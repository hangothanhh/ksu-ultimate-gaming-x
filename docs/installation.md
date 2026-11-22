# Hướng dẫn Cài đặt Chi tiết (A → Z cho người mới)

## 1. Mục đích
Tài liệu này giúp bạn cài đặt đúng, kiểm tra tính toàn vẹn file (SHA-256) và xác minh **KSU Ultimate Gaming X (`v1.0.0`)** hoạt động an toàn trên máy Android đã có KernelSU — ngay cả khi bạn mới làm quen với Android Root.

---

## 2. Giải thích nhanh các khái niệm
- **KernelSU (KSU)**: Hệ thống cấp quyền quản trị (`root`) hoạt động ở tầng nhân Linux (`kernel`), cho phép nạp các *module* bổ sung tính năng hoặc sửa thông số hệ thống mà không ghi đè vĩnh viễn phân vùng `/system`.
- **Module ZIP (`KSU-Ultimate-Gaming-X-v1.0.0.zip`)**: Phần lõi cài vào **KernelSU Manager**, chứa shell scripts điều khiển phần cứng, Rust daemon `kgx-core` và thư viện Zygisk.
- **Companion APK (`KSU-Ultimate-Gaming-X-v1.0.0.apk`)**: Ứng dụng Android giao diện Material 3 để bạn bật/tắt tính năng, xem FPS/nhiệt độ trực tiếp, chọn danh sách ứng dụng **không spoof** (`Spoof Denylist`). **Lưu ý**: File APK **không** thay thế được Module ZIP — bạn phải cài Module ZIP trước.
- **Zygisk / ReZygisk**: Cơ chế tiêm mô-đun vào tiến trình ứng dụng khi khởi chạy (`zygote64`). Dự án dùng nó cho tính năng **Stock-Identity Shield** (giữ danh tính máy gốc cho Google Play Services, Cài đặt và các app trong Denylist).

---

