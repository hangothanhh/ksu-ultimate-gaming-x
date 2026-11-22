# KSU Ultimate Gaming X (`v1.0.0`)

> **Language**: **English** | [Tiếng Việt](README.vi.md)

An all-in-one gaming performance engine, thermal coordinator, display refresh-rate guard, and whole-system device spoofing suite for **KernelSU** — powered by a **Native ARM64 Rust Daemon (`kgx-core`)**, a **Zygisk Stock-Identity Shield (`arm64-v8a.so`)**, and a **Standalone Material 3 Companion App (`KSU-Ultimate-Gaming-X-v1.0.0.apk`)**.

- **Current Version**: `v1.0.0` (`versionCode: 100`)
- **Development Status**: First public release (`VERIFIED` on Samsung Galaxy S22 Exynos; `PARTIAL` mock-verified for Adreno/Mali)
- **Target Platform**: Android ARM64 (`arm64-v8a`, Android 8.0+ / API >= 26; full GameManager features on Android 12+ / API >= 31)
- **Tech Stack**: POSIX Shell (`module/`), Native Rust ARM64 (`companion/rust-core`, zero external crates), C++17 Zygisk API v4 (`companion/zygisk-spoof`), Pure Android SDK Java + Rust JNI (`companion/android-app`)
- **Official Links**: [GitHub Releases](https://github.com/hangothanhh/ksu-ultimate-gaming-x/releases) · [Report Issues](https://github.com/hangothanhh/ksu-ultimate-gaming-x/issues) · [License (GNU GPLv3+)](LICENSE) · [CHANGELOG](CHANGELOG.md)

> [!WARNING]
> **AI Transparency & "AI Slop" Notice:**
> This project's codebase and documentation were developed with **assistance from Google Antigravity (AI coding assistant)**, then tested on physical hardware (Samsung Galaxy S22 Exynos, Android 12 / One UI 4.1) and verified through a 7-stage POSIX/mock test suite ([tests/verify_all.py](tests/verify_all.py)).
> - **"AI Slop" Warning**: AI-generated code or configurations may still contain subtle edge-case bugs on devices or ROMs that the maintainer **has not personally tested**. Do **not** treat a device's presence in the sample database as a compatibility guarantee.
> - Only items explicitly marked **`VERIFIED`** have been validated on physical hardware. Any Pull Request containing unverified AI-generated code will be rejected under [CONTRIBUTING.md](CONTRIBUTING.md).

---

## Quick Table of Contents
1. [What This Project Does](#what-this-project-does)
2. [Read Before Installing — Risk Warnings](#read-before-installing)
3. [Real-World Compatibility Matrix](#compatibility)
4. [Requirements](#requirements)
5. [Beginner Installation Guide (A → Z)](#installation-guide)
6. [Update, Rollback, Uninstall & Recovery](#update-rollback-uninstall--recovery)
7. [Usage, FAQ, Troubleshooting & Safe Diagnostics (`kgxctl diag`)](#troubleshooting--diagnostic-report)
8. [Repository Structure & Build from Source](#repository-structure--build-from-source)
9. [Credits, Contributing, License & Third-Party Notices](#contributing-license--credits)

---

<a id="what-this-project-does"></a>
## 1. What This Project Does

*Beginner note:* **KernelSU (KSU)** is a Linux kernel-level `root` solution for Android that loads modules dynamically without permanently modifying the read-only `/system` partition.

| Component | Purpose & How It Works | Status | Limits / How to Toggle | Detailed Guide |
|---|---|---|---|---|
| **Gaming Performance Engine & Rust Daemon (`kgx-core`)** | Auto-detects foreground games, applies per-game CPU/GPU profiles, pins render threads to `top-app`, selectively trims/optimizes RAM & I/O, and restores stock state on game exit or `SIGHUP`/`SIGTERM` | `VERIFIED` *(S22)* / `PARTIAL` *(Adreno/Mali mock)* | Never runs `am kill-all` or `cmd netpolicy`; toggle via `AUTO_OPTIMIZE` (App or `kgxctl`) | [docs/gaming-engine.md](docs/gaming-engine.md) |
| **5-Factor FPS Compatibility Engine** | Computes realistic achievable FPS via $\min(\text{Requested}, \text{Game Cap}, \text{Display Hz}, \text{Thermal Cap})$; pre-applies `cmd game` / `downscale` only when the game is **not running** to prevent `PlatformCompat killUid` crashes | `VERIFIED` *(S22 Android 12)* | Cannot bypass hard game-engine Android caps (e.g., Genshin 60 FPS cap); toggle via `FPS_ENGINE_ENABLED` | [docs/fps-compatibility.md](docs/fps-compatibility.md) |
| **LTPO 120Hz Refresh Rate Guard** | Isolates primary display (`INTERNAL`) modes from external HDMI/DeX displays (50/70/75Hz), blocks false downgrades of `hw_profile.env`, sanitizes `120.1 -> 120.0`, and auto-recovers after crashes/Soft-Reboots | `VERIFIED` *(S22 LTPO)* | Controlled via `DISPLAY_AUTO_HZ`; inside Samsung DeX, external `Display #2` Hz cap still applies | [docs/fps-compatibility.md](docs/fps-compatibility.md) |
| **Device Profile Database & Whole-System Spoof** | Bundled **34 device profiles** (`devices.tsv`) & **31 game entries** (`games.tsv`); GPU-weighted scoring (`matcher.sh`), applied cleanly via `resetprop` + `system.prop` | `VERIFIED` *(S22)* | Profile matching is a GPU heuristic, **never guarantees** smooth FPS or 120 FPS unlocks; toggle via `SPOOF_ENABLED` | [docs/device-database.md](docs/device-database.md) |
| **Zygisk Stock-Identity Shield & Spoof Denylist** | `zygisk/arm64-v8a.so` (Zygisk API v4) restores true stock device properties for GMS/Play Store/GSF/Wallet (`PLAY_INTEGRITY_SHIELD`), Settings apps (`SPOOF_EXCLUDE_SETTINGS`), and user-selected packages in `spoof_denylist.list` | `VERIFIED` *(S22 + ReZygisk)* | Requires ReZygisk/Zygisk Next and clean reboot/Soft-Reboot after `.so` updates; does **not** guarantee passing Play Integrity | [docs/device-database.md](docs/device-database.md) |
| **CPU / GPU / Power Telemetry & Scene FPS Overlay** | Directly reads CPU/GPU frequencies & load, battery power (`mW`/`mA`), and SurfaceFlinger FPS + 1% Low via `kgx-core`; renders a floating mini overlay card & records CSV graphs (`SessionRecorder`) | `VERIFIED` *(S22)* | Overlay activates only after granting overlay permission and toggling Overlay ON | [docs/gaming-engine.md](docs/gaming-engine.md) |
| **Thermal Intelligence, Exynos Sweet-Spot & Bypass Charging** | 4-stage thermal guard (`THERMAL_GUARD_ENABLED`), Exynos 2200 Sustained Sweet-Spot (~82% peak), Soft Thermal Step-Down, hysteresis Bypass Charging (`>= BYPASS_MIN_PCT`), Samsung GOS Neutralizer | `VERIFIED` *(S22)* / `EXPERIMENTAL` *(other devices)* | **Never** disables silicon hardware thermal protection (`trip_point_*`); `THERMAL_UNLOCK` on unverified SoCs is experimental | [docs/thermal-management.md](docs/thermal-management.md) |
| **External Display, Res Override & DeX-Safe Freezer** | Turns off only the internal phone screen during HDMI/DP output (`EXT_DISPLAY_SCREEN_OFF` with safety guard); resolution scaling (`RES_OVERRIDE_ENABLED`); `cgroup.freeze` v2 app freezer skipping apps open in Pop-up/DeX windows | `VERIFIED` *(S22 HDMI/DP + cgroup v2)* | Refuses internal screen-off when no external display is connected; Freezer requires kernel `cgroup.freeze` support | [docs/configuration.md](docs/configuration.md) |
| **Touch & Network Diagnostics** | Tunes touch sampling sysfs node if present (`touch_game_node`) + measures touch rate (`touch measure`) and ping latency (`net test 1.1.1.1`) | `PARTIAL` *(implemented; kernel-node dependent)* | Toggle via `TOUCH_OPT_ENABLED` & `NET_OPT_ENABLED` | [docs/configuration.md](docs/configuration.md) |
| **Standalone Material 3 Android APK** | Pure-SDK Android app communicating with Rust JNI (`com.kgx.ultimate`) replacing legacy WebUI, with 3 Quick Settings Tiles | `VERIFIED` *(S22 Android 12)* | Requires Android 8.0+ and KernelSU Superuser permission | [docs/installation.md](docs/installation.md) |
| **Legacy Material 3 WebUI (`module/webroot`)** | In-manager KernelSU web interface | `UNSUPPORTED` *(Removed)* | Completely removed to prevent stale crashes → use Standalone Companion APK instead | — |

---

<a id="read-before-installing"></a>
## 2. Read Before Installing — Risk Warnings

> [!CAUTION]
> **Please read carefully before downloading or flashing:**
> 1. This project **deeply modifies Android at Root privilege** (system properties, `GameManager`, display refresh rates, CPU/GPU/charging `sysfs` nodes, `pm disable-user` for GOS, Zygisk PLT/JNI hooks).
> 2. Requires a working **KernelSU** environment. Root modifications always carry risks of app crashes, higher battery drain, overheating, or system instability.
> 3. Incompatible configurations on untested devices/kernels **can cause a bootloop**.
> 4. **You can lose all personal data** if a severe issue forces a Wipe Data / Factory Reset or stock firmware re-flash.
> 5. Not every kernel/device exposes optional hardware nodes (Bypass Charging, Exynos UFCC, touch game nodes, `cgroup.freeze`).
> 6. **120 FPS is NOT guaranteed in every game**: many games lock 60 FPS inside their engine or follow the physical refresh rate of the active display (e.g., 75Hz in Samsung DeX).
> 7. **Device Profile spoofing does NOT equal real hardware capability**: profiles only alter software/property identification.
> 8. **Passing Play Integrity is NOT guaranteed**: *Stock-Identity Shield* only hides spoofed values from GMS; attestation still depends on bootloader state, root setup, and your separate Play Integrity setup.
> 9. **No guarantee against anti-cheat / root detection** in games that detect KernelSU or Zygisk environments.
> 10. **Silicon Hardware Thermal Protection is NEVER disabled**: kernel hardware thermal shutdown thresholds (`trip_point_*`) always remain untouched.
> 11. **Experimental tweaks (`THERMAL_UNLOCK=1` on untested SoCs/devices)**: may raise temperatures rapidly and cause harsher thermal throttling — avoid enabling without active cooling and backups.
> 12. **Users assume full responsibility** when installing and running this software under the terms of the GNU GPL v3.0 or later (`GPL-3.0-or-later`) license.

### 6 Mandatory Steps Before Installing
1. **Back up important data** (photos, messages, documents, 2FA codes) off the phone.
2. Check the [Compatibility Matrix](#compatibility) below to see whether your device is `VERIFIED`, `PARTIAL`, or `UNKNOWN`.
3. Verify your **Android version** (minimum Android 8.0 / recommended Android 12+).
4. Verify your **KernelSU** setup is active and stable.
5. Download both the **Module ZIP** and **Companion APK** from Releases and **verify SHA-256** before flashing.
6. Read the [Recovery Guide](#recovery) before flashing so you know how to recover immediately if needed.

---

<a id="compatibility"></a>
## 3. Real-World Compatibility Matrix

**Honest classification rules:**
- `VERIFIED`: Tested directly on physical hardware.
- `PARTIAL`: Verified via computer POSIX/mock test suite (`tests/verify_all.py`) or partially verified.
- `EXPERIMENTAL`: Experimental high-power/thermal tuning or unverified cross-device tweaks.
- `UNSUPPORTED`: Architecturally unsupported.
- `UNKNOWN`: No physical hardware test data *(we never claim compatibility solely by SoC/brand name)*.

| Category | Observed Hardware / Environment | Status | Verification Notes |
|---|---|---|---|
| **Physical Device Tested** | **Samsung Galaxy S22 Exynos (`SM-S901B` / `r0s`)**, Exynos 2200 (`s5e9925`), Xclipse 920 (`sgpu`), LTPO 10–120Hz panel | `VERIFIED` | Tested directly on maintainer's physical device |
| **Android** | **Android 12 / One UI 4.1 (API 31)** *(VERIFIED)*; API 26–34 *(source-level)* | `VERIFIED` *(API 31)* / `UNKNOWN` *(others)* | `customize.sh` enforces minimum Android >= 8.0 (API 26) |
| **Architecture** | **ARM64 (`arm64-v8a`)** | `VERIFIED` | `armeabi-v7a`, `x86`, `x86_64`: `UNSUPPORTED` |
| **Root Solution** | **KernelSU temproot (`samsung-v2.2`, code `32687`) + ReZygisk** | `VERIFIED` | APatch / KernelSU Next / Zygisk Next: `UNKNOWN` (untested on hardware) |
| **Kernel** | Stock Samsung S22 Exynos kernel + KernelSU temproot | `VERIFIED` | Custom kernels / other OEMs: `UNKNOWN` |
| **Companion APK** | `KSU-Ultimate-Gaming-X-v1.0.0.apk` (minSdk 26 / targetSdk 34) | `VERIFIED` *(Android 12)* | Requires KernelSU Superuser permission |
| **WebUI (KernelSU)** | `module/webroot` removed | `UNSUPPORTED` | Replaced completely by Standalone APK |
| **Rust Binaries** | Target `aarch64-linux-android` (`kgx-core`, `libkgx_rust.so`) | `VERIFIED` | Pure `std`, zero external crates |
| **Qualcomm Adreno / MediaTek Mali** | Snapdragon / Dimensity entries in DB & Stage 4A/4B mock suite | `PARTIAL` *(Mock only)* | Not yet tested on physical hardware → use caution with clock/thermal tweaks |
| **Per-Game Compatibility** | Evaluated per package (`WHITELIST`, `GAME_CAP`, `OPEN`) via 31-game DB | `VERIFIED` *(Free Fire / Delta Force VN on Display #0)* | Many games enforce engine caps or DeX 75Hz limits (`GAME_CAP`/`DISPLAY_LIMIT`) |

---

<a id="requirements"></a>
## 4. Requirements

- **Device & CPU**: Android phone with **ARM64 (`arm64-v8a`)** CPU.
- **OS**: Android **8.0+ (API 26+)**; Android **12+ (API 31+)** recommended for full `cmd game downscale` & `GameManager` features.
- **Root**: Working **KernelSU** installation (on temproot setups, ensure temproot is injected before opening the app or flashing).
- **Zygisk (recommended)**: Install **ReZygisk** (or a compatible Zygisk API v4 provider) to enable **Play Integrity Shield**, **Exclude Settings**, and **Spoof Denylist**.
- **Storage**: At least ~20 MB free on `/data` for module files, stock snapshots, and backups.
- **APK Permissions**: Superuser (`su`) permission in KernelSU Manager; `SYSTEM_ALERT_WINDOW` (Draw Over Other Apps) + Notifications are only needed if you turn on **Scene FPS Overlay**.

---

<a id="installation-guide"></a>
## 5. Beginner Installation Guide (A → Z)

See full step-by-step instructions in **[docs/installation.md](docs/installation.md)**. Quick summary:

### 5.1. Download the Right Files
1. Open **[GitHub Releases v1.0.0](https://github.com/hangothanhh/ksu-ultimate-gaming-x/releases/tag/v1.0.0)**.
2. Download **both release assets**:
   - `KSU-Ultimate-Gaming-X-v1.0.0.zip` → **KernelSU Module** (flash inside KernelSU Manager).
   - `KSU-Ultimate-Gaming-X-v1.0.0.apk` → **Companion App** (install like a normal Android APK).
3. Do **NOT** download `Source code (zip)` to flash in KernelSU Manager — it only contains source files and will fail to install.

### 5.2. Verify SHA-256 Checksums Before Installing
Verify file integrity to rule out corrupted or tampered downloads:

- **Windows (PowerShell / CMD):**
  ```cmd
  certutil -hashfile KSU-Ultimate-Gaming-X-v1.0.0.zip SHA256
  certutil -hashfile KSU-Ultimate-Gaming-X-v1.0.0.apk SHA256
  ```
- **Linux / Android Termux:**
  ```sh
  sha256sum KSU-Ultimate-Gaming-X-v1.0.0.zip KSU-Ultimate-Gaming-X-v1.0.0.apk
  ```
- **macOS:**
  ```sh
  shasum -a 256 KSU-Ultimate-Gaming-X-v1.0.0.zip KSU-Ultimate-Gaming-X-v1.0.0.apk
  ```

Compare against the verified `v1.0.0` hashes (generated from binaries tested across all 7 verification stages):

| File | Size | Official SHA-256 |
|---|---|---|
| `KSU-Ultimate-Gaming-X-v1.0.0.zip` | `633,482` bytes | `700c1449e3db4fc901d346e9f427f51161ae279b23851649e3566b82b91c5bd7` |
| `KSU-Ultimate-Gaming-X-v1.0.0.apk` | `369,411` bytes | `fc5f04e4f2ddafa037f9a7c0951580500de38c11e571939a8b793499e962722a` |

*(If even 1 character differs, delete the file and download it again.)*

### 5.3. Flash Module & Install Companion APK
1. Open **KernelSU Manager** and confirm KernelSU status is active/working.
2. Go to the **Modules** tab → tap **Install** → select `KSU-Ultimate-Gaming-X-v1.0.0.zip`.
3. Wait for `- Installation complete!`. If you see an error line starting with `!`, check [docs/installation.md](docs/installation.md).
4. Reboot your phone (or perform a **Soft-Reboot** if using KernelSU temproot, following your device's temproot instructions).
5. Install `KSU-Ultimate-Gaming-X-v1.0.0.apk` and grant Superuser permission to `KSU Gaming X` (`com.kgx.ultimate`) in KernelSU Manager → **Superuser**.

### 5.4. First-Launch Verification
Open **KSU Gaming X** and verify:
- Daemon status shows **Running (`pid > 0`)**.
- Detected SoC/GPU and stock `Display Max Hz` are accurate (not falsely dropped to `60 Hz` on a `120 Hz` panel).
- Default `global.conf` flags: `SPOOF_ENABLED=1`, `PLAY_INTEGRITY_SHIELD=1`, `SPOOF_EXCLUDE_SETTINGS=1`, `THERMAL_GUARD_ENABLED=1`, `THERMAL_UNLOCK=0`.
- Optional CLI verification (`adb shell su -c ...` or rooted Termux):
  ```sh
  /data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl status
  /data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl spoof diag
  ```

---

<a id="update-rollback-uninstall--recovery"></a>
## 6. Update, Rollback, Uninstall & Recovery

Full details are documented in **[docs/backup-restore.md](docs/backup-restore.md)**. Summary:
- **Update**: Always back up (`kgxctl backup create pre_update`), verify SHA-256 of the new release, then flash via KernelSU Manager. `module/customize.sh` preserves `global.conf`, `custom_games.tsv`, `spoof_denylist.list`, and `custom_profiles.tsv`, migrating missing config keys automatically. Perform a clean reboot / Soft-Reboot after `.so` updates (never overwrite `.so` while `zygote64` is live).
- **Instant Rollback**: Toggle **Safe Mode** inside the app, tap the module's **Action** button in KernelSU Manager (`action.sh`), or run `kgxctl safemode on && kgxctl rollback`.
- **Uninstall**: Remove the module inside **KernelSU Manager → Modules** and reboot. `module/uninstall.sh` restores GOS, network, touch, unfreezes `cgroup.freeze`, disables Bypass Charging, resets `wm size`/`density`, restores refresh rate, clears `system.prop`, and removes `/data/adb/ksu_gaming_x` (preserving `backups/` if `KEEP_BACKUPS_ON_UNINSTALL=1`). Never delete `/system` files manually.

<a id="recovery"></a>
### Emergency Recovery
- **APK crashes only**: Clear APK cache/data and reinstall the APK matching SHA-256.
- **Module stuck / misbehaving**: Enable `SAFE_MODE=1` or tap **Action** in KernelSU Manager.
- **Bootloop**: Built-in `boot_counter` inside `module/post-fs-data.sh` detects **2 consecutive failed boots**, automatically sets `SAFE_MODE=1`, removes `system.prop`, and restores stock properties.
- **Still unable to boot Android**: Boot into **KernelSU Safe Mode** (hold Volume Down during boot on supported KernelSU builds) to disable all modules, or on **temproot** setups simply force a cold reboot to return to stock unrooted Android. *(Warning: use Factory Reset / Wipe Data only as a last resort — it **ERASES ALL PERSONAL DATA**.)*

---

<a id="troubleshooting--diagnostic-report"></a>
## 7. Usage, FAQ, Troubleshooting & Safe Diagnostics (`kgxctl diag`)

- **Usage & Configuration**: Control modes via 3 **Quick Settings Tiles**, set per-game profiles in the Companion APK, or edit settings via CLI (`/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl --help`) and [docs/configuration.md](docs/configuration.md).
- **FAQ & Common Issues**: Read **14 beginner troubleshooting guides** (missing module, WebUI removed notice, FPS caps, 60Hz drops, overheating, conflicts, and Play Integrity) at **[docs/troubleshooting.md](docs/troubleshooting.md)**.

### Export a Redacted Diagnostic Report (`kgxctl diag`)
```sh
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl diag /sdcard/Download/kgx_diag.txt"
```
This exports module version, Android/API, kernel, KernelSU, SoC/GPU, daemon state, config flags, and the last 40 log lines — **automatically masking** serial numbers, IMEIs, MAC addresses, emails, private IPv4s, and tokens/passwords with `[REDACTED_*]` before you attach it to **[GitHub Issues](https://github.com/hangothanhh/ksu-ultimate-gaming-x/issues)**.

---

<a id="repository-structure--build-from-source"></a>
## 8. Repository Structure & Build from Source

### Actual Repository Layout
```text
ksu-ultimate-gaming-x/
├── README.md                          # English primary documentation
├── README.vi.md                       # Vietnamese documentation mirror
├── CHANGELOG.md                       # Release changelog (EN; VI under docs/vi/)
├── CONTRIBUTING.md                    # Contributing rules & anti-AI-slop policy
├── LICENSE                            # GNU GPL v3.0 or later (GPL-3.0-or-later)
├── NOTICE                             # Third-party notices & AI transparency
├── AI_CONTRIBUTIONS.md                # Google Antigravity contribution disclosure
├── SECURITY.md                        # Security policy & root safety boundaries
├── .gitignore                         # Ignores keystores, dist/, system.prop, caches
├── .editorconfig                      # UTF-8 & LF normalization
├── .github/
│   ├── workflows/ci.yml               # GitHub Actions CI (ZIP build + Stages 1-6)
│   ├── ISSUE_TEMPLATE/                # Bug Report, Feature Request, Compatibility Report
│   └── PULL_REQUEST_TEMPLATE.md       # PR checklist with AI & rollback verification
├── docs/                              # Detailed English guides (mirrors under docs/vi/)
│   ├── installation.md
│   ├── configuration.md
│   ├── gaming-engine.md
│   ├── fps-compatibility.md
│   ├── device-database.md
│   ├── thermal-management.md
│   ├── backup-restore.md
│   ├── troubleshooting.md
│   ├── development.md
│   └── vi/                            # Vietnamese mirrors of docs & root guides
├── module/                            # KernelSU module core (POSIX sh + ARM64 ELF/DEX)
│   ├── module.prop                    # Module metadata (v1.0.0 / versionCode=100)
│   ├── post-fs-data.sh                # Bootloop guard & early-boot safe spoof
│   ├── service.sh                     # Crash/reboot recovery & daemon startup
│   ├── action.sh                      # KernelSU Manager quick Action rollback
│   ├── customize.sh                   # Installer & upgrade config migration
│   ├── uninstall.sh                   # Complete system state restoration
│   ├── bin/
│   │   ├── kgxctl                     # JSON control CLI & redacted kgxctl diag
│   │   ├── kgx-core                   # Native AArch64 Rust daemon & telemetry engine
│   │   └── gaming_daemon.sh           # Daemon wrapper & POSIX fallback
│   ├── lib/                           # 16 POSIX shell library modules
│   ├── data/                          # devices.tsv/json, games.tsv/json, default_global.conf, kgx-display.dex
│   └── zygisk/arm64-v8a.so            # Zygisk Stock-Identity & Denylist Shield
├── companion/
│   ├── rust-core/src/main.rs          # Native Rust daemon source
│   ├── zygisk-spoof/                  # C++17 Zygisk API v4 source & zygisk.hpp header
│   ├── display-helper/                # DisplayPowerCtrl.java -> kgx-display.dex
│   └── android-app/                   # Standalone Android APK (Java + Material 3 + Rust JNI)
├── scripts/
│   ├── build_rust.py                  # Compiles kgx-core, zygisk arm64-v8a.so, libkgx_rust.so
│   ├── build_apk.py                   # Compiles DEX & signs Companion APK (Zero Gradle)
│   └── build_zip.py                   # Deterministic ZIP packager (UNIX LF & permissions)
└── tests/
    └── verify_all.py                  # Automated 7-stage verification suite (--skip-apk for CI)
```

### Quick Build & Test Commands
Full toolchain instructions (Rust `aarch64-linux-android`, Android NDK `29.0.14206865`, Android SDK `android-34`, Build-Tools `34.0.0`, OpenJDK 17) are in **[docs/development.md](docs/development.md)**:
```powershell
python -u scripts/build_rust.py
python -u scripts/build_apk.py
python -u scripts/build_zip.py
python -u tests/verify_all.py
```

---

<a id="contributing-license--credits"></a>
## 9. Credits, Contributing, License & Third-Party Notices

- **Credits / Contributions**:
  - Lead Maintainer: `hangothanhh` (project ownership, real hardware testing, verification & releases).
  - Development Assistance: **Google Antigravity** (architecture, source implementation, automated test suite & documentation — see **[AI_CONTRIBUTIONS.md](AI_CONTRIBUTIONS.md)**).
- **Contributing Guidelines**: Read **[CONTRIBUTING.md](CONTRIBUTING.md)** (includes mandatory AI transparency and Anti-AI-Slop rules).
- **Security Policy**: Read **[SECURITY.md](SECURITY.md)**.
- **License**: Distributed under **[GNU General Public License v3.0 or later (`GPL-3.0-or-later`)](LICENSE)** — Copyright (C) 2026 `hangothanhh`.
- **Third-Party Attribution**: See **[NOTICE](NOTICE)** (includes public Zygisk API v4 header `companion/zygisk-spoof/include/zygisk.hpp` — Copyright 2022–2023 John "topjohnwu" Wu). All product/SoC/device/game names appear solely for technical compatibility identification and imply no official affiliation or endorsement.
