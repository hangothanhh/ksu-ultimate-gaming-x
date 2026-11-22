# Configuration & Options (`global.conf`)

> **Language**: **English** | [Tiếng Việt](vi/configuration.md)

## 1. Purpose
Explains every configuration key in `/data/adb/ksu_gaming_x/config/global.conf` (initialized from [default_global.conf](../module/data/default_global.conf)) and companion list files so beginners understand each toggle before modifying it.

---

## 2. Persistent On-Device Paths
While active on Android, persistent module data (preserved across ZIP upgrades) lives under `/data/adb/ksu_gaming_x/`:
- `config/global.conf` — Global configuration (modified safely by the Companion App via `kgxctl engine set <KEY> <VALUE>`).
- `config/custom_games.tsv` — User-customized per-game profiles (10 tab-separated columns).
- `config/spoof_denylist.list` — Package names **excluded from spoofing** (restored to stock by Zygisk Shield).
- `config/freezer_apps.list` — Background packages eligible for `cgroup.freeze` v2 while gaming (`FREEZER_ENABLED=1`).
- `profiles/custom_profiles.tsv` — Custom user-created device spoof profiles.

---

## 3. `global.conf` Key Reference

| Key | Default | Meaning | Notes / Warnings |
|---|---|---|---|
| `AUTO_OPTIMIZE` | `1` | Auto-detect foreground games via `kgx-core` | Set `0` to disable automatic per-game tuning |
| `SAFE_MODE` | `0` | Emergency Safe Mode | Setting `1` restores stock settings immediately and stops daemon |
| `SPOOF_ENABLED` | `1` | Master device spoof switch | Applies system-wide except packages protected by Zygisk Shield |
| `PLAY_INTEGRITY_SHIELD` | `1` | Zygisk restores stock props for GMS/Play Store/GSF/Wallet | Requires active ReZygisk/Zygisk Next |
| `SPOOF_EXCLUDE_SETTINGS` | `1` | Keeps real device identity inside Android/Samsung/OEM Settings | Keeps About Phone accurate |
| `GLOBAL_SPOOF_PROFILE` | `realme_14_5g` | Default spoof profile ID from `devices.tsv` or `custom_profiles.tsv` | Requires Zygisk or `resetprop` |
| `DEFAULT_MODE` | `high_performance` | Default performance mode (`balanced`, `high_performance`, `extreme_gaming`, `battery_gaming`) | Avoid `extreme_gaming` when device is already hot |
| `FPS_ENGINE_ENABLED` | `1` | Enables GameManager pre-configuration (`cmd game` / `device_config game_overlay`) | Only writes while the game process is **not running** to prevent `killUid` |
| `DISPLAY_AUTO_HZ` | `1` | Auto-manages `min/peak_refresh_rate` per game | Includes anti-60Hz guard & `120.1 -> 120.0` sanitizer |
| `TOUCH_OPT_ENABLED` | `1` | Tunes touch game sysfs node during active sessions (if supported) | Reverted via `sysfs_restore_all` on exit |
| `RAM_OPT_ENABLED` | `1` | Adjusts `swappiness` / `vfs_cache_pressure` & selective background trim | Strictly never runs `am kill-all` |
| `THERMAL_GUARD_ENABLED` | `1` | Automatic 4-stage thermal protection (NORMAL → WARM → HOT → CRITICAL) | Recommended ON to prevent overheating shutdowns |
| `THERMAL_UNLOCK` | `0` | Relaxes software limits (`EXYNOS_UFCC` / GPU devfreq) *(EXPERIMENTAL on untested SoCs)* | Requires adequate cooling; **never** modifies `trip_point_*` |
| `SUSTAINED_SWEET_SPOT` | `0` | Caps peak clocks (~82% peak on Exynos) for sustained thermals instead of early throttling | Recommended for long Exynos 2200 sessions |
| `MAX_CLOCK_LOCK` | `0` | Holds higher min/max clocks per `cpu_gpu.sh` tables | Increases battery drain and heat |
| `SOFT_THERMAL_STEP` | `0` | Two-tier soft clock step-down before severe lag hits | Applies only during active game sessions |
| `GOS_NEUTRALIZE` | `0` | Temporarily disables `com.samsung.android.game.gos` (`pm disable-user`) | Auto-re-enabled when toggled off or in `SAFE_MODE=1` |
| `EXT_DISPLAY_SCREEN_OFF` | `0` | Turns off internal phone panel only while external HDMI/DP display is active | Safety guard **refuses** screen-off if no external display is detected |
| `RES_OVERRIDE_ENABLED` | `0` | Overrides screen resolution (`wm size` / `wm density`) | Auto-resets when conditions end |
| `RES_OVERRIDE_SCOPE` | `ext_scrcpy` | Resolution override scope: `ext_scrcpy` or `always` | `always` applies resolution continuously even unplugged |
| `RES_OVERRIDE_PRESET` | `1080x1920` | Target resolution for `RES_OVERRIDE_ENABLED` | Valid range `480..3840` |
| `RES_OVERRIDE_DENSITY` | `auto` | Target DPI (`auto` or integer `240–640`) | Scales proportionally from stock width |
| `FREEZER_ENABLED` | `0` | Freezes listed apps via `cgroup.freeze` v2 | Skips apps visible in Pop-up View or Samsung DeX |
| `THERMAL_ALERT_ENABLED` | `1` | Enables temperature warnings in overlay / status | — |
| `THERMAL_ALERT_BATT_C` | `44` | Battery temperature alert threshold (°C) | — |
| `THERMAL_ALERT_CPU_C` | `92` | CPU temperature alert threshold (°C) | — |
| `THERMAL_ALERT_ACTION` | `notify` | Threshold action (`notify`, `step_down`, `bypass`, `both`) | — |
| `BYPASS_CHARGING` | `0` | Routes charger power directly to board (`batt_slate_mode`/`input_suspend`/`charging_enabled`) | Requires supported kernel node |
| `BYPASS_MIN_PCT` | `80` | Minimum battery percentage for Bypass Charging (`-3%` hysteresis) | Prevents deep battery drain while plugged in |
| `POLL_INTERVAL_ACTIVE` | `2` | Active session poll interval (seconds) | `1–30s` |
| `POLL_INTERVAL_IDLE` | `1` | Idle poll interval (seconds) | `1–30s` |
| `EXIT_DEBOUNCE_SEC` | `2` | Grace delay (seconds) after leaving foreground before restoring | Avoids flicker during quick app switches |
| `KEEP_BACKUPS_ON_UNINSTALL` | `0` | If `1`, preserves `backups/` when uninstalling module | Deletes all other `ksu_gaming_x` files |

---

## 4. Safe Configuration Editing
- **Recommended**: Use toggles and dialogs in the **KSU Gaming X APK**.
- **Via CLI (`kgxctl`)**:
  ```sh
  su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl engine get"
  su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl engine set SPOOF_EXCLUDE_SETTINGS 1"
  ```
- **Back up before experimenting**:
  ```sh
  su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl backup create before_test"
  ```

---

## 5. Warnings & Common Mistakes
- **Never hand-edit `orig_display.env` or `orig_props.tsv`**: These capture stock snapshots for restoration; corrupting them causes wrong restores.
- **If settings cause lag or heat**: Toggle `SAFE_MODE=1` in the app or tap **Action** in KernelSU Manager for immediate rollback.
