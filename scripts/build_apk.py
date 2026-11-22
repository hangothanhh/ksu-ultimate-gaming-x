#!/usr/bin/env python3
"""Standalone SDK APK builder for KSU Gaming X v1.0.0 (Zero Gradle; aapt2 + javac + d8 + zipalign + apksigner)."""

from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP_DIR = ROOT / "companion" / "android-app"
HELPER_DIR = ROOT / "companion" / "display-helper"
MODULE_DATA_DIR = ROOT / "module" / "data"
DIST_DIR = ROOT / "dist"
APK_NAME = "KSU-Ultimate-Gaming-X-v1.0.0.apk"

SDK_ROOT = Path(os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME") or r"C:\Android\sdk")
BUILD_TOOLS = SDK_ROOT / "build-tools" / "34.0.0"
PLATFORM_JAR = SDK_ROOT / "platforms" / "android-34" / "android.jar"

AAPT2 = BUILD_TOOLS / "aapt2.exe"
D8 = BUILD_TOOLS / "d8.bat"
ZIPALIGN = BUILD_TOOLS / "zipalign.exe"
APKSIGNER = BUILD_TOOLS / "apksigner.bat"
JAVAC = Path(os.environ.get("JAVA_HOME", r"C:\Program Files\Microsoft\jdk-17.0.21.21-hotspot")) / "bin" / "javac.exe"
KEYTOOL = Path(os.environ.get("JAVA_HOME", r"C:\Program Files\Microsoft\jdk-17.0.21.21-hotspot")) / "bin" / "keytool.exe"

# Local development debug keystore fallback only (ignored in .gitignore).
# For custom release signing, set KGX_KEYSTORE_PATH / KGX_KEYSTORE_PASS / KGX_KEY_PASS / KGX_KEY_ALIAS.
KEYSTORE = Path(os.environ.get("KGX_KEYSTORE_PATH") or str(APP_DIR / "kgx.keystore"))
KS_PASS = os.environ.get("KGX_KEYSTORE_PASS", "kgxultimate")
KEY_PASS = os.environ.get("KGX_KEY_PASS", KS_PASS)
KEY_ALIAS = os.environ.get("KGX_KEY_ALIAS", "kgxkey")


def find_exe(preferred: Path, name: str) -> str:
    if preferred.is_file():
        return str(preferred)
    found = shutil.which(name)
    if found:
        return found
    raise RuntimeError(f"Required tool not found: {preferred} / {name}")


def run(cmd: list[str], cwd: Path | None = None) -> None:
    res = subprocess.run(cmd, cwd=str(cwd) if cwd else None, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"Command failed ({res.returncode}): {' '.join(cmd)}\n{res.stdout}\n{res.stderr}")


def ensure_keystore(keytool_bin: str) -> None:
    if KEYSTORE.is_file():
        return
    KEYSTORE.parent.mkdir(parents=True, exist_ok=True)
    run([
        keytool_bin, "-genkeypair", "-v",
        "-keystore", str(KEYSTORE),
        "-alias", KEY_ALIAS,
        "-keyalg", "RSA",
        "-keysize", "2048",
        "-validity", "10000",
        "-storepass", KS_PASS,
        "-keypass", KEY_PASS,
        "-dname", "CN=KSU Ultimate Gaming X Dev, OU=Engineering, O=KGX, C=VN",
    ])


def build_display_dex(javac: str, d8: str) -> Path:
    src = HELPER_DIR / "src" / "com" / "kgx" / "display" / "DisplayPowerCtrl.java"
    if not src.is_file():
        raise RuntimeError(f"DisplayPowerCtrl source missing: {src}")
    MODULE_DATA_DIR.mkdir(parents=True, exist_ok=True)
    out_dex = MODULE_DATA_DIR / "kgx-display.dex"
    with tempfile.TemporaryDirectory(prefix="kgx_disp_dex_") as tmp_dir:
        tmp = Path(tmp_dir)
        cls_dir = tmp / "classes"
        dex_dir = tmp / "dex"
        cls_dir.mkdir()
        dex_dir.mkdir()
        run([
            javac,
            "-source", "8",
            "-target", "8",
            "-Xlint:-options",
            "-encoding", "UTF-8",
            "-classpath", str(PLATFORM_JAR),
            "-d", str(cls_dir),
            str(src),
        ])
        class_files = [str(p) for p in sorted(cls_dir.rglob("*.class"))]
        run([
            d8,
            "--min-api", "26",
            "--lib", str(PLATFORM_JAR),
            "--output", str(dex_dir),
            *class_files,
        ])
        built_dex = dex_dir / "classes.dex"
        if not built_dex.is_file():
            raise RuntimeError("d8 did not produce display helper classes.dex")
        shutil.copyfile(built_dex, out_dex)
    print(f"Built display helper DEX: {out_dex} ({out_dex.stat().st_size} bytes)")
    return out_dex


def build_apk() -> Path:
    aapt2 = find_exe(AAPT2, "aapt2")
    d8 = find_exe(D8, "d8")
    zipalign = find_exe(ZIPALIGN, "zipalign")
    apksigner = find_exe(APKSIGNER, "apksigner")
    javac = find_exe(JAVAC, "javac")
    keytool = find_exe(KEYTOOL, "keytool")

    jni_so = APP_DIR / "jniLibs" / "arm64-v8a" / "libkgx_rust.so"
    if not jni_so.is_file():
        raise RuntimeError(f"Rust JNI library missing: {jni_so}. Run scripts/build_rust.py first.")
    if not PLATFORM_JAR.is_file():
        raise RuntimeError(f"Android SDK platform jar missing: {PLATFORM_JAR}")

    ensure_keystore(keytool)
    build_display_dex(javac, d8)
    DIST_DIR.mkdir(parents=True, exist_ok=True)
    out_apk = DIST_DIR / APK_NAME
    sha_path = DIST_DIR / f"{APK_NAME}.sha256"

    with tempfile.TemporaryDirectory(prefix="kgx_apk_") as tmp_dir:
        tmp = Path(tmp_dir)
        res_zip = tmp / "compiled_res.zip"
        gen_src = tmp / "gen"
        classes_dir = tmp / "classes"
        dex_dir = tmp / "dex"
        base_apk = tmp / "base.apk"
        unsigned_apk = tmp / "unsigned.apk"
        aligned_apk = tmp / "aligned.apk"
        gen_src.mkdir()
        classes_dir.mkdir()
        dex_dir.mkdir()

        # 1. Compile XML resources
        run([aapt2, "compile", "--dir", str(APP_DIR / "res"), "-o", str(res_zip)])

        # 2. Link resources + manifest -> base.apk + R.java
        run([
            aapt2, "link",
            "-o", str(base_apk),
            "-I", str(PLATFORM_JAR),
            "--manifest", str(APP_DIR / "AndroidManifest.xml"),
            "--java", str(gen_src),
            "-R", str(res_zip),
            "--auto-add-overlay",
        ])

        # 3. Compile Java sources + generated R.java
        java_files = [str(p) for p in sorted((APP_DIR / "java").rglob("*.java"))] + [
            str(p) for p in sorted(gen_src.rglob("*.java"))
        ]
        run([
            javac,
            "-source", "8",
            "-target", "8",
            "-Xlint:-options",
            "-encoding", "UTF-8",
            "-classpath", str(PLATFORM_JAR),
            "-d", str(classes_dir),
            *java_files,
        ])

        # 4. Dex compiled classes with d8
        class_files = [str(p) for p in sorted(classes_dir.rglob("*.class"))]
        run([
            d8,
            "--min-api", "26",
            "--lib", str(PLATFORM_JAR),
            "--output", str(dex_dir),
            *class_files,
        ])
        classes_dex = dex_dir / "classes.dex"
        if not classes_dex.is_file():
            raise RuntimeError("d8 did not produce classes.dex")

        # 5. Merge base.apk + classes.dex + STORED Rust ARM64 libkgx_rust.so cleanly
        with zipfile.ZipFile(base_apk, "r") as zin, zipfile.ZipFile(unsigned_apk, "w") as zout:
            for item in zin.infolist():
                data = zin.read(item.filename)
                comp = zipfile.ZIP_STORED if item.filename == "resources.arsc" else zipfile.ZIP_DEFLATED
                zi = zipfile.ZipInfo(item.filename, date_time=(2026, 11, 22, 0, 0, 0))
                zi.compress_type = comp
                zout.writestr(zi, data)

            zi_dex = zipfile.ZipInfo("classes.dex", date_time=(2026, 11, 22, 0, 0, 0))
            zi_dex.compress_type = zipfile.ZIP_DEFLATED
            zout.writestr(zi_dex, classes_dex.read_bytes())

            zi_so = zipfile.ZipInfo("lib/arm64-v8a/libkgx_rust.so", date_time=(2026, 11, 22, 0, 0, 0))
            zi_so.compress_type = zipfile.ZIP_STORED
            zout.writestr(zi_so, jni_so.read_bytes())

        # 6. Align (4-byte page alignment before signing)
        run([zipalign, "-f", "-p", "4", str(unsigned_apk), str(aligned_apk)])

        # 7. Sign & verify v2/v3 APK Signature
        run([
            apksigner, "sign",
            "--ks", str(KEYSTORE),
            "--ks-pass", f"pass:{KS_PASS}",
            "--key-pass", f"pass:{KEY_PASS}",
            "--ks-key-alias", KEY_ALIAS,
            "--out", str(out_apk),
            str(aligned_apk),
        ])
        run([apksigner, "verify", "--verbose", str(out_apk)])

    digest = hashlib.sha256(out_apk.read_bytes()).hexdigest()
    sha_path.write_text(f"{digest}  {APK_NAME}\n", encoding="utf-8", newline="\n")
    print(f"Built signed APK: {out_apk} ({out_apk.stat().st_size} bytes)")
    print(f"SHA256: {digest}")
    return out_apk


if __name__ == "__main__":
    try:
        build_apk()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
