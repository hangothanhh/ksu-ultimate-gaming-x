# Quản lý Nhiệt độ, Exynos Sweet-Spot & Bypass Charging

## 1. Mục đích
Giải thích cách `thermal.sh`, `power.sh`, `gos.sh` và `kgx-core` theo dõi nhiệt độ pin/CPU/GPU, cách hoạt động của chế độ **Sustained Sweet-Spot**, **Soft Thermal Step-Down**, **Bypass Charging**, **Samsung GOS Neutralizer** và các ranh giới bảo vệ phần cứng tuyệt đối.

---

## 2. Ranh giới bảo vệ phần cứng tuyệt đối
> [!IMPORTANT]
> Module **KHÔNG BAO GIỜ** vô hiệu hóa Thermal Protection của silicon hay sửa các node `trip_point_*` (`kgx_is_protected_sysfs()` chặn mọi thao tác ghi vào `trip_point_*`, `*tmu*`, `throttling`, `*ifpo*`, `selinux`). Bảo vệ nhiệt phần cứng của kernel vẫn hoạt động 100% để ngăn cháy nổ hoặc sập nguồn.

Ngoài ra, qua kiểm tra dump crash thực tế trên Galaxy S22 Exynos 2200 (`SError 0xbe000011`), module tuyệt đối **cấm ghi `/sys/kernel/gpu/gpu_ifpo_control`** (Inter-Frame Power Off) khi đang render để tránh panic/reboot.

---

## 3. Các chế độ nhiệt & nguồn

### A. Thermal Guard mặc định (`THERMAL_GUARD_ENABLED=1`)
Theo dõi liên tục cảm biến pin, CPU và GPU theo các ngưỡng trong `global.conf` (`THERMAL_WARN_*`, `THERMAL_HOT_*`, `THERMAL_CRIT_*`) với độ trễ hysteresis:
- `NORMAL`: cho phép full mode đã chọn.
- `WARM` (`batt >= 38°C` hoặc `cpu >= 68°C`): chuẩn bị giảm áp lực nhiệt.
- `HOT` (`batt >= 41°C` hoặc `cpu >= 76°C`): hạ mục tiêu FPS tối đa xuống `90 FPS`.
- `CRITICAL` (`batt >= 44°C` hoặc `cpu >= 85°C`): hạ trần FPS xuống `60 FPS` và nới xung min/max về an toàn.

### B. Sustained Sweet-Spot (`SUSTAINED_SWEET_SPOT=1`) & Thermal Unlock (`THERMAL_UNLOCK=1`)
- **Sustained Sweet-Spot** (khuyên dùng cho Exynos 2200 khi chơi dài): Khóa trần xung ở vùng hiệu suất ổn định (~82% peak, VD GPU ~1095 MHz thay vì 1306 MHz) để giữ khung hình đều mà không bị nhiệt bùng lên quá sớm.
- **Thermal Unlock** (*EXPERIMENTAL trên thiết bị chưa kiểm chứng*): Nới giới hạn phần mềm ở `exynos-ufcc` / `exynos-migov` (bảo toàn silicon `trip_point_*`), vẫn tự chuyển sang `UNLOCKED_COOL` (giữ trần max nhưng nới xung min idle) nếu CPU `>= 82°C` hoặc pin `>= 44°C`.

### C. Soft Thermal Step-Down (`SOFT_THERMAL_STEP=1`) & Thermal Alert
- Tự hạ bậc nhẹ xung đỉnh theo 2 tier trước khi máy đạt ngưỡng quá nhiệt nặng (`thermal_alert_action` hỗ trợ `notify`, `step_down`, `bypass`, `both`).

### D. Safe Bypass Charging (`BYPASS_CHARGING=1`, `power.sh`)
- Khi máy đang cắm sạc **và** phần trăm pin `>= BYPASS_MIN_PCT` (mặc định `80%`, hysteresis tắt khi `< BYPASS_MIN_PCT - 3%` = `77%`), module kích hoạt node sạc nhánh tương ứng của kernel (`batt_slate_mode`, `input_suspend`, `charging_enabled` hoặc `store_mode`) để nuôi máy trực tiếp từ sạc, giảm nhiệt sinh ra từ quá trình nạp pin.
- Tự khôi phục dòng sạc bình thường ngay khi thoát game, rút sạc, bật `SAFE_MODE=1` hoặc gỡ module.
- **Hạn chế**: Phụ thuộc kernel và phần cứng máy có cung cấp sysfs node hỗ trợ sạc nhánh hay không (xem `bypass_supported` trong `kgxctl status`).

### E. Samsung GOS Neutralizer (`GOS_NEUTRALIZE=1`, `gos.sh`)
- Vô hiệu hóa tạm thời gói `com.samsung.android.game.gos` qua `pm disable-user` khi bật tùy chọn (chỉ trên máy Samsung có gói này), và bật lại (`pm enable`) ngay khi tắt hoặc kích hoạt `SAFE_MODE=1` / gỡ module.

---

## 4. Cảnh báo & Khắc phục
- Không vừa bật `THERMAL_UNLOCK=1` + `MAX_CLOCK_LOCK=1` vừa sạc nhanh trong môi trường nóng bí. Nếu thấy máy nóng bất thường (`> 44°C` pin), tắt `THERMAL_UNLOCK` và `MAX_CLOCK_LOCK`, ưu tiên `SUSTAINED_SWEET_SPOT=1` hoặc quạt tản nhiệt.
- Nếu lỡ kẹt cấu hình xung/pin do máy tắt ngang: `service.sh` sẽ gọi `thermal_restore_unlock` và `uninstall.sh` gọi `power_bypass_restore` + `gos_restore` + `sysfs_restore_all`.
