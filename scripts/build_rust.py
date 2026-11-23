#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Compile ARM64 Rust native binaries for KSU Ultimate Gaming X (pure std, zero external crates)."""

from __future__ import annotations

import os
import platform
import shutil
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
IS_WIN = os.name == "nt"


def find_rustc() -> Path:
    found = shutil.which("rustc")
    if found:
        return Path(found)
    return Path.home() / ".cargo" / "bin" / ("rustc.exe" if IS_WIN else "rustc")


def find_ndk_bin() -> Path:
    candidates: list[Path] = []
    for env_key in ("ANDROID_NDK_HOME", "ANDROID_NDK_ROOT", "ANDROID_NDK_LATEST_HOME"):
        val = os.environ.get(env_key)
        if val:
            candidates.append(Path(val))

    sdk_candidates = [
        os.environ.get("ANDROID_SDK_ROOT"),
        os.environ.get("ANDROID_HOME"),
        r"C:\Android\sdk" if IS_WIN else None,
        str(Path.home() / "Android" / "Sdk"),
        "/usr/local/lib/android/sdk",
    ]
    for sc in sdk_candidates:
        if not sc:
            continue
        ndk_parent = Path(sc) / "ndk"
        if ndk_parent.is_dir():
            pref = ndk_parent / "29.0.14206865"
            if pref.is_dir():
                candidates.append(pref)
            for child in sorted(ndk_parent.iterdir(), reverse=True):
                if child.is_dir() and child != pref:
                    candidates.append(child)

    host_tags = (
        ["windows-x86_64"]
        if IS_WIN
        else (["darwin-arm64", "darwin-x86_64"] if sys.platform == "darwin" else ["linux-x86_64"])
    )
    for ndk_dir in candidates:
        prebuilt = ndk_dir / "toolchains" / "llvm" / "prebuilt"
        if not prebuilt.is_dir():
            continue
        for tag in host_tags:
            bdir = prebuilt / tag / "bin"
            if bdir.is_dir():
                return bdir
        for child in sorted(prebuilt.iterdir()):
            bdir = child / "bin"
            if bdir.is_dir():
                return bdir

    raise RuntimeError(
        "Android NDK LLVM bin directory not found. Set ANDROID_NDK_HOME or install NDK under ANDROID_SDK_ROOT/ndk."
    )


RUSTC = find_rustc()
NDK_BIN = find_ndk_bin()
LINKER = NDK_BIN / ("aarch64-linux-android29-clang.cmd" if IS_WIN else "aarch64-linux-android29-clang")
CLANGXX = NDK_BIN / ("aarch64-linux-android29-clang++.cmd" if IS_WIN else "aarch64-linux-android29-clang++")
STRIP = NDK_BIN / ("llvm-strip.exe" if IS_WIN else "llvm-strip")


def verify_aarch64_elf(path: Path, required_symbol: bytes | None = None) -> None:
    data = path.read_bytes()
    if data[:4] != b"\x7fELF":
        raise RuntimeError(f"Not a valid ELF binary: {path}")
    e_machine = struct.unpack("<H", data[18:20])[0]
    if e_machine != 183:
        raise RuntimeError(f"Expected AArch64 ELF (183) for {path}, got {e_machine}")
    if required_symbol and required_symbol not in data:
        raise RuntimeError(f"Missing expected symbol {required_symbol!r} in {path}")


def run_rustc(args: list[str], out_path: Path) -> None:
    if not RUSTC.is_file():
        raise RuntimeError(f"rustc not found at {RUSTC}")
    if not LINKER.is_file():
        raise RuntimeError(f"NDK linker not found at {LINKER}")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        str(RUSTC),
        "--edition=2021",
        "--target", "aarch64-linux-android",
        "-C", f"linker={LINKER}",
        "-C", "opt-level=z",
        "-C", "lto=yes",
        "-C", "panic=abort",
        "-C", "strip=none",
    ] + args + ["-o", str(out_path)]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"rustc failed for {out_path}:\n{res.stdout}\n{res.stderr}")
    if STRIP.is_file():
        subprocess.run([str(STRIP), "--strip-unneeded", str(out_path)], check=True)
    print(f"Built Rust ARM64 artifact: {out_path} ({out_path.stat().st_size} bytes)")


def build_zygisk_shield() -> None:
    if not CLANGXX.is_file():
        raise RuntimeError(f"NDK C++ compiler not found at {CLANGXX}")
    src = ROOT / "companion" / "zygisk-spoof" / "src" / "main.cpp"
    inc = ROOT / "companion" / "zygisk-spoof" / "include"
    out_so = ROOT / "module" / "zygisk" / "arm64-v8a.so"
    out_so.parent.mkdir(parents=True, exist_ok=True)

    cmd = [
        str(CLANGXX),
        "-std=c++17",
        "-shared",
        "-fPIC",
        "-O2",
        "-fvisibility=hidden",
        "-fno-exceptions",
        "-fno-rtti",
        "-Wall",
        "-Wextra",
        f"-I{inc}",
        str(src),
        "-static-libstdc++",
        "-llog",
        "-ldl",
        "-o",
        str(out_so),
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"clang++ failed for {out_so}:\n{res.stdout}\n{res.stderr}")
    if STRIP.is_file():
        subprocess.run([str(STRIP), "--strip-unneeded", str(out_so)], check=True)
    verify_aarch64_elf(out_so, b"zygisk_module_entry")
    elf_bytes = out_so.read_bytes()
    if b"libc++_shared.so" in elf_bytes:
        raise RuntimeError("arm64-v8a.so must NOT dynamically depend on libc++_shared.so!")
    for sym in (b"com.android.settings", b"spoof_denylist.list"):
        if sym not in elf_bytes:
            raise RuntimeError(f"Missing expected symbol {sym!r} in {out_so}")
    print(f"Built Zygisk ARM64 shield: {out_so} ({out_so.stat().st_size} bytes)")


def main() -> int:
    # 1. Module ARM64 Rust telemetry core -> module/bin/kgx-core
    kgx_core_src = ROOT / "companion" / "rust-core" / "src" / "main.rs"
    kgx_core_out = ROOT / "module" / "bin" / "kgx-core"
    run_rustc([str(kgx_core_src)], kgx_core_out)
    verify_aarch64_elf(kgx_core_out)

    # 2. Zygisk Stock-Identity & Denylist Shield -> module/zygisk/arm64-v8a.so
    build_zygisk_shield()

    # 3. Android APK JNI cdylib -> companion/android-app/jniLibs/arm64-v8a/libkgx_rust.so
    jni_src = ROOT / "companion" / "android-app" / "rust-jni" / "src" / "lib.rs"
    if jni_src.is_file():
        jni_out = ROOT / "companion" / "android-app" / "jniLibs" / "arm64-v8a" / "libkgx_rust.so"
        run_rustc(["--crate-type=cdylib", str(jni_src)], jni_out)
        verify_aarch64_elf(jni_out, b"Java_com_kgx_ultimate_RustBridge_nativeExec")

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
