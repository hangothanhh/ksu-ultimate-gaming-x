# Device Profile Database, Whole-System Spoof & Zygisk Stock-Identity Shield

> **Language**: **English** | [Tiếng Việt](vi/device-database.md)

## 1. Purpose
Explains how the 34-device profile database (`devices.tsv`/`devices.json`), GPU scoring engine (`matcher.sh`), safe system-wide spoofing (`spoof.sh`), and Zygisk Shield (`companion/zygisk-spoof/`) work together without breaking Settings, Google Play, or user-excluded apps.

---

## 2. Device Database & Compatibility Scoring
Bundled with **34 sample device profiles** in [module/data/devices.tsv](../module/data/devices.tsv) and **31 games** in [module/data/games.tsv](../module/data/games.tsv).
In `auto` mode, `matcher_select_auto_profile()` scores profiles using:
- Real device GPU family (`adreno`, `mali`, `xclipse`, or neutral if `unknown`) vs profile GPU.
- Game whitelist preference (`preferred_adreno` / `preferred_mali`).
- Hardware tier distance (`HW_TIER`).
- Supported refresh rate compatibility (`DISPLAY_MAX_HZ`).

> [!IMPORTANT]
> **Manage Expectations**: Database matching (*OPTIMAL / COMPATIBLE*) is a GPU/tier scoring heuristic — **it does NOT guarantee smooth performance or that a game publisher will unlock 120 FPS**. Some games also inspect hardware attestation, `GL_RENDERER` strings, or active display Hz.

---

## 3. Safe Whole-System Spoof (`spoof.sh`)
- Before applying any profile, `spoof_capture_original()` records all stock properties into `/data/adb/ksu_gaming_x/state/orig_props.tsv`.
- Applies properties via `resetprop` and `system.prop` covering **only** model/brand/manufacturer/device/product/marketname (`GLOBAL_SPOOF_PROFILE`).
- **Strictly protected**: never touches `ro.serialno`, `ro.boot.*`, `ro.crypto.*`, `ro.debuggable`, `ro.secure`, `ro.adb.secure`, IMEI, or forces `ro.build.fingerprint` into `system.prop`.

---

## 4. Zygisk Stock-Identity Shield & Spoof Denylist (`arm64-v8a.so`)
Because global spoofing lets games inspect both Java `android.os.Build` and native `SystemProperties` at startup, excluded processes use our Zygisk API v4 library (`companion/zygisk-spoof/src/main.cpp`):
1. **Google Play Services / Store / GSF / Wallet** (`PLAY_INTEGRITY_SHIELD=1`): Restores genuine stock properties inside GMS/DroidGuard, Play Store, GSF, and Google Wallet.
   - *Transparency note*: This prevents module spoofing from corrupting stock device identity during Play Integrity checks. It does **not** guarantee passing Play Integrity (`BASIC`/`DEVICE`/`STRONG`), which depends on bootloader status, root hiding, and separate modules like PIF/TrickyStore.
2. **Android / Samsung / OEM Settings** (`SPOOF_EXCLUDE_SETTINGS=1`): Keeps genuine device info inside `com.android.settings*`, `com.samsung.android.app.settings*`, `com.samsung.android.settings*`, `com.miui.settings`, `com.oplus.settings`, and `com.coloros.settings`.
3. **User Spoof Denylist (`config/spoof_denylist.list`)**: Any app checked under **Spoof Denylist** in the Companion APK (or added via `kgxctl spoof denylist-add <pkg>`) sees genuine stock hardware properties.

---

## 5. CLI Verification & Control
```sh
# Check Zygisk Shield & Play Integrity diagnostic status
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl spoof diag"

# List apps currently excluded from spoofing
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl spoof denylist"

# Add or remove a package from Spoof Denylist
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl spoof denylist-add ru.andr7e.deviceinfohw"
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl spoof denylist-remove ru.andr7e.deviceinfohw"

# Disable spoofing completely (restore stock properties)
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl engine set SPOOF_ENABLED 0"
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl spoof restore"
```
Sample log output when active (`logcat -d -s KGX_PIShield`):
`I KGX_PIShield: Shield active in com.google.android.gms.unstable (20 props, jni=1, scope=pi): V2425A -> stock SM-S901B (r0s)`

---

## 6. Important Notes When Updating Denylist
- Updates to `spoof_denylist.list` and `SPOOF_EXCLUDE_SETTINGS` are detected dynamically via `mtime`/`size`, taking effect on the **next cold launch** of each target app (Force Stop running apps first).
- After upgrading `zygisk/arm64-v8a.so` itself, perform a clean reboot / Soft-Reboot so `zygote64` loads the new `.so`. **Never** overwrite a live `.so` mapped in `zygote64` RAM using `unzip -o`.
