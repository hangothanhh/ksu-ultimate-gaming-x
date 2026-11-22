#!/usr/bin/env python3
"""Deterministic KernelSU module ZIP packager for KSU Ultimate Gaming X."""

from __future__ import annotations

import hashlib
import os
import stat
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODULE_DIR = ROOT / "module"
DIST_DIR = ROOT / "dist"
ZIP_NAME = "KSU-Ultimate-Gaming-X-v1.0.0.zip"

TEXT_EXTS = {
    ".sh", ".prop", ".tsv", ".json", ".conf", ".list",
    ".html", ".css", ".js", ".md", ".txt",
}
EXEC_FILES = {
    "customize.sh",
    "post-fs-data.sh",
    "service.sh",
    "action.sh",
    "uninstall.sh",
    "bin/kgxctl",
    "bin/kgx-core",
    "bin/gaming_daemon.sh",
    "META-INF/com/google/android/update-binary",
}

FIXED_DATE_TIME = (2026, 11, 22, 0, 0, 0)


def is_executable(rel_posix: str) -> bool:
    if rel_posix in EXEC_FILES:
        return True
    if rel_posix.startswith("lib/") and rel_posix.endswith(".sh"):
        return True
    if rel_posix.startswith("bin/"):
        return True
    return False


def is_text_file(rel_posix: str) -> bool:
    name = rel_posix.rsplit("/", 1)[-1]
    if name in {"kgxctl", "update-binary", "updater-script"}:
        return True
    return Path(name).suffix.lower() in TEXT_EXTS


def build_zip() -> Path:
    if not MODULE_DIR.is_dir():
        raise RuntimeError(f"Module directory not found: {MODULE_DIR}")

    DIST_DIR.mkdir(parents=True, exist_ok=True)
    zip_path = DIST_DIR / ZIP_NAME
    sha_path = DIST_DIR / f"{ZIP_NAME}.sha256"

    all_dirs: set[str] = set()
    all_files: list[Path] = []
    for p in sorted(MODULE_DIR.rglob("*")):
        rel = p.relative_to(MODULE_DIR).as_posix()
        if rel == "system.prop":
            raise RuntimeError("module/system.prop must not be pre-baked; customize.sh/spoof.sh creates it dynamically.")
        if rel == "webroot" or rel.startswith("webroot/"):
            raise RuntimeError("module/webroot must not exist; UI moved to standalone Rust Companion APK.")
        if p.is_dir():
            all_dirs.add(rel)
        elif p.is_file():
            all_files.append(p)
            parts = rel.split("/")[:-1]
            for i in range(1, len(parts) + 1):
                all_dirs.add("/".join(parts[:i]))

    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for d in sorted(all_dirs):
            zi = zipfile.ZipInfo(d.rstrip("/") + "/", date_time=FIXED_DATE_TIME)
            zi.create_system = 3  # UNIX
            zi.external_attr = ((stat.S_IFDIR | 0o755) << 16) | 0x10
            zf.writestr(zi, b"")

        for f in sorted(all_files, key=lambda p: p.relative_to(MODULE_DIR).as_posix()):
            rel = f.relative_to(MODULE_DIR).as_posix()
            raw = f.read_bytes()
            if is_text_file(rel):
                raw = raw.replace(b"\r\n", b"\n")
                if raw.startswith(b"\xef\xbb\xbf"):
                    raw = raw[3:]

            mode = 0o755 if is_executable(rel) else 0o644
            zi = zipfile.ZipInfo(rel, date_time=FIXED_DATE_TIME)
            zi.create_system = 3  # UNIX
            zi.external_attr = (stat.S_IFREG | mode) << 16
            zi.compress_type = zipfile.ZIP_DEFLATED
            zf.writestr(zi, raw)
            print(f"  + {rel:<52} mode={oct(mode)} size={len(raw)}")

    digest = hashlib.sha256(zip_path.read_bytes()).hexdigest()
    sha_path.write_text(f"{digest}  {ZIP_NAME}\n", encoding="utf-8", newline="\n")

    print(f"\nBuilt: {zip_path} ({zip_path.stat().st_size} bytes)")
    print(f"SHA256: {digest}")
    return zip_path


if __name__ == "__main__":
    try:
        build_zip()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
