# Khắc phục sự cố, FAQ & Báo cáo chẩn đoán (`kgxctl diag`)

## 1. Mục đích
Tổng hợp các lỗi người mới hay gặp khi sử dụng **KSU Ultimate Gaming X** theo cấu trúc: *Biểu hiện → Nguyên nhân có thể → Cách kiểm tra → Cách xử lý → Khi nào cần gửi log*.

---

## 2. Hướng dẫn xuất Diagnostic Report an toàn trước khi hỏi lỗi
> [!IMPORTANT]
> Trước khi gửi log lên GitHub Issues, luôn dùng `kgxctl diag`. Lệnh này **tự động che** serial, IMEI, địa chỉ MAC, email, IP riêng và token/mật khẩu thành `[REDACTED_*]`. Không tự chụp ảnh hoặc dán log thô chưa ẩn thông tin cá nhân!

```sh
# In trực tiếp báo cáo đã ẩn thông tin ra màn hình
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl diag"

# Hoặc xuất thẳng ra thư mục Download để gửi kèm Issue
su -c "/data/adb/modules/ksu_ultimate-gaming-x/bin/kgxctl diag /sdcard/Download/kgx_diag.txt"
```
*(Sửa đúng đường dẫn `/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl diag /sdcard/Download/kgx_diag.txt`.)*

Nếu vẫn mở được APK, báo cáo chẩn đoán ghi rõ: version module (`v1.0.0`), Android/API, kernel, KernelSU, SoC/GPU, trạng thái daemon, các cờ tính năng và 40 dòng log gần nhất (đã redact). Gửi tại: https://github.com/hangothanhh/ksu-ultimate-gaming-x/issues/new/choose

---

## 3. Danh sách lỗi thường gặp & Cách xử lý

### 1. Module không xuất hiện trong KernelSU Manager
1. **Biểu hiện**: Flash xong không thấy `KSU Ultimate Gaming X` trong tab Mô-đun.
2. **Nguyên nhân có thể**: Bạn chưa khởi động lại sau khi flash (với máy KSU thông thường); hoặc trên máy temproot bạn đã bấm *Reboot* thường làm mất KernelSU; hoặc bạn lỡ tải nhầm file *Source code ZIP* thay vì `KSU-Ultimate-Gaming-X-v1.0.0.zip`.
3. **Cách kiểm tra**: Mở KernelSU Manager xem phần trạng thái trên cùng có báo *Đang hoạt động* không; kiểm tra trong file ZIP vừa flash có `module.prop` ở thư mục gốc không.
4. **Cách xử lý**: Tải đúng file `KSU-Ultimate-Gaming-X-v1.0.0.zip` từ Releases, kiểm tra SHA-256, rồi flash lại.

### 2. Cài file ZIP thất bại (`! Unsupported ...`)
1. **Biểu hiện**: Màn hình flash báo lỗi đỏ có dấu `!`.
2. **Nguyên nhân có thể**: Thiết bị không phải `arm64-v8a` (VD máy chạy Android 32-bit `armeabi-v7a` hoặc giả lập x86), Android thấp hơn 8.0 (`API < 26`), hoặc file ZIP bị hỏng lúc tải.
3. **Cách kiểm tra**: Đọc dòng thông báo chính xác trên log cài đặt và chạy `certutil` / `sha256sum` kiểm tra file ZIP.
4. **Cách xử lý**: Máy 32-bit và Android < 8.0 thuộc nhóm `UNSUPPORTED`; nếu lỗi do tải thiếu byte, tải lại ZIP khớp SHA-256.

### 3. Tìm không thấy WebUI trong KernelSU
1. **Biểu hiện**: Không mở được WebUI trong KernelSU Manager.
2. **Nguyên nhân**: Từ kiến trúc mới (đã phát hành ở `v1.0.0`), **WebUI cũ (`module/webroot`) đã bị loại bỏ hoàn toàn** và được thay thế bằng **Companion Android APK** (`KSU-Ultimate-Gaming-X-v1.0.0.apk`).
3. **Cách xử lý**: Tải và cài `KSU-Ultimate-Gaming-X-v1.0.0.apk` từ GitHub Releases.

