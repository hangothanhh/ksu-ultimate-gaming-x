# Troubleshooting, FAQ & Redacted Diagnostic Report (`kgxctl diag`)

> **Language**: **English** | [Tiếng Việt](vi/troubleshooting.md)

## 1. Purpose
Covers common beginner issues following a structured flow: *Symptoms → Possible Cause → How to Check → Fix → When to Report Logs*.

---

## 2. Exporting a Safe Redacted Diagnostic Report Before Asking for Help
> [!IMPORTANT]
> Always use `kgxctl diag` before posting logs to GitHub Issues. It **automatically redacts** serials, IMEIs, MAC addresses, emails, private IPv4s, and tokens/passwords into `[REDACTED_*]`. Never share raw unredacted logs or screenshots exposing personal device IDs!

```sh
# Print redacted report directly to terminal
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl diag"

# Or export directly to Download/ for attaching to an Issue
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl diag /sdcard/Download/kgx_diag.txt"
```

Reports include module version (`v1.0.0`), Android/API, kernel, KernelSU, SoC/GPU, daemon state, config flags, and the last 40 redacted log lines. Open an issue at: https://github.com/hangothanhh/ksu-ultimate-gaming-x/issues/new/choose

---

## 3. Common Issues & Fixes (14 Cases)

### 1. Module Does Not Appear in KernelSU Manager
1. **Symptoms**: After flashing, `KSU Ultimate Gaming X` is missing in the Modules tab.
2. **Possible Causes**: Did not reboot after flashing; on a temproot device you performed a normal *Cold Reboot* which wiped KernelSU; or you accidentally downloaded GitHub's *Source code ZIP* instead of `KSU-Ultimate-Gaming-X-v1.0.0.zip`.
3. **Check**: Confirm KernelSU Manager status is *Working*, and verify the flashed ZIP contains `module.prop` at its root.
4. **Fix**: Download `KSU-Ultimate-Gaming-X-v1.0.0.zip` from Releases, verify SHA-256, and re-flash.

### 2. ZIP Flash Fails (`! Unsupported ...`)
1. **Symptoms**: Flashing stops with red `!` abort text.
2. **Possible Causes**: Device is not `arm64-v8a` (e.g., 32-bit `armeabi-v7a` or x86 emulator), Android is below 8.0 (`API < 26`), or download was corrupted.
3. **Check**: Read the exact `!` line in the flash log and run `certutil` / `sha256sum`.
4. **Fix**: 32-bit and Android < 8.0 are `UNSUPPORTED`; otherwise re-download until SHA-256 matches.

### 3. No WebUI Button Inside KernelSU
1. **Symptoms**: Cannot open WebUI from KernelSU Manager.
2. **Cause**: Legacy **WebUI (`module/webroot`) has been completely removed** and replaced by the **Standalone Companion APK** (`KSU-Ultimate-Gaming-X-v1.0.0.apk`).
3. **Fix**: Download and install `KSU-Ultimate-Gaming-X-v1.0.0.apk` from GitHub Releases.

### 4. Companion APK Reports "Root Required" or Cannot Connect
1. **Symptoms**: APK shows daemon/module unavailable or root permission denied.
2. **Possible Causes**: `com.kgx.ultimate` was not granted Superuser (`su`) permission in KernelSU Manager, or Module ZIP was never flashed.
3. **Check**: Check `KernelSU Manager → Superuser` for `KSU Gaming X` and check `/data/adb/modules/ksu_ultimate_gaming_x`.
4. **Fix**: Enable Superuser for `KSU Gaming X` and tap retry inside the app.

### 5. Dashboard Metrics Missing or FPS Always Shows `N/A`
1. **Symptoms**: FPS stays `N/A` or live stats do not update while gaming.
2. **Cause**: Daemon not running, viewing Home screen (no active SurfaceFlinger game render layer), or primary screen is turned off while external monitor handles rendering.
3. **Check**: Run `kgxctl daemon status` and `kgxctl overlay-tick`.
4. **Fix**: Enable `AUTO_OPTIMIZE=1`, run `kgxctl daemon start`, or play on the primary display (`Display #0`).

### 6. CPU / GPU Shows `0 MHz` or `unknown`
1. **Symptoms**: Dashboard reports unknown GPU or zero clocks.
2. **Cause**: Your custom kernel exposes `/sys/class/devfreq` or `/sys/kernel/gpu` at paths differing from built-in Adreno/Mali/Exynos S22 patterns in `hw_detect.sh`.
3. **Check**: Run `kgxctl hw` and `kgxctl diag`.
4. **Fix**: Submit a Compatibility Report with `kgxctl diag` output and `ls /sys/class/devfreq/`.

