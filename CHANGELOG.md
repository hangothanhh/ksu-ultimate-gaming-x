# Changelog

> **Language**: **English** | [Tiếng Việt](docs/vi/CHANGELOG.md)

All notable changes to **KSU Ultimate Gaming X** are documented in this file based on verified source changes and test results.

---

## [Unreleased] (Post-v1.0.0 Governance & Reproducible Build Update)

### Added
- Added [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) (+ [docs/vi/CODE_OF_CONDUCT.md](docs/vi/CODE_OF_CONDUCT.md)), [.gitattributes](.gitattributes), KernelSU Manager OTA feed [update.json](update.json), and tag-triggered draft workflow `.github/workflows/release.yml`.
- Added `SPDX-License-Identifier: GPL-3.0-or-later` headers across all 43 project-authored source files (preserving [companion/zygisk-spoof/include/zygisk.hpp](companion/zygisk-spoof/include/zygisk.hpp) unmodified).
- Bundled `LICENSE` and `NOTICE` directly inside both `KSU-Ultimate-Gaming-X-v1.0.0.zip` and Companion APK `assets/` via `build_zip.py` / `build_apk.py` (enforced by `tests/verify_all.py` Stages 6–7).

### Changed
- Switched repository license on `main` from MIT to **GNU General Public License v3.0 or later (`GPL-3.0-or-later`)** while keeping release binary version `v1.0.0` unchanged; updated [NOTICE](NOTICE) with static toolchain runtime licenses (`MIT OR Apache-2.0` for Rust `std`, `Apache-2.0 WITH LLVM-exception` for NDK `libc++`) and `module/module.prop` (`author=hangothanhh`, `updateJson`).
- Credited **Google Antigravity**'s documentation and engineering assistance inside [README.md](README.md), [NOTICE](NOTICE), and [AI_CONTRIBUTIONS.md](AI_CONTRIBUTIONS.md) (documentation-only attribution without Git bot `Co-authored-by:` trailers).
- Promoted **English** as the primary documentation language across root files, `docs/*.md`, and `.github/` templates, with full Vietnamese translations preserved under [README.vi.md](README.vi.md) and `docs/vi/`.
- Aligned [companion/zygisk-spoof/README.md](companion/zygisk-spoof/README.md) with the actual Stock-Identity & Denylist Shield implementation (`KGX_PIShield`, `spoof_denylist.list`).
- Made [scripts/build_rust.py](scripts/build_rust.py), [scripts/build_apk.py](scripts/build_apk.py), and [tests/verify_all.py](tests/verify_all.py) cross-platform across Windows and Linux/macOS, and **removed all 4 prebuilt ARM64/DEX binaries from Git tracking** in favor of clean from-source compilation in CI.

### Security
- Hardened `.github/workflows/ci.yml` to compile Rust, Zygisk C++, Display DEX, APK, and ZIP cleanly from source on `ubuntu-latest`, run all 7 verification stages, enforce zero committed binaries/keys, and pin all third-party GitHub Actions (Node 24 releases) by exact commit SHA.

---

## v1.0.0 (2026-11-22)

Initial public release (`versionCode=100`, tag `v1.0.0`).

### Added
- **KernelSU Module Engine (`module/`)**:
  - `post-fs-data.sh` (bootloop guard triggering `SAFE_MODE=1` and resetting `system.prop` after 2 consecutive failed boots) and `service.sh` (hardware detection, crash/reboot session recovery, daemon launch).
  - Unified JSON CLI `bin/kgxctl`: `status`, `hw`, `games`, `profiles`, `spoof`, `engine`, `touch`, `net`, `backup`, `logs`, `safemode`, `daemon`, `system`, `rollback`, `display`, `overlay-tick`, `freezer`, and redacted `diag`.
  - 16 POSIX shell libraries (`lib/*.sh`): `hw_detect.sh`, `spoof.sh`, `display.sh`, `fps.sh`, `thermal.sh`, `cpu_gpu.sh`, `ram.sh`, `touch.sh`, `power.sh`, `gos.sh`, `freezer.sh`, `network.sh`, `backup.sh`, `matcher.sh`, `session.sh`, `common.sh`.
- **Native ARM64 Rust Daemon (`companion/rust-core/`)**:
  - `bin/kgx-core`: low-overhead telemetry reader (CPU/GPU/RAM/PSI/battery `mW`/`mA`, SurfaceFlinger FPS + 1% Low with `ov_layer.cache`), real-time thermal/bypass/freezer management, and `SIGTERM`/`SIGINT`/`SIGHUP` restoration handling.
- **Zygisk Stock-Identity & Denylist Shield (`companion/zygisk-spoof/`)**:
  - `zygisk/arm64-v8a.so` (Zygisk API v4, `-static-libstdc++`, zero `libc++_shared.so` dependency).
  - Restores stock device properties for Google Play Services / Play Store / GSF / Wallet (`PLAY_INTEGRITY_SHIELD`), Android/OEM Settings apps (`SPOOF_EXCLUDE_SETTINGS=1`), and user-selected `spoof_denylist.list` packages.
