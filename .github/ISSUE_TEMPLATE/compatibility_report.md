---
name: Báo cáo tương thích thiết bị (Compatibility Report)
about: Chia sẻ kết quả kiểm thử thực tế trên thiết bị của bạn (giúp cập nhật bảng tương thích trung thực)
title: "[Compat] "
labels: compatibility
assignees: ''
---

## 1. Thông tin máy kiểm thử
- **Hãng / Model / Codename**:
- **SoC / GPU**:
- **Android / ROM**:
- **Kernel version (`uname -r`)**:
- **KernelSU + Zygisk provider**:
- **Phiên bản KSU Ultimate Gaming X**: `v1.0.0`

## 2. Trạng thái từng tính năng (Chỉ chọn mục bạn ĐÃ TỰ TEST)
| Tính năng | Trạng thái (`VERIFIED` / `PARTIAL` / `BROKEN`) | Ghi chú |
|---|---|---|
| Cài đặt Module ZIP & khởi động | | |
| Companion APK kết nối root | | |
| `kgx-core` daemon & Scene FPS Overlay | | |
| Device Spoof toàn hệ thống | | |
| Zygisk Stock-Identity Shield & Denylist | | |
| Giữ / khôi phục 120Hz (hoặc max Hz) | | |
| Thermal Guard / Sweet-Spot / Bypass Charging | | |
| External Display Screen-Off / Resolution Override | | |

## 3. Output kiểm tra (`kgxctl diag`)
```text
(Chạy `su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl diag"` và dán kết quả vào đây)
```
