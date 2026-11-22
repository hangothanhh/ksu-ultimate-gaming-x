# Detailed Installation Guide (Beginner A → Z)

> **Language**: **English** | [Tiếng Việt](vi/installation.md)

## 1. Purpose
This guide walks you through downloading the right files, verifying SHA-256 checksums, flashing the module, and confirming that **KSU Ultimate Gaming X (`v1.0.0`)** is running safely on a KernelSU-rooted Android device — even if you are new to Android rooting.

---

## 2. Quick Concept Primer
- **KernelSU (KSU)**: A Linux kernel-level root solution for Android that loads modules without permanently rewriting the `/system` partition.
- **Module ZIP (`KSU-Ultimate-Gaming-X-v1.0.0.zip`)**: The core package flashed inside **KernelSU Manager**, containing hardware shell scripts, the Rust daemon `kgx-core`, and the Zygisk library.
- **Companion APK (`KSU-Ultimate-Gaming-X-v1.0.0.apk`)**: The Material 3 Android app used to toggle features, view live FPS/temperature telemetry, and configure apps excluded from spoofing (**Spoof Denylist**). **Note**: The APK **cannot** replace the Module ZIP — always flash the Module ZIP first.
- **Zygisk / ReZygisk**: Injects native hooks during app startup (`zygote64`). Used by **Stock-Identity Shield** to keep genuine device identity visible to Google Play Services, Settings, and user-chosen Denylist apps.

---

## 3. Prerequisites
1. An **ARM64 (`arm64-v8a`)** Android device running **Android 8.0+ (API >= 26)** (`Android 12+ / API >= 31` recommended for `cmd game` / downscale support).
2. A working **KernelSU** (or compatible **KernelSU Next / APatch**) installation.
3. Optional but recommended for *Stock-Identity Shield / Spoof Denylist*: **ReZygisk** or **Zygisk Next** installed.
4. **Back up important data** (photos, documents, banking/2FA apps) off your phone before flashing any root module.
5. Read the [Risk Warnings](../README.md#read-before-installing) and [Recovery Guide](../README.md#recovery).

---

## 4. Download & Verify SHA-256

### Step 1: Download the Correct Assets from GitHub Releases
1. Open https://github.com/hangothanhh/ksu-ultimate-gaming-x/releases/tag/v1.0.0
2. Download **both release assets**:
   - `KSU-Ultimate-Gaming-X-v1.0.0.zip` *(KernelSU Module)*
   - `KSU-Ultimate-Gaming-X-v1.0.0.apk` *(Companion App)*
3. Do **NOT** download `Source code (zip)` from the repository homepage or Assets section and try to flash it in KernelSU — that is raw source code, **not** a flashable module.

### Step 2: Verify SHA-256 Checksums
Check that your downloaded files were neither corrupted in transit nor altered. Reference hashes are published alongside each release in `.sha256` files:

- **Windows (PowerShell / CMD):**
  ```cmd
  certutil -hashfile KSU-Ultimate-Gaming-X-v1.0.0.zip SHA256
  certutil -hashfile KSU-Ultimate-Gaming-X-v1.0.0.apk SHA256
  ```
- **Linux / Termux (Android):**
  ```sh
  sha256sum KSU-Ultimate-Gaming-X-v1.0.0.zip
  sha256sum KSU-Ultimate-Gaming-X-v1.0.0.apk
  ```
- **macOS:**
  ```sh
  shasum -a 256 KSU-Ultimate-Gaming-X-v1.0.0.zip
  shasum -a 256 KSU-Ultimate-Gaming-X-v1.0.0.apk
  ```

**Verification rule**: The 64-character hex string must match the corresponding `.sha256` file on GitHub Releases character for character (case-insensitive). If even one character differs, delete the file and re-download it.

---

## 5. Flash the Module ZIP in KernelSU
1. Copy `KSU-Ultimate-Gaming-X-v1.0.0.zip` to internal storage (e.g., `Download/`).
2. Open **KernelSU Manager**.
3. Confirm the home card shows KernelSU **Working** (on temproot setups like Samsung S22, ensure temproot is currently active).
4. Open the **Modules** tab → tap **Install** *(button placement varies by KernelSU Manager version)* → select `KSU-Ultimate-Gaming-X-v1.0.0.zip`.
5. Watch the installer log (`customize.sh`):
   - Success ends with: `- Installation complete! Open KSU Gaming X App to configure.`
   - Common abort messages: `! Unsupported architecture` (non-ARM64 device) or `! Android API ... is too old` (below Android 8.0).
6. Reboot your device (or perform a **Soft-Reboot** if using **KernelSU temproot** so you do not lose temproot — follow your device's temproot workflow).

---

## 6. Install the Companion APK & First Launch
> Security note: **Never** blindly grant root to unfamiliar apps. Only **KSU Gaming X** needs `su` permission from KernelSU to communicate with `kgxctl` and `kgx-core`.

1. Install `KSU-Ultimate-Gaming-X-v1.0.0.apk` like any standard APK (enable *Allow from this source* if prompted).
2. Open **KernelSU Manager → Superuser**, locate **KSU Gaming X** (`com.kgx.ultimate`), and toggle root access ON (or tap **Allow** on the prompt).
3. Launch **KSU Gaming X** and check on first run:
   - **Status & Daemon**: `kgx-core` reports **running**.
   - **Hardware Info**: Detected SoC, GPU, and stock `DISPLAY_MAX_HZ` are accurate (e.g., `120 Hz` on Galaxy S22, not falsely dropped to `60 Hz`).
   - **Device Spoof**: Defaults from `module/data/default_global.conf` are `SPOOF_ENABLED=1`, `PLAY_INTEGRITY_SHIELD=1`, and `SPOOF_EXCLUDE_SETTINGS=1`. Toggle off in the app if you do not want spoofing.
   - **Thermal & Game**: Defaults are `THERMAL_GUARD_ENABLED=1`, `THERMAL_UNLOCK=0`, `SUSTAINED_SWEET_SPOT=0`.

---

## 7. Command-Line Verification (Beyond UI Toggles)
Verify independently via `adb shell su -c ...` or rooted Termux:
```sh
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl status"
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl diag"
```
Confirm:
- `"daemon":{"running":true,...}` → daemon active.
- `"display":{"current_hz":120,"max_hz":120,...}` → true display refresh rate preserved.
- `"safe_mode":false` → not stuck in Safe Mode.

---

## 8. Common Installation Warnings & Fixes
- **Module missing after reboot**: If using **temproot**, check whether you ran a regular *Cold Reboot* instead of Soft-Reboot, which drops temproot.
- **App reports "Module not installed"**: You either installed the APK before flashing the Module ZIP or forgot to grant Superuser permission to `com.kgx.ultimate` in KernelSU Manager.
- **Need immediate rollback**: Tap the module's **Action** button in KernelSU Manager (`module/action.sh` executes `kgxctl rollback`), or check the [Troubleshooting Guide](troubleshooting.md).
