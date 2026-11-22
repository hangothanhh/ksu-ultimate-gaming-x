# Changelog

Mọi thay đổi đáng chú ý của dự án **KSU Ultimate Gaming X** đều được ghi nhận tại đây theo nguồn code và kiểm thử thực tế.

---

## v1.0.0 (2026-11-22)

Phiên bản phát hành công khai đầu tiên (`versionCode=100`, tag `v1.0.0`).

### Added
- **KernelSU Module Engine (`module/`)**:
  - Hỗ trợ `post-fs-data.sh` (bảo vệ chống bootloop sau 2 lần khởi động lỗi liên tiếp → tự kích `SAFE_MODE=1` + khôi phục `system.prop`) và `service.sh` (tự phát hiện phần cứng, khôi phục phiên bị ngắt đột ngột, khởi chạy daemon nền).
  - Giao diện CLI JSON thống nhất `bin/kgxctl` gồm các nhóm lệnh: `status`, `hw`, `games`, `profiles`, `spoof`, `engine`, `touch`, `net`, `backup`, `logs`, `safemode`, `daemon`, `system`, `rollback`, `display`, `overlay-tick`, `freezer`, và `diag` (báo cáo chẩn đoán tự động che dữ liệu nhạy cảm).
  - Bộ thư viện POSIX (`lib/*.sh`): `hw_detect.sh`, `spoof.sh`, `display.sh`, `fps.sh`, `thermal.sh`, `cpu_gpu.sh`, `ram.sh`, `touch.sh`, `power.sh`, `gos.sh`, `freezer.sh`, `network.sh`, `backup.sh`, `matcher.sh`, `session.sh`, `common.sh`.
- **Native ARM64 Rust Daemon (`companion/rust-core/`)**:
  - `bin/kgx-core`: đọc chỉ số hệ thống nhanh (CPU/GPU/RAM/PSI/pin `mW`/`mA`, SurfaceFlinger FPS + 1% Low với `ov_layer.cache`), điều phối thermal/bypass/freezer theo thời gian thực, xử lý tín hiệu `SIGTERM`/`SIGINT`/`SIGHUP` khi tắt daemon hoặc soft-reboot.
- **Zygisk Stock-Identity & Denylist Shield (`companion/zygisk-spoof/`)**:
  - Thư viện `zygisk/arm64-v8a.so` (Zygisk API v4, `-static-libstdc++`, không phụ thuộc `libc++_shared.so`).
  - Khôi phục thông số máy gốc cho Google Play Services / Play Store / GSF / Wallet (`PLAY_INTEGRITY_SHIELD`), ứng dụng Cài đặt Android/OEM (`SPOOF_EXCLUDE_SETTINGS=1`), và danh sách ứng dụng do người dùng chọn (`spoof_denylist.list`).
- **Standalone Companion APK (`companion/android-app/`)**:
  - Ứng dụng Material 3 (Zero-Gradle, build qua `aapt2` + `javac` + `d8` + `zipalign` + `apksigner`) kèm cầu nối JNI Rust (`libkgx_rust.so`).
  - Bao gồm Dashboard trực tiếp, chọn game/profile, trình chọn Spoof Denylist, Scene-style FPS Overlay (`KgxOverlayService`) có khóa chống chạm nhầm, ghi & xem biểu đồ CSV (`SessionRecorder`, `TelemetryChartView`), và 3 Quick Settings Tiles (`KgxModeTileService`, `KgxBypassTileService`, `KgxOverlayTileService`).
- **Automated Verification & CI**:
  - Bộ kiểm thử 7 stage `tests/verify_all.py` (cú pháp POSIX `sh -n`, vệ sinh dòng LF/anti-bashism, đối chiếu DB 34 máy / 31 game, giả lập E2E Adreno / Mali / Exynos 2200, audit Companion APK, kiểm tra ZIP/ELF/SHA-256).
  - GitHub Actions workflow `.github/workflows/ci.yml` chạy kiểm tra tự động (Stage 1–6) trên mọi push/PR.

### Changed
- Chuyển hoàn toàn giao diện điều khiển từ WebUI sang Companion Android APK độc lập (`module/webroot` đã được loại bỏ triệt để).
- Chuẩn hóa đường dẫn build & phiên bản toàn dự án thành `v1.0.0` (`KSU-Ultimate-Gaming-X-v1.0.0.zip` và `KSU-Ultimate-Gaming-X-v1.0.0.apk`).
- Cập nhật `scripts/build_apk.py` đọc cấu hình keystore qua biến môi trường (`KGX_KEYSTORE_*`), tách keystore cục bộ khỏi Git.