### 4. APK báo "Cần quyền Root" hoặc không kết nối được module
1. **Biểu hiện**: Mở APK thấy thẻ báo lỗi không đọc được trạng thái daemon hoặc không cấp quyền root.
2. **Nguyên nhân có thể**: Chưa cấp quyền Superuser (`su`) cho `com.kgx.ultimate` trong KernelSU Manager, hoặc chưa flash Module ZIP vào KernelSU.
3. **Cách kiểm tra**: Kiểm tra trong `KernelSU Manager → Siêu người dùng` xem app `KSU Gaming X` đã bật chưa; kiểm tra tồn tại thư mục `/data/adb/modules/ksu_ultimate_gaming_x`.
4. **Cách xử lý**: Bật quyền Superuser cho `KSU Gaming X`, bấm **Thử kết nối lại** trong app.

### 5. Dashboard không hiển thị thông số hoặc FPS luôn là `N/A`
1. **Biểu hiện**: Mở game nhưng ô FPS hiện `N/A` hoặc số liệu không nhảy.
2. **Nguyên nhân**: Daemon chưa chạy, đang ở ngoài màn hình chính (không có layer SurfaceFlinger của game đang render), hoặc máy đang bật màn hình phụ/tắt màn hình chính không đồng bộ layer.
3. **Cách kiểm tra**: Chạy `kgxctl daemon status` và `kgxctl overlay-tick`.
4. **Cách xử lý**: Bật `AUTO_OPTIMIZE=1`, bật dịch vụ daemon (`kgxctl daemon start`), hoặc thử chạy game ở màn hình chính (`Display #0`).

### 6. CPU / GPU không có dữ liệu hoặc thiếu thông số GPU
1. **Biểu hiện**: Mục GPU báo `0 MHz` hoặc `unknown`.
2. **Nguyên nhân**: Đường dẫn `/sys/class/devfreq` hoặc `/sys/kernel/gpu` trên kernel/ROM tùy biến của máy khác chuẩn Adreno/Mali/Exynos S22 đã cài sẵn trong `hw_detect.sh`.
3. **Cách kiểm tra**: Chạy `kgxctl hw` và `kgxctl diag`.
4. **Cách xử lý**: Mở Compatibility Report kèm output `kgxctl diag` và đường dẫn `/sys/class/devfreq/*` để maintainer bổ sung hỗ trợ.

### 7. FPS không tăng hoặc game vẫn giới hạn 60 FPS
1. **Biểu hiện**: Đã bật game profile `120 FPS` nhưng game vẫn khóa 60 FPS.
2. **Nguyên nhân có thể**:
   - Game khóa cứng ở tầng engine (`GAME_CAP`, ví dụ *Genshin Impact* khóa 60 FPS trên Android).
   - Màn hình máy hoặc màn hình Samsung DeX chỉ có trần 60/75Hz (`DISPLAY_LIMIT`).
   - Máy đang quá nhiệt (`CRITICAL` giới hạn 60 FPS).
   - Chưa khởi động lại game sau khi đổi cấu hình Spoof/Downscale.
3. **Cách kiểm tra**: Chạy `kgxctl games get <package>` để xem trường `primary_limiter` và `explanation`.
4. **Cách xử lý**: Đóng hẳn game (`Force Stop`) rồi mở lại; nếu đang chạy trong Samsung DeX trên màn 60/75Hz, chuyển ra chơi trên màn chính 120Hz.

### 8. Màn hình bị tụt về 60Hz hoặc kẹt 60Hz sau Soft/Hard Reboot
1. **Biểu hiện**: Thoát game hoặc khởi động lại máy xong màn hình bị kẹt 60Hz.
2. **Nguyên nhân có thể**: Phiên game ngắt đột ngột trước khi restore, hoặc công cụ ngoài (như SamHelper) để `120.1` khiến `DisplayModeDirector` One UI từ chối khóa 120Hz, hoặc đang chạy bản cũ chưa vá lỗi `hw_detect.sh`.
3. **Cách kiểm tra**: Chạy `kgxctl hw` và kiểm tra `settings get system min_refresh_rate` / `peak_refresh_rate`.
4. **Cách xử lý**: Cập nhật lên `v1.0.0`, chạy `kgxctl display recover` (hoặc `kgxctl display restore`).

