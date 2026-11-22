# Cấu hình & Tùy chọn (Configuration)

## 1. Mục đích
Giải thích toàn bộ các khóa cấu hình trong `/data/adb/ksu_gaming_x/config/global.conf` (khởi tạo từ [default_global.conf](../module/data/default_global.conf)) và các tệp danh sách đi kèm để người mới hiểu rõ từng công tắc làm gì trước khi thay đổi.

---

## 2. Đường dẫn file cấu hình trên máy
Khi module hoạt động trên Android, toàn bộ dữ liệu bền vững (không mất khi nâng cấp ZIP) được lưu tại `/data/adb/ksu_gaming_x/`:
- `config/global.conf` — Cấu hình toàn cục (được Companion App chỉnh qua `kgxctl engine set <KEY> <VALUE>`).
- `config/custom_games.tsv` — Danh sách game do người dùng tùy biến (10 cột phân tách bằng tab).
- `config/spoof_denylist.list` — Danh sách package ứng dụng **không bị spoof** (bởi Zygisk Shield).
- `config/freezer_apps.list` — Danh sách package được phép đóng băng nền khi chơi game (`FREEZER_ENABLED=1`).
- `profiles/custom_profiles.tsv` — Hồ sơ thiết bị spoof tự tạo.

---

## 3. Bảng thông số `global.conf`

