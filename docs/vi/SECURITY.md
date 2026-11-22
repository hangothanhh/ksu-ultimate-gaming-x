# Chính sách Bảo mật & Ranh giới An toàn (`SECURITY.md`)

> **Ngôn ngữ**: [English](../../SECURITY.md) | **Tiếng Việt**

## Phiên bản được hỗ trợ

| Phiên bản | Trạng thái | Ghi chú |
|---|---|---|
| `v1.0.0` | Được hỗ trợ | Bản phát hành công khai đầu tiên |

## Các Ranh giới An toàn Tuyệt đối (Non-Negotiable Safety Boundaries)

**KSU Ultimate Gaming X** vận hành với quyền root qua KernelSU và Zygisk. Để bảo vệ an toàn phần cứng, hệ điều hành và tài khoản người dùng, mã nguồn áp dụng các lớp khóa cứng sau:

1. **Không bao giờ sửa danh tính phần cứng hoặc trạng thái bootloader / verified boot**:
   - `spoof_set_prop_safe()` trong `module/lib/spoof.sh` và `isSecuritySensitiveProp()` trong `companion/zygisk-spoof/src/main.cpp` chặn tuyệt đối mọi thao tác chạm vào `ro.serialno`, `ro.boot.*`, `ro.crypto.*`, `ro.debuggable`, `ro.secure`, `ro.adb.secure`, IMEI hoặc địa chỉ MAC.
   - `ro.build.fingerprint` được loại khỏi `system.prop` và tự khôi phục về gốc nếu bị sai lệch.
2. **Không bao giờ ghi vào các node sysfs phần cứng nguy hiểm / bảo vệ silicon**:
   - `kgx_is_protected_sysfs()` trong `module/lib/common.sh` chặn ghi vào ngưỡng ngắt nhiệt phần cứng (`trip_point_*`), node dễ gây `SError` như `gpu_ifpo_control` (`*ifpo*`), node SELinux hoặc giá trị xung vượt dải an toàn.
3. **Không dùng lệnh kill toàn cục gây văng máy hay công cụ vượt anti-cheat/attestation**:
   - Không chạy `am kill-all`, `cmd netpolicy` hoặc can thiệp bộ nhớ/anti-cheat của game.
   - Zygisk Stock-Identity Shield chỉ khôi phục thuộc tính gốc của chính máy đó cho Google Services / Cài đặt / danh sách Denylist của người dùng, không giả mạo hardware attestation keys.
4. **Ẩn dữ liệu nhạy cảm khi xuất chẩn đoán (`kgxctl diag`)**:
   - Tự động thay serial, chuỗi số >= 15 chữ số, địa chỉ MAC, IPv4 riêng, email, token và mật khẩu thành `[REDACTED_*]` trước khi xuất báo cáo.
5. **Cô lập khóa ký APK cục bộ**:
   - `.gitignore` chặn `*.keystore`, `*.jks`, `*.idsig`, `dist/` và `module/system.prop` sinh tự động. Khi ký APK release chính thức, thiết lập biến môi trường `KGX_KEYSTORE_PATH`, `KGX_KEYSTORE_PASS`, `KGX_KEY_PASS`, và `KGX_KEY_ALIAS` thay vì đưa keystore vào Git.

## Báo cáo Lỗ hổng hoặc Hành vi Mất an toàn

- **KHÔNG** đăng log thô chứa serial, token, IP hoặc IMEI lên Issue công khai.
- Chạy `kgxctl diag` để kiểm tra mọi trường nhạy cảm đã đổi thành `[REDACTED_*]` trước khi chia sẻ log.
- Với lỗi công khai không làm lộ payload khai thác nhạy cảm, mở Issue tại: https://github.com/hangothanhh/ksu-ultimate-gaming-x/issues
- Với phát hiện bảo mật nghiêm trọng liên quan quyền root/crash mà việc công khai sớm có thể gây rủi ro cho người dùng, liên hệ riêng với maintainer `hangothanhh` hoặc chỉ tóm tắt bước tái hiện tối thiểu không kèm mã khai thác cho tới khi có bản vá.
