# Build from Source & Verification Guide

> **Language**: **English** | [Tiếng Việt](vi/development.md)

## 1. Purpose
Instructions for developers compiling the KernelSU Module ZIP, ARM64 Rust binaries (`kgx-core`, `libkgx_rust.so`), C++17 Zygisk library (`arm64-v8a.so`), and Companion Android APK (`KSU-Ultimate-Gaming-X-v1.0.0.apk`) directly from source.

---

## 2. Verified Build Toolchain
Derived from [scripts/build_rust.py](../scripts/build_rust.py), [scripts/build_apk.py](../scripts/build_apk.py), [scripts/build_zip.py](../scripts/build_zip.py), and [tests/verify_all.py](../tests/verify_all.py):

| Component | Verified Requirement | Notes |
|---|---|---|
| **Operating System** | Windows 10/11 *(full build + 7 stages)*; Linux `ubuntu-latest` *(ZIP build + CI Stages 1–6)* | `build_rust.py` / `build_apk.py` default to Windows paths (with SDK/Java env overrides) |
| **Python** | Python 3.12+ | Standard library only (zero pip dependencies) |
| **Rust Toolchain** | `rustc` with `aarch64-linux-android` target | Pure `std`, zero external crates |
| **Android NDK** | NDK `29.0.14206865` (`aarch64-linux-android29-clang`, `clang++`, `llvm-strip`) | Links C++ Zygisk with `-static-libstdc++ -llog -ldl` |
| **Android SDK** | Platform `android-34` (`android.jar`) & Build-Tools `34.0.0` (`aapt2`, `d8`, `zipalign`, `apksigner`) | Respects `ANDROID_SDK_ROOT` / `ANDROID_HOME` |
| **Java JDK** | OpenJDK 17 (`javac`, `keytool`) | Compiles Java 8 bytecode (no Gradle/CMake required) |
| **POSIX Shell (Tests)** | Git for Windows `sh.exe` (or `/bin/sh` + `awk` + `tar` on Linux) | Powers Stage 1–6 POSIX verification |
| **Disk Space** | ~2 GB (including Android SDK + NDK + Rust toolchain) | Repository source + artifacts are < 5 MB |

---

## 3. Build & Verification Steps

### Step 1: Clone Repository
```sh
git clone https://github.com/hangothanhh/ksu-ultimate-gaming-x.git
cd ksu-ultimate-gaming-x
```
*(No Git submodules are used.)*

### Step 2: Compile Rust & Zygisk ARM64 Binaries (Windows with NDK + Rust)
```powershell
python -u scripts/build_rust.py
```
Builds:
1. `companion/rust-core/src/main.rs` → `module/bin/kgx-core` (AArch64 ELF)
2. `companion/zygisk-spoof/src/main.cpp` → `module/zygisk/arm64-v8a.so` (Zygisk API v4 SO, no `libc++_shared.so` dependency)
3. `companion/android-app/rust-jni/src/lib.rs` → `companion/android-app/jniLibs/arm64-v8a/libkgx_rust.so`

### Step 3: Build Display Helper DEX & Companion APK
*(Optionally sign with your own release keystore via environment variables; otherwise generates a local gitignored debug keystore at `companion/android-app/kgx.keystore`):*
```powershell
# Optional release signing overrides:
# $env:KGX_KEYSTORE_PATH = "C:\path\to\your-release.keystore"
# $env:KGX_KEYSTORE_PASS = "..."
# $env:KGX_KEY_PASS = "..."
# $env:KGX_KEY_ALIAS = "..."

python -u scripts/build_apk.py
```
Outputs:
- `module/data/kgx-display.dex`
- `dist/KSU-Ultimate-Gaming-X-v1.0.0.apk` + `.sha256`

### Step 4: Package Deterministic KernelSU Module ZIP (Windows or Linux)
```sh
python3 -u scripts/build_zip.py
```
Outputs:
- `dist/KSU-Ultimate-Gaming-X-v1.0.0.zip` + `.sha256`
- Enforces LF (`\n`), strips UTF-8 BOM, applies UNIX permissions (`0755` scripts/binaries, `0644` data/SO), and forbids `module/system.prop` or `module/webroot`.

### Step 5: Run Verification Suite
- **Full 7-stage suite (requires built APK in `dist/`)**:
  ```powershell
  python -u tests/verify_all.py
  ```
- **Stages 1–6 (Linux CI or Module ZIP only)**:
  ```sh
  python3 -u tests/verify_all.py --skip-apk
  ```

### Step 6: Inspect Output Checksums (SHA-256)
- **Windows (PowerShell)**:
  ```powershell
  Get-FileHash dist\KSU-Ultimate-Gaming-X-v1.0.0.zip, dist\KSU-Ultimate-Gaming-X-v1.0.0.apk -Algorithm SHA256
  ```
- **Linux**:
  ```sh
  sha256sum dist/KSU-Ultimate-Gaming-X-v1.0.0.zip dist/KSU-Ultimate-Gaming-X-v1.0.0.apk
  ```

---

## 4. Note for Linux Cross-Compilation
Default NDK/SDK/JDK paths inside `build_rust.py` (`.cmd`/`.exe`) and `build_apk.py` (`*.bat`/`.exe`) target the maintainer's Windows host. On Linux, adjust tool binary names without `.cmd`/`.bat`/`.exe` extensions, or rely on GitHub Actions CI for Module ZIP packaging and Stages 1–6 (`--skip-apk`).