## 3. Bạn cần chuẩn bị gì?
1. Máy Android kiến trúc **ARM64 (`arm64-v8a`)**, **Android 8.0+ (API >= 26)**. Để dùng đầy đủ `cmd game` / giảm độ phân giải game cần **Android 12+ (API >= 31)**.
2. Đã cài và kích hoạt **KernelSU** (hoặc **KernelSU Next / APatch** tương thích).
3. Nếu muốn dùng tính năng *Stock-Identity Shield / Spoof Denylist*, cài module Zygisk (khuyến nghị **ReZygisk** hoặc **Zygisk Next**).
4. **Sao lưu dữ liệu quan trọng** (ảnh, tài liệu, ứng dụng ngân hàng/xác thực 2 bước) ra máy tính hoặc đám mây trước khi cài bất kỳ module root nào.
5. Đọc phần [Cảnh báo rủi ro](../README.md#read-before-installing--cảnh-báo) và [Hướng dẫn khôi phục](../README.md#54-recovery--cứu-hộ-khi-gặp-lỗi).

---

## 4. Các bước tải và kiểm tra SHA-256

### Bước 1: Tải đúng file từ GitHub Releases
1. Truy cập: https://github.com/hangothanhh/ksu-ultimate-gaming-x/releases/tag/v1.0.0
2. Tải **2 file**:
   - `KSU-Ultimate-Gaming-X-v1.0.0.zip` *(Module KernelSU)*
   - `KSU-Ultimate-Gaming-X-v1.0.0.apk` *(Ứng dụng điều khiển)*
3. **Tuyệt đối không** bấm *Download ZIP / Source code (zip)* trên trang chủ repo rồi đem đi flash trong KernelSU — gói đó chỉ là mã nguồn, **không phải** module cài đặt.

### Bước 2: Kiểm tra mã băm SHA-256 (Verify Download)
Mục đích là chắc chắn file tải về không bị hỏng mạng hoặc bị chỉnh sửa. Giá trị chuẩn của từng bản được công bố ngay trong tệp `*.sha256` đi kèm trên trang Releases.

- **Trên Windows (PowerShell / CMD):**
  ```cmd
  certutil -hashfile KSU-Ultimate-Gaming-X-v1.0.0.zip SHA256
  certutil -hashfile KSU-Ultimate-Gaming-X-v1.0.0.apk SHA256
  ```
- **Trên Linux / Termux (Android):**
  ```sh
  sha256sum KSU-Ultimate-Gaming-X-v1.0.0.zip
  sha256sum KSU-Ultimate-Gaming-X-v1.0.0.apk
  ```
- **Trên macOS:**
  ```sh
  shasum -a 256 KSU-Ultimate-Gaming-X-v1.0.0.zip
  shasum -a 256 KSU-Ultimate-Gaming-X-v1.0.0.apk
  ```

**Nhận biết toàn vẹn**: Chuỗi 64 ký tự hex in ra phải khớp từng ký tự (không phân biệt hoa/thường) với file `.sha256` tương ứng trên GitHub Releases. Nếu khác dù chỉ 1 ký tự → xóa file và tải lại.

---

## 5. Cài đặt Module ZIP vào KernelSU
1. Chép `KSU-Ultimate-Gaming-X-v1.0.0.zip` vào bộ nhớ máy (VD thư mục `Download`).
2. Mở ứng dụng **KernelSU Manager**.
3. Đảm bảo trạng thái trên màn hình chính của KernelSU báo **Đang hoạt động / Working** (trên máy dùng temproot như Samsung S22 cần đảm bảo đã nạp temproot thành công).
4. Chuyển sang tab **Mô-đun (Modules)** → bấm nút **Cài đặt (Install)** *(vị trí nút tùy phiên bản KernelSU Manager, thường ở góc dưới phải hoặc thanh công cụ)*.
5. Chọn file `KSU-Ultimate-Gaming-X-v1.0.0.zip` → xác nhận **Cài đặt**.
6. Theo dõi màn hình log cài đặt (`customize.sh`):
   - Thông báo thành công sẽ có dòng: `- Installation complete! Open KSU Gaming X App to configure.`
   - Thông báo lỗi thường gặp: `! Unsupported architecture` (máy không phải ARM64) hoặc `! Android API ... is too old` (Android dưới 8.0).
7. Khởi động lại máy (hoặc **Soft-Reboot** nếu bạn đang dùng **KernelSU temproot** để tránh mất root khi cold reboot — kiểm tra hướng dẫn temproot của riêng máy bạn trước).

---

## 6. Cài đặt Companion APK & Khởi chạy lần đầu
> Lưu ý: **Không** cấp quyền root trực tiếp cho app khác nếu chưa hiểu rõ. Riêng Companion APK **Gaming X** cần quyền root (`su`) từ KernelSU để giao tiếp với CLI `kgxctl` và `kgx-core`.

1. Cài đặt file `KSU-Ultimate-Gaming-X-v1.0.0.apk` như app Android thông thường (cần bật *Cho phép cài đặt từ nguồn này* nếu hệ thống hỏi).
2. Mở **KernelSU Manager → Siêu người dùng (Superuser)**, tìm **KSU Gaming X** (`com.kgx.ultimate`) và gạt bật cấp quyền root (hoặc mở app rồi bấm **Cho phép** khi hộp thoại Superuser hiện ra).
3. Mở **KSU Gaming X** và kiểm tra các mục sau ngay lần đầu:
   - **Thẻ Trạng thái & Daemon**: `kgx-core` phải báo đang chạy (`running`).
   - **Thẻ Phần cứng**: Nhận đúng SoC, GPU và `DISPLAY_MAX_HZ` (VD `120 Hz` trên Galaxy S22, không bị sai thành `60 Hz`).
   - **Device Spoof**: Theo cấu hình mặc định trong `module/data/default_global.conf`, `SPOOF_ENABLED=1`, `PLAY_INTEGRITY_SHIELD=1` và `SPOOF_EXCLUDE_SETTINGS=1`. Nếu chưa muốn spoof, bạn có thể tắt công tắc ngay trên app.
   - **Thermal & Game**: Chế độ mặc định là `THERMAL_GUARD_ENABLED=1`, `THERMAL_UNLOCK=0`, `SUSTAINED_SWEET_SPOT=0`.

---

## 7. Cách kiểm tra thực tế (không chỉ nhìn công tắc UI)
Nếu muốn xác minh độc lập bằng dòng lệnh (`adb shell su -c ...` hoặc Termux root):
```sh
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl status"
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl diag"
```
Kiểm tra:
- `"daemon":{"running":true,...}` → daemon đã chạy.
- `"display":{"current_hz":120,"max_hz":120,...}` → nhận đúng tần số màn hình gốc.
- `"safe_mode":false` → không bị kẹt chế độ an toàn.

---

## 8. Cảnh báo & Lỗi thường gặp khi cài đặt
- **Không thấy module sau khi flash**: Kiểm tra xem bạn có đang dùng máy **temproot** mà lại bấm *Khởi động lại bình thường (Cold Reboot)* làm mất KernelSU không.
- **App báo "Chưa cài Module KernelSU"**: Bạn đã cài APK trước khi flash Module ZIP, hoặc chưa cấp quyền Superuser cho `com.kgx.ultimate` trong KernelSU Manager.
- **Muốn khôi phục ngay tức thì**: Bấm nút **Action** của module trong KernelSU Manager (chạy `module/action.sh` thực hiện `kgxctl rollback`), hoặc xem [Hướng dẫn khắc phục sự cố](troubleshooting.md).