| Khóa | Mặc định | Ý nghĩa | Cảnh báo / Lưu ý |
|---|---|---|---|
| `AUTO_OPTIMIZE` | `1` | Tự nhận diện game foreground qua daemon `kgx-core` | Tắt (`0`) để dừng tự động áp profile khi mở game |
| `SAFE_MODE` | `0` | Chế độ an toàn khẩn cấp | Nếu bật `1`, module hoàn nguyên mọi thông số gốc và không chạy daemon |
| `SPOOF_ENABLED` | `1` | Bật/tắt toàn bộ cơ chế spoof tên máy | Tác dụng toàn hệ thống trừ gói được bảo vệ bởi Zygisk Shield |
| `PLAY_INTEGRITY_SHIELD` | `1` | Zygisk hoàn nguyên prop gốc cho GMS/Play Store/GSF/Wallet | Cần Zygisk/ReZygisk hoạt động |
| `SPOOF_EXCLUDE_SETTINGS` | `1` | Không spoof ứng dụng Cài đặt Android/Samsung/OEM | Giúp Cài đặt hiển thị đúng thông tin gốc |
| `GLOBAL_SPOOF_PROFILE` | `realme_14_5g` | ID thiết bị spoof mặc định từ `devices.tsv` hoặc `custom_profiles.tsv` | Cần có Zygisk hoặc `resetprop` |
| `DEFAULT_MODE` | `high_performance` | Chế độ hiệu năng mặc định (`balanced`, `high_performance`, `extreme_gaming`, `battery_gaming`) | Không áp `extreme_gaming` nếu máy nóng sẵn |
| `FPS_ENGINE_ENABLED` | `1` | Bật chỉnh GameManager (`cmd game` / `device_config game_overlay`) | Chỉ áp khi process game **chưa chạy** để tránh `killUid` |
| `DISPLAY_AUTO_HZ` | `1` | Tự động chỉnh `min/peak_refresh_rate` theo cấu hình game | Có guard chống kẹt 60Hz và chuẩn hóa `120.1 -> 120.0` |
| `TOUCH_OPT_ENABLED` | `1` | Tối ưu node cảm ứng khi vào game (nếu node tồn tại) | Hoàn nguyên qua `sysfs_restore_all` khi thoát game |
| `RAM_OPT_ENABLED` | `1` | Cân chỉnh `swappiness` / `vfs_cache_pressure` & dọn nền có chọn lọc | Tuyệt đối không chạy `am kill-all` |
| `THERMAL_GUARD_ENABLED` | `1` | Bảo vệ nhiệt độ tự động (NORMAL → WARM → HOT → CRITICAL) | Nên giữ `1` để tránh tắt nguồn vì nóng |
| `THERMAL_UNLOCK` | `0` | Nâng trần xung nhiệt (`EXYNOS_UFCC` / devfreq GPU) *(EXPERIMENTAL trên máy mới)* | Chỉ bật khi tản nhiệt tốt; **không** sửa `trip_point_*` |
| `SUSTAINED_SWEET_SPOT` | `0` | Khóa trần xung ổn định (~82% peak trên Exynos) thay vì bung 100% gây tụt FPS sớm | Phù hợp chơi dài trên Exynos 2200 |
| `MAX_CLOCK_LOCK` | `0` | Giữ tần số min/max cao hơn theo bảng trong `cpu_gpu.sh` | Tốn pin và nóng nhanh hơn |
| `SOFT_THERMAL_STEP` | `0` | Hạ bậc xung mềm theo ngưỡng nhiệt trước khi lag nặng | Chỉ áp khi đang trong phiên game |
| `GOS_NEUTRALIZE` | `0` | Vô hiệu hóa tạm thời `com.samsung.android.game.gos` (`pm disable-user`) | Tự bật lại khi tắt tùy chọn hoặc bật `SAFE_MODE=1` |
| `EXT_DISPLAY_SCREEN_OFF` | `0` | Tự tắt chỉ màn hình điện thoại khi cắm màn hình ngoài | Có safety guard **cấm tắt** nếu không phát hiện màn hình ngoài |
| `RES_OVERRIDE_ENABLED` | `0` | Đổi độ phân giải hệ thống (`wm size` / `wm density`) | Tự reset khi ngắt điều kiện |
| `RES_OVERRIDE_SCOPE` | `ext_scrcpy` | Phạm vi áp dụng độ phân giải: `ext_scrcpy` hoặc `always` | `always` đổi độ phân giải liên tục ngay cả khi rút cáp |
| `RES_OVERRIDE_PRESET` | `1080x1920` | Độ phân giải đích cho `RES_OVERRIDE_ENABLED` | Hỗ trợ các ngưỡng `480..3840` hợp lệ |
| `RES_OVERRIDE_DENSITY` | `auto` | DPI khi đổi độ phân giải (`auto` hoặc số nguyên 240–640) | Tự tính tỉ lệ theo chiều rộng gốc |
| `FREEZER_ENABLED` | `0` | Đóng băng các app trong `freezer_apps.list` qua `cgroup.freeze` v2 | Không đóng băng app đang mở ở View/Samsung DeX |
| `THERMAL_ALERT_ENABLED` | `1` | Bật cảnh báo nhiệt độ trong overlay / trạng thái | — |
| `THERMAL_ALERT_BATT_C` | `44` | Ngưỡng cảnh báo nhiệt pin (°C) | — |
| `THERMAL_ALERT_CPU_C` | `92` | Ngưỡng cảnh báo nhiệt CPU (°C) | — |
| `THERMAL_ALERT_ACTION` | `notify` | Hành động khi vượt ngưỡng (`notify`, `step_down`, `bypass`, `both`) | — |
| `BYPASS_CHARGING` | `0` | Chuyển dòng sạc nuôi máy trực tiếp qua `batt_slate_mode`/`input_suspend`/`charging_enabled` | Yêu cầu kernel có node tương ứng |
| `BYPASS_MIN_PCT` | `80` | Mức pin tối thiểu để bật Bypass Charging (hysteresis -3%) | Tránh tụt sạch pin khi vừa sạc vừa chơi |
| `POLL_INTERVAL_ACTIVE` | `2` | Chu kỳ quét (giây) khi đang trong game | Từ 1–30s |
| `POLL_INTERVAL_IDLE` | `1` | Chu kỳ quét (giây) khi ngoài game | Từ 1–30s |
| `EXIT_DEBOUNCE_SEC` | `2` | Thời gian chờ (giây) sau khi rời game mới hoàn nguyên | Tránh giật cấu hình khi lỡ chạm ra ngoài 1 giây |
| `KEEP_BACKUPS_ON_UNINSTALL` | `0` | Nếu `1`, giữ thư mục `backups/` khi gỡ module | Xóa các mục còn lại của `ksu_gaming_x` |

---

## 4. Cách chỉnh cấu hình an toàn
- **Cách dễ nhất (khuyên dùng)**: Chỉnh bằng các công tắc/menu trong ứng dụng **KSU Gaming X APK**.
- **Cách qua dòng lệnh (`kgxctl`)**:
  ```sh
  su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl engine get"
  su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl engine set SPOOF_EXCLUDE_SETTINGS 1"
  ```
- **Cách sao lưu trước khi thử nghiệm**:
  ```sh
  su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl backup create truoc_khi_thu"
  ```

---

## 5. Cảnh báo & Lỗi thường gặp
- **Không tự sửa tay `orig_display.env` hay `orig_props.tsv`**: Đây là ảnh chụp trạng thái gốc dùng để hoàn nguyên. Sửa sai sẽ khiến module khôi phục nhầm giá trị.
- **Nếu cấu hình lỗi làm nóng máy hoặc lag**: Bật `SAFE_MODE=1` trên app hoặc bấm nút **Action** trong KernelSU Manager để `rollback` ngay lập tức.
