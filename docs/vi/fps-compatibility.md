# FPS Compatibility Engine & LTPO 120Hz Refresh-Rate Guard

> **Ngôn ngữ**: [English](../fps-compatibility.md) | **Tiếng Việt**

## 1. Mục đích
Giải thích vì sao không phải lúc nào spoof tên máy cũng mở khóa được 90/120 FPS trong game, cơ chế phân tích 5 yếu tố của module (`fps.sh`), cách chống crash `PlatformCompat killUid` khi chỉnh `GameManager`, và cách bộ bảo vệ 120Hz (`display.sh` + `hw_detect.sh`) ngăn tụt/kẹt 60Hz.

---

## 2. Động cơ phân tích FPS 5 yếu tố (`fps_analyze_json`)
Module **không hứa hẹn viển vông** rằng mọi game đều lên 120 FPS. Khi bạn chọn game, `kgxctl games get <pkg>` và app sẽ tính trần FPS thật sự dựa trên đúng **5 giới hạn**:

$$\text{Effective FPS} = \min(\text{Requested FPS},\ \text{Game Engine Cap},\ \text{Display Max Hz},\ \text{Thermal Cap})$$

| Bộ giới hạn (`primary_limiter`) | Ý nghĩa thực tế |
|---|---|
| `THERMAL_LIMIT` | Nhiệt độ máy đang ở mức `HOT` (giới hạn 90 FPS) hoặc `CRITICAL` (giới hạn 60 FPS) |
| `DISPLAY_LIMIT` | Tần số quét tối đa của màn hình nhỏ hơn FPS yêu cầu (VD màn 60Hz không thể hiển thị 120 FPS) |
| `GAME_LIMIT` | Bản thân engine của game khóa cứng trên Android (VD *Genshin Impact* khóa `GAME_CAP 60 FPS`, spoof máy khác cũng không vượt được trần Android trừ khi dùng mod game — mà module **không** làm) |
| `WHITELIST_LIMIT` | Game khóa 90/120 FPS theo whitelist thiết bị (`WHITELIST`), nhưng Spoof đang tắt hoặc chưa khớp |
| `HARDWARE_LIMIT` | Game cho phép mở nhưng SoC/GPU xếp hạng (`HW_TIER`) có thể không giữ vững đều mức FPS đó khi tải nặng |

---

## 3. Bảo vệ chống văng game (`PlatformCompat killUid` trên Android 12+)
Trên Android 12+, gọi `cmd game mode/downscale` hoặc `device_config put game_overlay` **trong lúc game đang chạy** sẽ kích hoạt `PlatformCompat.putOverridesOnReleaseBuilds()` gọi thẳng `killUid()`, làm game văng lập tức.
Cách module xử lý trong [module/lib/fps.sh](../../module/lib/fps.sh):
- Cấu hình `GameManager` / `downscale` được **pre-apply trước khi game chạy** (lúc bạn lưu cấu hình game hoặc khi khởi động `service.sh`).
- Khi phát hiện game đang chạy (`fps_is_pkg_running`), `fps_apply` và `session_deactivate` **tuyệt đối không** gọi `cmd game` hay `device_config` (chỉ dọn `gamemgr_applied.tsv` khi thật sự tắt/rollback qua `Safemode` hoặc `games clear`/lúc game không chạy).

---

## 4. Bộ bảo vệ 120Hz LTPO & Khôi phục sau Reboot (`hw_detect.sh` + `display.sh`)
Trên máy Samsung LTPO 10–120Hz (đã kiểm chứng thực tế trên Galaxy S22 Exynos One UI 4.1), module xử lý 4 lỗi phổ biến:
1. **Cô lập màn hình chính khỏi HDMI / Desktop DeX**: Chỉ lấy `supportedModes` của dòng `DisplayDeviceInfo{` có `type INTERNAL` / `FLAG_DEFAULT_DISPLAY`, không bị trộn tần số 50/70/75Hz của màn hình ngoài.
2. **Tránh lỗi tràn đối số `mksh` (`Argument list too long`)**: Xuất output `dumpsys display` và `dumpsys SurfaceFlinger` ra file tạm rồi xử lý bằng `awk`, có fallback kernel `/sys/class/drm/*DSI*/modes` và `/sys/class/lcd/panel/vrr`.
3. **Không bao giờ hạ cấp `hw_profile.env`**: Nếu đã nhận `DISPLAY_MAX_HZ > 60` mà lần quét mới rỗng/lỗi, vẫn giữ nguyên profile `>60Hz` cũ và ghi log cảnh báo; nếu lỡ dính `60`, `hw_load()` và `kgx-core` tự quét lại một lần khi `sys.boot_completed=1`.
4. **Chuẩn hóa bẫy `120.1` của SamHelper & bật Seamless 120Hz**:
   - SamHelper thường ghi `120.1`, lớn hơn mode panel thật `120.00001 Hz` khiến `DisplayModeDirector` từ chối và hạ về 60Hz. `display_sanitize_hz_val()` tự chuẩn hóa `120.1 -> 120.0`.
   - Khi `chosen >= 90`, module luôn bật `secure refresh_rate_mode 1` (và `system refresh_rate_mode 1` nếu có).
   - Khi máy tắt đột ngột/soft-reboot lúc còn `active_display.env`, `service.sh` gọi `display_recover_on_boot` **trước** khi dọn state và `kgx-core` gọi `call_kgxctl_cleanup()` khi nhận `SIGTERM`/`SIGINT`/`SIGHUP`.

---

## 5. Giới hạn thực tế khi dùng Samsung DeX
Khi chạy game bên trong cửa sổ **Samsung DeX (`Display #2`)**, game hỏi Android API tần số quét của chính màn hình mà nó đang hiển thị (`Display #2`), **không phải** màn hình điện thoại (`Display #0`).
- Nếu màn hình HDMI gắn ngoài chỉ hỗ trợ tối đa 60Hz hoặc 75Hz (`Display #2` báo `75.0 Hz`), các game như *Delta Force Mobile* sẽ **tự làm mờ nút 90/120 FPS** dù Spoof đã nhận đúng `V2425A`.
- **Cách xử lý hiện tại**: Mở game trực tiếp trên màn hình điện thoại (`Display #0` — 120Hz).

---

## 6. Kiểm tra nhanh bằng dòng lệnh
```sh
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl hw"
su -c "settings get system min_refresh_rate; settings get system peak_refresh_rate; settings get secure refresh_rate_mode"
su -c "dumpsys display | grep -E 'mDisplayModeSpecs=|baseModeId=' | head -n 5"
```
Trạng thái khỏe mạnh trên S22: `min=120.0`, `peak=120.0`, `sec_rrm=1`, `baseModeId=1`, `DISPLAY_SUPPORTED_HZ='30 48 60 96 120'`.
