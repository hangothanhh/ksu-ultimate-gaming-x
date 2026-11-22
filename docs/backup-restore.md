# Backup, Update, Rollback, Uninstall & Recovery

> **Language**: **English** | [Tiếng Việt](vi/backup-restore.md)

## 1. Purpose
Detailed procedures for backing up configuration (`backup.sh`), updating safely, rolling back bad settings, cleanly uninstalling the module, and recovering from boot issues.

---

## 2. Backup & Restore (`kgxctl backup`)

### Create a Backup
Saves `config/`, `profiles/`, and stock snapshots (`state/orig_props.tsv`, `state/orig_display.env`, `state/orig_net.env`) to `/data/adb/ksu_gaming_x/backups/kgx_backup_<date>_<label>.tar.gz`:
```sh
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl backup create manual"
```

### List & Restore Backups
```sh
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl backup list"
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl backup restore kgx_backup_20261122_120000_manual.tar.gz"
```

---

## 3. Updating to a New Version
1. **Check installed version**: Open the Companion APK or read `/data/adb/modules/ksu_ultimate_gaming_x/module.prop`.
2. **Back up config**: Run `kgxctl backup create pre_update` (or use Backup inside the app).
3. **Download & verify SHA-256**: Get the new release from [GitHub Releases](https://github.com/hangothanhh/ksu-ultimate-gaming-x/releases) and verify checksums per [docs/installation.md](installation.md).
4. **Are settings preserved?**:
   - Always check `CHANGELOG.md` first.
   - In `v1.0.0` `customize.sh`, upgrades **preserve** `/data/adb/ksu_gaming_x/config/` (`global.conf`, `custom_games.tsv`, `spoof_denylist.list`), `profiles/custom_profiles.tsv`, and automatically migrate missing keys (`PLAY_INTEGRITY_SHIELD`, `SPOOF_EXCLUDE_SETTINGS`, `orig_display.env`).
5. **Install update**: Flash the new Module ZIP inside KernelSU Manager and update the Companion APK if updated. Reboot (or perform a clean Soft-Reboot when `zygisk/arm64-v8a.so` changed).
6. **Post-update check**: Run `kgxctl status` and `kgxctl hw`.

---

## 4. Instant Rollback (If Settings Cause Lag, Heat, or Issues)
- **Method 1 (Companion App)**: Toggle **Safe Mode (`SAFE_MODE=1`)** — stops the daemon and restores all properties, resolution, refresh rate, GOS, and freezer states immediately.
- **Method 2 (KernelSU Manager Action button)**: Tap **Action** next to `KSU Ultimate Gaming X` (`module/action.sh` executes `kgxctl rollback` and restarts cleanly).
- **Method 3 (ADB / Root Terminal)**:
  ```sh
  su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl safemode on"
  su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl rollback"
  ```

---

## 5. Clean Uninstall

### Standard Procedure
1. Open **KernelSU Manager → Modules**.
2. To disable temporarily without wiping settings: toggle the module **OFF** and reboot.
3. To remove completely: tap **Uninstall (Trash icon)** and reboot. On next boot, `module/uninstall.sh`:
   - Stops `kgx-core`.
   - Restores GOS, network, touch, unfreezes all `cgroup.freeze` apps, disables Bypass Charging, restores RAM/thermal/CPU/GPU, resets `wm size`/`density`, turns internal display back on, restores refresh rate, clears `GameManager` state, and deletes `system.prop` / spoof props.
   - Deletes `/data/adb/ksu_gaming_x` (preserving only `backups/` if `KEEP_BACKUPS_ON_UNINSTALL=1`).
4. Uninstall the **KSU Gaming X APK** like a regular Android app.

### Verify Zero Leftover Background Services
```sh
ps -A | grep -E 'kgx-core|gaming_daemon' || echo "Clean"
ls -la /data/adb/modules/ksu_ultimate_gaming_x 2>/dev/null || echo "Module removed"
```

---

## 6. Recovery Guide by Severity

| Scenario | Safe & Verified Recovery Method | Data Loss Risk |
|---|---|---|
| **Only APK crashes / UI fails** | Clear APK cache/data or reinstall APK matching SHA-256; background module remains safe | None |
| **Module not loading / inactive** | Verify KernelSU is active (especially on temproot) and check whether `SAFE_MODE=1` is set | None |
| **Sudden lag / overheating after tweaking** | Tap **Action** in KernelSU Manager or run `kgxctl safemode on` | None |
| **Bootloop (stuck on boot logo)** | **Built-in protection**: `post-fs-data.sh` tracks `boot_counter`. After **2 consecutive failed boots**, it automatically enables `SAFE_MODE=1`, deletes `system.prop`, and restores stock properties. | None |
| **Still cannot boot Android** | Boot into **KernelSU Safe Mode** (hold Volume Down on supported KernelSU builds to disable all modules); on **KernelSU temproot**, a force power-off / normal cold boot returns to stock unrooted Android; on permanent KSU, re-flash stock `boot.img` via Odin/Fastboot. | **WARNING**: Flashing wrong partitions or running Wipe Data / Factory Reset in Recovery **ERASES ALL PERSONAL DATA**! Never manually delete files under `/system`. |