- **Standalone Companion APK (`companion/android-app/`)**:
  - Zero-Gradle Material 3 Android app (`aapt2` + `javac` + `d8` + `zipalign` + `apksigner`) with Rust JNI bridge (`libkgx_rust.so`), live Dashboard, game/profile selector, Spoof Denylist picker, lockable Scene FPS Overlay (`KgxOverlayService`), CSV recorder & chart viewer (`SessionRecorder`, `TelemetryChartView`), and 3 Quick Settings Tiles (`KgxModeTileService`, `KgxBypassTileService`, `KgxOverlayTileService`).
- **Automated Verification & CI**:
  - 7-stage verification suite `tests/verify_all.py` (POSIX `sh -n`, LF/anti-bashism hygiene, 34-device / 31-game DB validation, Adreno/Mali/Exynos E2E mocks, APK audit, ZIP/ELF/SHA-256 verification).
  - GitHub Actions workflow `.github/workflows/ci.yml` validating Module ZIP packaging + Stages 1–6 (`--skip-apk`).

### Changed
- Migrated UI completely from legacy WebUI (`module/webroot` removed) to the Standalone Companion APK.
- Standardized build outputs and metadata at `v1.0.0` (`KSU-Ultimate-Gaming-X-v1.0.0.zip` and `KSU-Ultimate-Gaming-X-v1.0.0.apk`).
- Updated `scripts/build_apk.py` with environment variable signing overrides (`KGX_KEYSTORE_*`) while keeping local debug keystores gitignored.

### Fixed
- **Mid-game crashes on Android 12+**: Avoided invoking `cmd game` / `device_config` while a game process is alive (prevents `PlatformCompat.putOverridesOnReleaseBuilds()` calling `killUid()`); removed `am kill-all`.
- **Auto-reboot (`SError 0xbe000011`) on Exynos 2200**: Stopped writing `/sys/kernel/gpu/gpu_ifpo_control` and protected `*ifpo*` in `kgx_is_protected_sysfs()`.
- **60Hz drops & stuck 60Hz after Soft/Hard Reboot (Galaxy S22 LTPO / One UI 4.1)**:
  - Isolated primary display modes (`type INTERNAL` / `FLAG_DEFAULT_DISPLAY`), excluding external HDMI/DeX rates (50/70/75Hz).
  - Redirected `dumpsys` output to temp files to prevent `mksh` `/system/bin/printf: Argument list too long` (~128KB argv limit).
  - Added `dumpsys SurfaceFlinger` + kernel DRM/panel `vrr` sysfs fallbacks, downgrade guards for `hw_profile.env`, and self-healing in `hw_load()` & Rust `kgx-core`.
  - Sanitized SamHelper `120.1 -> 120.0`, enforced `refresh_rate_mode=1` for >= 90Hz, and added `display_recover_on_boot` + `call_kgxctl_cleanup()`.
- **Zygisk PLT hook filtering**: Restricted `pltHookRegister` to executable `.so` mappings only (excluding `.apk`/`.odex`/`.vdex`).

### Removed
- Removed legacy `module/webroot` WebUI.
- Removed `cmd netpolicy` and `am kill-all` usage (enforced by `tests/verify_all.py`).

### Security
- Enforced hard guards against altering `ro.serialno`, `ro.boot.*`, `ro.crypto.*`, `ro.debuggable`, `ro.secure`, `ro.adb.secure`, IMEI, or MAC in shell and Zygisk C++.
- Added `kgxctl diag` auto-redacting serials, IMEIs, MACs, emails, private/public IPs (keeping public DNS ping targets like `1.1.1.1`), and tokens/passwords.
- Ignored `*.keystore`, `*.jks`, `*.idsig`, `dist/`, and `module/system.prop` via `.gitignore`.

### Known Issues
- **120 FPS in Samsung DeX on <= 75Hz external displays**: Games such as *Delta Force Mobile* query the refresh rate of the `Display` hosting the window (`Display #2` DeX). Run the game on the internal `120Hz` screen (`Display #0`) to access high-FPS toggles.
- **`ksud soft-reboot` on Samsung with Wi-Fi ADB**: May drop Wi-Fi ADB connections or hit Samsung system/camera watchdogs if background services conflict.
- **Physical Hardware Verification Coverage**: Verified directly only on Samsung Galaxy S22 Exynos (`SM-S901B`, Android 12 / One UI 4.1); Adreno and Mali paths are mock-verified only.

### Compatibility
- `VERIFIED`: Samsung Galaxy S22 Exynos (`SM-S901B`, `r0s`, `s5e9925`, Android 12 / API 31, One UI 4.1, KernelSU temproot + ReZygisk).
- `PARTIAL`: Qualcomm Adreno & MediaTek Mali (POSIX mock verified via `tests/verify_all.py` only).
- `UNSUPPORTED`: 32-bit ARMv7, Android < 8.0 (API < 26), legacy WebUI.
