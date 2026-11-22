# Zygisk Stock-Identity & Denylist Shield (`KGX_PIShield`)

This directory contains the C++17 source for the **Zygisk API v4** companion library ([src/main.cpp](src/main.cpp)), compiled to `module/zygisk/arm64-v8a.so`.

## Purpose & Behaviour
- Reads `/data/adb/ksu_gaming_x/config/global.conf`, `/data/adb/ksu_gaming_x/state/orig_props.tsv`, `/data/adb/ksu_gaming_x/state/active_spoof.env`, and `/data/adb/ksu_gaming_x/config/spoof_denylist.list`.
- Isolates Google Play Services / Play Store / GSF / Wallet (`PLAY_INTEGRITY_SHIELD=1`), Android/OEM Settings (`SPOOF_EXCLUDE_SETTINGS=1`), and user-selected packages in `spoof_denylist.list` back to the genuine stock values from `orig_props.tsv` using `__system_property_read_callback` PLT hooks and `android.os.Build` / `Build.VERSION` JNI reflection.
- Executable-only PLT filter hooks only mapped executable `.so` libraries (skipping `.apk`/`.odex`/`.vdex` mappings).
- Non-excluded apps and games unload immediately (`DLCLOSE_MODULE_LIBRARY`). Never modifies verified boot, `ro.serialno`, IMEI, or attestation keys.

## Building with Android NDK (ARM64)
Built directly via `scripts/build_rust.py` (`aarch64-linux-android29-clang++ -std=c++17 -shared -fPIC -static-libstdc++ -llog -ldl`), referencing the unmodified Zygisk API v4 header in [include/zygisk.hpp](include/zygisk.hpp) (Copyright 2022–2023 John "topjohnwu" Wu). Requires ReZygisk or Zygisk Next on the target device.