### 7. FPS Does Not Increase or Stays Capped at 60 FPS
1. **Symptoms**: Game profile is set to `120 FPS`, yet the game only allows or runs at 60 FPS.
2. **Possible Causes**:
   - Hard game-engine Android cap (`GAME_CAP`, e.g., *Genshin Impact* locks 60 FPS on Android).
   - Active display or Samsung DeX external display is capped at 60/75Hz (`DISPLAY_LIMIT`).
   - Device hit `CRITICAL` thermal throttling (60 FPS cap).
   - Game was not restarted after changing Spoof or Downscale settings.
3. **Check**: Run `kgxctl games get <package>` and read `primary_limiter` + `explanation`.
4. **Fix**: Force-stop and relaunch the game; if in Samsung DeX on a 60/75Hz monitor, switch to the internal 120Hz phone display (`Display #0`).

### 8. Screen Drops to 60Hz or Gets Stuck at 60Hz After Soft/Hard Reboot
1. **Symptoms**: After exiting a game or rebooting, screen refresh rate stays stuck at 60Hz.
2. **Possible Causes**: Abrupt reboot mid-session before restore ran, third-party tools (like SamHelper) writing `120.1` (rejected by One UI `DisplayModeDirector`), or running an outdated pre-fix build.
3. **Check**: Run `kgxctl hw` and inspect `settings get system min_refresh_rate` / `peak_refresh_rate`.
4. **Fix**: Ensure `v1.0.0` is installed and run `kgxctl display recover` (or `kgxctl display restore`).

### 9. Rapid Overheating During Long Gaming Sessions
1. **Symptoms**: Phone heats quickly and throttles FPS after 10–15 minutes.
2. **Cause**: `THERMAL_UNLOCK=1` and `MAX_CLOCK_LOCK=1` both enabled in warm ambient conditions.
3. **Fix**: Turn off `MAX_CLOCK_LOCK`, switch to **`SUSTAINED_SWEET_SPOT=1`** and **`BYPASS_CHARGING=1`** (while plugged in >= 80% if supported), plus external cooling.

### 10. Micro-Stutter or Unexpected Game Crashes
1. **Symptoms**: Game closes unexpectedly or stutters heavily.
2. **Possible Causes**: Low physical RAM, conflicts with other kernel tweakers (Konabess / LSpeed / FDE), or changing `downscale` while the game process is running.
3. **Check**: Inspect `kgxctl logs 40` and `logcat -b crash` for `SIGSEGV`/`SIGILL`.
4. **Fix**: Always Force Stop the game before altering `downscale`; disable competing performance modules to isolate conflicts.

### 11. `kgx-core` Daemon Fails to Auto-Start
1. **Symptoms**: Companion APK shows daemon stopped (`running=false`) after boot.
2. **Cause**: `SAFE_MODE=1` was triggered (after 2 consecutive failed boots) or `AUTO_OPTIMIZE=0`.
3. **Check**: Run `kgxctl status` and `kgxctl diag`.
4. **Fix**: Once stable, tap **Action** in KernelSU Manager or run `kgxctl safemode off && kgxctl daemon start`.

### 12. Conflicts With Other Spoof Modules
1. **Symptoms**: Spoofed device model is overwritten or fails to apply.
2. **Cause**: Conflicting system-wide prop modules (e.g., MagiskHide Props Config or other spoof modules).
3. **Check**: Run `kgxctl profiles conflicts`.
4. **Fix**: Disable duplicate spoof modules modifying `ro.product.*`.

### 13. Play Integrity Failures / Banking Apps / Settings Detecting Spoof
1. **Symptoms**: Google Wallet, Play Protect, Settings, or banking apps see the spoofed model or fail device checks.
2. **Possible Causes**:
   - Upgraded `zygisk/arm64-v8a.so` without rebooting / Soft-Rebooting `zygote64`, or missing ReZygisk/Zygisk Next.
   - Banking/custom apps are outside default Google targets and need manual inclusion in **Spoof Denylist**.
   - **Play Integrity failures are often unrelated to this module** (unlocked bootloader, custom ROM, or expired PIF/TrickyStore keyboxes).
3. **Check**: Run `kgxctl spoof diag` and `logcat -d -s KGX_PIShield | tail -n 20`.
4. **Fix**: Enable `PLAY_INTEGRITY_SHIELD=1` + `SPOOF_EXCLUDE_SETTINGS=1`, add sensitive apps to **Spoof Denylist** inside the APK, and Force Stop them. *Note: this module does not spoof hardware attestation keys or bypass anti-cheat.*

### 14. Mass App Crashes (`SIGILL`) After Manual Hot-Overwrite
1. **Symptoms**: System apps and GMS crash repeatedly after manual file copy.
2. **Cause**: Running `unzip -o` directly over `zygisk/arm64-v8a.so` while `zygote64` has the previous `.so` `mmap`-ed in RAM.
3. **Fix**: Always flash Module ZIP properly via KernelSU Manager and reboot / Soft-Reboot cleanly.
