# Optional Zygisk Per-Process Spoof Companion

This directory contains the C++17 source for the **Layer 2 (Zygisk-assisted)** companion library (`libkgx_zygisk_spoof.so`).

## Why this exists alongside Pure KernelSU
- **Pure KernelSU (`resetprop`)**: Modifies native Android system properties (`__system_property_get`) dynamically when a game enters the foreground and restores stock values on exit. Works out-of-the-box on KernelSU without Zygisk.
- **Zygisk Companion (`android.os.Build`)**: Some games read static Java `android.os.Build.MODEL` / `BRAND` / `MANUFACTURER` / `DEVICE` / `PRODUCT` / `FINGERPRINT` fields cached during Zygote app specialization. This optional companion reads `/data/adb/ksu_gaming_x/state/zygisk_rules.conf` inside the privileged Zygisk companion daemon and updates `android.os.Build` ONLY inside the target game process via JNI, then immediately unloads itself (`DLCLOSE_MODULE_LIBRARY`).

## Building with Android NDK (ARM64)
1. Place `zygisk.hpp` (Zygisk API v4 header from ZygiskNext / ReZygisk) in `companion/zygisk-spoof/include/zygisk.hpp`.
2. Configure & build with Android NDK r26+ (`arm64-v8a`):
   ```sh
   cmake -B build \
     -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" \
     -DANDROID_ABI=arm64-v8a \
     -DANDROID_PLATFORM=android-29
   cmake --build build --config Release
   ```
3. Copy `build/libkgx_zygisk_spoof.so` into `module/zygisk/arm64-v8a.so` before packaging the ZIP if you want bundled Zygisk support (requires ZygiskNext or ReZygisk installed on KernelSU).