### Fixed
- **Sửa văng game giữa trận trên Android 12+**: Không gọi `cmd game` / `device_config` khi tiến trình game đang chạy (tránh Android `PlatformCompat.putOverridesOnReleaseBuilds()` gọi `killUid()`); loại bỏ lệnh `am kill-all` gây chết app chạy nền.
- **Sửa tự khởi động lại trên Exynos 2200 (`SError 0xbe000011`)**: Bỏ thao tác ghi `/sys/kernel/gpu/gpu_ifpo_control` và đưa `*ifpo*` vào danh sách node bảo vệ tuyệt đối trong `kgx_is_protected_sysfs()`.
- **Sửa rớt về 60Hz & kẹt 60Hz sau Soft/Hard Reboot (Galaxy S22 LTPO / One UI 4.1)**:
  - Cô lập chế độ màn hình chính (`type INTERNAL` / `FLAG_DEFAULT_DISPLAY`), loại bỏ Hz màn ngoài HDMI/DeX (50/70/75Hz).
  - Ghi output `dumpsys` ra file tạm để tránh lỗi `mksh` `/system/bin/printf: Argument list too long` (~128KB argv limit) khi cắm HDMI + Desktop virtual display.
  - Bổ sung fallback `dumpsys SurfaceFlinger` + kernel DRM/panel `vrr` sysfs, guard chống hạ cấp `hw_profile.env`, tự chữa trong `hw_load()` và Rust `kgx-core`.
  - Xử lý bẫy số thập phân `120.1` của SamHelper → chuẩn hóa `120.0`, luôn bật `refresh_rate_mode=1` khi >= 90Hz, tự phục hồi trong `service.sh` và tắt daemon qua `call_kgxctl_cleanup()`.
- **Sửa lọc PLT hook Zygisk**: Chỉ móc nối thư viện `.so` có quyền thực thi (`x`), tránh đưa `.apk`/`.odex`/`.vdex` dưới `/data/app/` vào `pltHookRegister`.

### Removed
- Loại bỏ `module/webroot` (WebUI cũ) để chuyển sang Companion Android APK thuần native/Material 3.
- Loại bỏ việc dùng `cmd netpolicy` và `am kill-all` (đều bị khóa kiểm tra trong `tests/verify_all.py`).

### Security
- Thêm cơ chế bảo vệ chống ghi `ro.serialno`, `ro.boot.*`, `ro.crypto.*`, `ro.debuggable`, `ro.secure`, `ro.adb.secure`, IMEI và MAC trong cả shell lẫn C++ Zygisk.
- Thêm `kgxctl diag` tự động che serial, IMEI, MAC, email, IP nội bộ/công cộng (trừ DNS công cộng kiểm ping như `1.1.1.1`) và token/mật khẩu.
- Bổ sung `.gitignore` loại trừ `*.keystore`, `*.jks`, `*.idsig`, `dist/` và `module/system.prop`.

### Known Issues
- **120 FPS trong Samsung DeX trên màn hình ngoài <= 75Hz**: Game (VD Delta Force Mobile) kiểm tra tần số quét của chính `Display` mà nó đang chạy (`Display #2` DeX). Khi màn HDMI gắn ngoài chỉ hỗ trợ 60–75Hz, game sẽ khóa chọn 90/120 FPS dù đã spoof model. Mở game trên màn hình chính (`Display #0` — 120Hz) sẽ nhận đủ tùy chọn.
- **Khởi động lại mềm (`ksud soft-reboot`) trên Samsung + ADB Wi-Fi**: Samsung `soft-reboot` có thể mất kết nối ADB Wi-Fi hoặc kích hoạt watchdog hệ thống nếu có xung đột service camera; chỉ nên dùng Soft-Reboot trực tiếp khi đã sao lưu dữ liệu và nạp được temproot/root bình thường.
- **Độ phủ thiết bị thật**: Hiện mới được kiểm chứng thực tế trên Samsung Galaxy S22 Exynos (SM-S901B, Android 12 One UI 4.1). Các cấu hình Qualcomm Adreno và MediaTek Mali hiện mới được kiểm tra bằng mock test.

### Compatibility
- `VERIFIED`: Samsung Galaxy S22 Exynos (`SM-S901B`, `r0s`, `s5e9925`, Android 12 / API 31, One UI 4.1, KernelSU temproot + ReZygisk).
- `PARTIAL`: Qualcomm Adreno & MediaTek Mali (chỉ kiểm thử logic qua POSIX mock trong `tests/verify_all.py`).
- `UNSUPPORTED`: ARMv7 32-bit, Android < 8.0 (API < 26), WebUI cũ.
