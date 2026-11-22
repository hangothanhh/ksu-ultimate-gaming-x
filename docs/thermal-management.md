# Thermal Management, Exynos Sweet-Spot & Bypass Charging

> **Language**: **English** | [Tiếng Việt](vi/thermal-management.md)

## 1. Purpose
Explains how `thermal.sh`, `power.sh`, `gos.sh`, and `kgx-core` monitor battery/CPU/GPU temperatures, alongside **Sustained Sweet-Spot**, **Soft Thermal Step-Down**, **Bypass Charging**, **Samsung GOS Neutralizer**, and non-negotiable hardware safety boundaries.

---

## 2. Hard Silicon Protection Boundaries
> [!IMPORTANT]
> This module **NEVER** disables silicon thermal protection or modifies hardware `trip_point_*` nodes (`kgx_is_protected_sysfs()` blocks every write to `trip_point_*`, `*tmu*`, `throttling`, `*ifpo*`, and `selinux`). Kernel-level thermal protection stays 100% active at all times to prevent hardware damage or unexpected shutdowns.

Based on physical crash analysis on Galaxy S22 Exynos 2200 (`SError 0xbe000011`), writes to **`/sys/kernel/gpu/gpu_ifpo_control`** (Inter-Frame Power Off) are also strictly blocked to avoid kernel panics/reboots while rendering.

---

## 3. Thermal & Power Profiles

### A. Default Thermal Guard (`THERMAL_GUARD_ENABLED=1`)
Monitors battery, CPU, and GPU sensors using `global.conf` thresholds (`THERMAL_WARN_*`, `THERMAL_HOT_*`, `THERMAL_CRIT_*`) with hysteresis:
- `NORMAL`: full configured performance mode allowed.
- `WARM` (`batt >= 38°C` or `cpu >= 68°C`): prepares thermal headroom.
- `HOT` (`batt >= 41°C` or `cpu >= 76°C`): lowers target FPS cap to `90 FPS`.
- `CRITICAL` (`batt >= 44°C` or `cpu >= 85°C`): caps target FPS at `60 FPS` and relaxes min/max clocks for safety.

### B. Sustained Sweet-Spot (`SUSTAINED_SWEET_SPOT=1`) & Thermal Unlock (`THERMAL_UNLOCK=1`)
- **Sustained Sweet-Spot** *(recommended for long Exynos 2200 sessions)*: Locks peak clocks around the efficiency sweet spot (~82% peak, e.g., ~1095 MHz GPU instead of 1306 MHz) to hold steadier frame times without early thermal throttling.
- **Thermal Unlock** *(EXPERIMENTAL on untested hardware)*: Relaxes software caps in `exynos-ufcc` / `exynos-migov` (preserving silicon `trip_point_*`), while automatically shifting to `UNLOCKED_COOL` (keeps ceiling open but drops min idle clocks) if CPU `>= 82°C` or battery `>= 44°C`.

### C. Soft Thermal Step-Down (`SOFT_THERMAL_STEP=1`) & Thermal Alerts
- Applies a gentle 2-tier peak frequency step-down before hitting hard throttling (`thermal_alert_action` supports `notify`, `step_down`, `bypass`, `both`).

### D. Safe Bypass Charging (`BYPASS_CHARGING=1`, `power.sh`)
- When plugged in **and** battery level `>= BYPASS_MIN_PCT` (default `80%`, switches off at `< BYPASS_MIN_PCT - 3%` = `77%`), activates the kernel's charging-bypass sysfs node (`batt_slate_mode`, `input_suspend`, `charging_enabled`, or `store_mode`) so AC power runs the board directly with minimal battery heat.
- Automatically restores normal charging on game exit, unplugging, enabling `SAFE_MODE=1`, or uninstalling.
- **Limitation**: Requires kernel support for one of the bypass sysfs nodes (check `bypass_supported` via `kgxctl status`).

### E. Samsung GOS Neutralizer (`GOS_NEUTRALIZE=1`, `gos.sh`)
- Temporarily disables `com.samsung.android.game.gos` (`pm disable-user`) when toggled on (Samsung devices only), and re-enables (`pm enable`) immediately when disabled, in `SAFE_MODE=1`, or on uninstall.

---

## 4. Warnings & Recovery
- Do not combine `THERMAL_UNLOCK=1` + `MAX_CLOCK_LOCK=1` with fast charging in hot ambient environments. If battery exceeds `44°C`, turn off `THERMAL_UNLOCK` and `MAX_CLOCK_LOCK` and switch to `SUSTAINED_SWEET_SPOT=1` or external cooling.
- After an abrupt shutdown or crash, `service.sh` calls `thermal_restore_unlock`, and `uninstall.sh` executes `power_bypass_restore` + `gos_restore` + `sysfs_restore_all`.