### 9. Nhiệt độ cao khi chơi game lâu
1. **Biểu hiện**: Máy nóng nhanh, tụt FPS sau 10–15 phút.
2. **Nguyên nhân**: Đang bật đồng thời `THERMAL_UNLOCK=1` + `MAX_CLOCK_LOCK=1` ở nhiệt độ phòng cao.
3. **Cách xử lý**: Tắt `MAX_CLOCK_LOCK`, chuyển sang **`SUSTAINED_SWEET_SPOT=1`** và bật **`BYPASS_CHARGING=1`** (nếu máy hỗ trợ và đang cắm sạc >= 80%), kết hợp tản nhiệt ngoài.

### 10. Chơi game vẫn giật hoặc game văng bất ngờ
1. **Biểu hiện**: Đang chơi tự nhiên đóng app hoặc khựng mạnh.
2. **Nguyên nhân**: Có thể do thiếu RAM vật lý, xung đột với app tinh chỉnh kernel khác (VD Konabess / LSpeed / FDE), hoặc thay đổi `downscale` trong lúc game đang chạy.
3. **Cách kiểm tra**: Đọc `kgxctl logs 40` và kiểm tra có `SIGSEGV`/`SIGILL` trong `logcat -b crash` hay không.
4. **Cách xử lý**: Đóng hẳn game trước khi đổi mức `downscale`; nếu cài module tinh chỉnh hiệu năng khác cùng lúc, hãy tắt module kia để cô lập lỗi.

### 11. Service / Daemon `kgx-core` không tự khởi động
1. **Biểu hiện**: Sau khi bật máy, Companion APK báo daemon dừng (`running=false`).
2. **Nguyên nhân**: `SAFE_MODE=1` đang bật (sau 2 lần khởi động lỗi liên tiếp), hoặc `AUTO_OPTIMIZE=0`.
3. **Cách kiểm tra**: Chạy `kgxctl status` và `kgxctl diag`.
4. **Cách xử lý**: Nếu muốn thoát Safe Mode sau khi đã ổn định, bấm nút **Action** trong KernelSU Manager hoặc chạy `kgxctl safemode off && kgxctl daemon start`.

### 12. Module xung đột với module khác
1. **Biểu hiện**: Spoof bị đè hoặc không hoạt động.
2. **Nguyên nhân**: Máy đang cài đồng thời các module chỉnh props toàn hệ thống khác (như MagiskHide Props Config, module spoof khác).
3. **Cách kiểm tra**: Chạy `kgxctl profiles conflicts`.
4. **Cách xử lý**: Tắt các module spoof trùng lặp để tránh ghi đè `ro.product.*`.

### 13. Lỗi Play Integrity / Ứng dụng báo thiết bị lạ / Ngân hàng
1. **Biểu hiện**: Sau khi bật Spoof, Google Wallet/Play Protect/app Cài đặt hoặc app ngân hàng thấy tên máy spoof hoặc báo lỗi kiểm tra thiết bị.
2. **Nguyên nhân có thể**:
   - Đã cài mới/cập nhật `zygisk/arm64-v8a.so` nhưng chưa khởi động lại (Soft/Cold Reboot) để `zygote64` nạp bản mới; hoặc chưa cài ReZygisk/Zygisk Next.
   - Ứng dụng ngân hàng không nằm trong danh sách Google mặc định nên cần bạn tự thêm vào **Spoof Denylist**.
   - Ngoài ra, **không phải mọi lỗi Play Integrity đều do module** (trạng thái unlock bootloader, ROM custom, hoặc PIF/TrickyStore hết key mới là nguyên nhân gốc phổ biến).
3. **Cách kiểm tra**: Chạy `kgxctl spoof diag` và `logcat -d -s KGX_PIShield | tail -n 20`.
4. **Cách xử lý**: Bật `PLAY_INTEGRITY_SHIELD=1`, `SPOOF_EXCLUDE_SETTINGS=1`, thêm các app cần xem máy thật vào **Spoof Denylist** trên Companion APK. **Lưu ý**: Module không cung cấp tính năng giả mạo hardware attestation keys hay vượt anti-cheat.

### 14. Nhiều app đồng loạt báo dừng (`SIGILL`) ngay sau khi cập nhật nóng thủ công
1. **Biểu hiện**: Các app hệ thống/GMS liên tục popup "đã dừng".
2. **Nguyên nhân**: Tự ý chép đè (`unzip -o`) file `zygisk/arm64-v8a.so` khi `zygote64` đang giữ mmap phiên bản cũ trong RAM.
3. **Cách xử lý**: Luôn cài module ZIP đúng cách qua KernelSU Manager và khởi động lại/Soft-Reboot để nạp `zygote64` sạch.
