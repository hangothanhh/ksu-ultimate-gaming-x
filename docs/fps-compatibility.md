# FPS Compatibility Engine & LTPO 120Hz Refresh-Rate Guard

> **Language**: **English** | [Tiếng Việt](vi/fps-compatibility.md)

## 1. Purpose
Explains why device spoofing alone cannot unlock 90/120 FPS in every title, how the 5-factor compatibility analyzer (`fps.sh`) works, how `PlatformCompat killUid` crashes are avoided when configuring `GameManager`, and how `display.sh` + `hw_detect.sh` prevent 60Hz drops and post-reboot 60Hz locks.

---

## 2. 5-Factor FPS Compatibility Engine (`fps_analyze_json`)
This module **makes zero unrealistic promises** that every game will run at 120 FPS. When evaluating a game, `kgxctl games get <pkg>` calculates the true ceiling from **5 factors**:

$$\text{Effective FPS} = \min(\text{Requested FPS},\ \text{Game Engine Cap},\ \text{Display Max Hz},\ \text{Thermal Cap})$$

| Limiter (`primary_limiter`) | Real-World Meaning |
|---|---|
| `THERMAL_LIMIT` | Device temperature is `HOT` (caps target at 90 FPS) or `CRITICAL` (caps at 60 FPS) |
| `DISPLAY_LIMIT` | Physical display max Hz is lower than requested FPS (e.g., 60Hz panel cannot render 120 FPS) |
| `GAME_LIMIT` | Game engine enforces a hard Android cap (e.g., *Genshin Impact* caps Android at `GAME_CAP 60 FPS`; spoofing cannot bypass it without modifying game binaries, which this module **never** does) |
| `WHITELIST_LIMIT` | Game gates 90/120 FPS behind an official device whitelist (`WHITELIST`), and Spoof is off or unmatched |
| `HARDWARE_LIMIT` | Game allows high FPS, but the SoC/GPU `HW_TIER` may not sustain that target under heavy load |

---

## 3. Crash Protection (`PlatformCompat killUid` on Android 12+)
On Android 12+, invoking `cmd game mode/downscale` or `device_config put game_overlay` **while the game process is running** triggers `PlatformCompat.putOverridesOnReleaseBuilds()`, calling `killUid()` and crashing the game instantly.
How [module/lib/fps.sh](../module/lib/fps.sh) avoids this:
- `GameManager` / `downscale` overrides are **pre-applied only while the game is not running** (when saving config in the app or during `service.sh` startup).
- Whenever `fps_is_pkg_running` detects a running game, `fps_apply` and `session_deactivate` **never** call `cmd game` or `device_config`.

---

## 4. LTPO 120Hz Guard & Reboot Recovery (`hw_detect.sh` + `display.sh`)
Verified on Samsung 10–120Hz LTPO panels (Galaxy S22 Exynos, One UI 4.1), four common failure modes are handled:
1. **Primary Display Isolation from HDMI / Desktop DeX**: Parses `supportedModes` strictly from `DisplayDeviceInfo{` lines marked `type INTERNAL` / `FLAG_DEFAULT_DISPLAY`, ignoring external 50/70/75Hz modes.
2. **Preventing `mksh` `Argument list too long`**: Writes `dumpsys display` and `dumpsys SurfaceFlinger` output to temporary files processed with `awk`, plus kernel fallbacks (`/sys/class/drm/*DSI*/modes`, `/sys/class/lcd/panel/vrr`).
3. **Downgrade Guard for `hw_profile.env`**: Never overwrites a previously detected `DISPLAY_MAX_HZ > 60` with `60`; if stuck at `60`, `hw_load()` and `kgx-core` auto-rescan once after `sys.boot_completed=1`.
4. **SamHelper `120.1` Trap & Seamless 120Hz Enforcement**:
   - Tools like SamHelper often write `120.1`, slightly exceeding Samsung's real `120.00001 Hz` panel mode and causing `DisplayModeDirector` to drop to 60Hz. `display_sanitize_hz_val()` normalizes `120.1 -> 120.0`.
   - When `chosen >= 90`, `secure refresh_rate_mode 1` (and `system refresh_rate_mode 1` if present) is always enabled.
   - If a crash or soft-reboot leaves `active_display.env` behind, `service.sh` executes `display_recover_on_boot` before clearing state, and `kgx-core` calls `call_kgxctl_cleanup()` on `SIGTERM`/`SIGINT`/`SIGHUP`.

---

## 5. Samsung DeX External Display Limit
When running a game inside a **Samsung DeX (`Display #2`)** window, Android reports the refresh rate of `Display #2`, **not** the internal phone panel (`Display #0`).
- If your HDMI monitor only supports 60Hz or 75Hz (`Display #2` reports `75.0 Hz`), games such as *Delta Force Mobile* will grey out 90/120 FPS even with an active `V2425A` spoof.
- **Workaround**: Launch high-FPS games directly on the internal phone screen (`Display #0` — 120Hz).

---

## 6. CLI Diagnostic Commands
```sh
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl hw"
su -c "settings get system min_refresh_rate; settings get system peak_refresh_rate; settings get secure refresh_rate_mode"
su -c "dumpsys display | grep -E 'mDisplayModeSpecs=|baseModeId=' | head -n 5"
```
Healthy Galaxy S22 output: `min=120.0`, `peak=120.0`, `sec_rrm=1`, `baseModeId=1`, `DISPLAY_SUPPORTED_HZ='30 48 60 96 120'`.
