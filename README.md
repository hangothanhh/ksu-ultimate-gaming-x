# KSU Ultimate Gaming X v1.0.0

All-in-one KernelSU gaming performance & hardware-isolation suite powered by a **native ARM64 Rust Daemon (`kgx-core`)**, **Zygisk PLT+JNI Stock-Identity Shield (`arm64-v8a.so`)**, and a standalone **Material 3 Rust Companion App (`KSU-Ultimate-Gaming-X-v1.0.0.apk`)**.

## Core Features

1. **Zero-Lock Rust Native Daemon & Scene-Style Telemetry Overlay**
   - Native ARM64 `kgx-core` daemon monitors foreground games, thermals, clocks, battery power (`mW` / `mA`), RAM pressure, and SurfaceFlinger frame flips with sub-millisecond reads (`ov_layer.cache` + sysfs fast paths).
   - Floating `KgxOverlayService` HUD displays live FPS, CPU/GPU usage, frequencies, temperatures, RAM usage, and power draw, with click-through lock, 1-tap CSV session recording (`SessionRecorder`), and in-app curve charts (`TelemetryChartView`).
   - Quick Settings Tiles for switching Modes, Bypass Charging, and Floating FPS Overlay.

2. **Whole-System Flagship Spoof + Zygisk Stock-Identity Shield & Denylist**
   - Safe `resetprop` flagship device profiles (without altering `ro.build.fingerprint`, `ro.serialno`, bootloader, or verified boot state).
   - Zygisk API v4 companion & PLT/JNI hooks (`__system_property_get`, `__system_property_read`, `__system_property_read_callback`, `android/os/SystemProperties`) automatically restore genuine stock identity for Google Play Services / Wallet / Vending (`PLAY_INTEGRITY_SHIELD`), Android/OEM Settings (`SPOOF_EXCLUDE_SETTINGS=1`), and any user-selected packages in `spoof_denylist.list`.

3. **Samsung Exynos / One UI Game Stability & LTPO 120Hz Refresh-Rate Guard**
   - **Primary-Display LTPO 120Hz Isolation**: Separates internal panel modes (`type INTERNAL` / `FLAG_DEFAULT_DISPLAY`, with `SurfaceFlinger` & DRM sysfs fallbacks) from external HDMI / Virtual DeX displays, never downgrades `hw_profile.env`, sanitizes fractional `120.1` overrides (`120.0`), enforces `refresh_rate_mode=1` on One UI, and auto-recovers cleanly on boot or `SIGTERM`/`SIGINT`/`SIGHUP` soft-reboot.
   - **Samsung GOS Neutralizer & Sustained Sweet-Spot**: Safely neutralizes GOS, maintains cool sustained Exynos 2200 ceilings (~82% peak), protects `gpu_ifpo_control`, avoids runtime `PlatformCompat killUid` crashes on running games, and supports hysteresis-guarded **Bypass Charging**.
   - **External Display & DeX Toolkit**: Auto internal screen-off on external monitors (`kgx-display.dex` / backlight fallback), system-wide or per-game `wm size`/`density` override (`ext_scrcpy` / `always`), and View/DeX-safe `cgroup.freeze` v2 app freezer.

## Repository Layout

- `module/` — Flashable KernelSU module (`service.sh`, `post-fs-data.sh`, `customize.sh`, `bin/kgxctl`, `bin/kgx-core`, `lib/*.sh`, `zygisk/arm64-v8a.so`, `data/*.tsv`/`json`).
- `companion/rust-core/` — Native AArch64 Rust binary (`kgx-core`).
- `companion/zygisk-spoof/` — C++17 Zygisk v4 Stock-Identity & Denylist Shield (`arm64-v8a.so`).
- `companion/android-app/` — Zero-Gradle Material 3 Companion APK (`aapt2` + `javac` + `d8`) + Rust JNI bridge (`libkgx_rust.so`).
- `companion/display-helper/` — `DisplayPowerCtrl` helper DEX (`kgx-display.dex`).
- `scripts/` — Deterministic builders (`build_rust.py`, `build_apk.py`, `build_zip.py`).
- `tests/verify_all.py` — 7-stage syntax, POSIX hygiene, database, mock E2E (Adreno/Mali/Exynos), APK API, ZIP, and ELF verification suite.

## Build & Verify

```powershell
python -u scripts/build_rust.py
python -u scripts/build_apk.py
python -u scripts/build_zip.py
python -u tests/verify_all.py
```

## Release Artifacts (`v1.0.0`)

Download from **GitHub Releases (`v1.0.0`)**:
- KernelSU Module ZIP: `KSU-Ultimate-Gaming-X-v1.0.0.zip` (+ `.sha256`)
- Companion APK: `KSU-Ultimate-Gaming-X-v1.0.0.apk` (+ `.sha256`)
