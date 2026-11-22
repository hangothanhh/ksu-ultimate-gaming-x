---
name: Báo lỗi (Bug Report)
about: Báo lỗi module KernelSU, app điều khiển, tần số quét 120Hz, crash hoặc lỗi build
title: "[Bug] "
labels: bug
assignees: ''
---

## 1. Mô tả lỗi
Mô tả ngắn gọn chuyện gì đã xảy ra và kết quả bạn mong đợi là gì.

## 2. Thông tin thiết bị (Bắt buộc)
- **Mẫu máy (Model)**: (VD: Galaxy S22 SM-S901B)
- **Phiên bản Android / ROM**: (VD: Android 12 / One UI 4.1)
- **Phiên bản KernelSU & Zygisk**: (VD: KernelSU ..., ReZygisk ...)
- **Phiên bản KSU Ultimate Gaming X**: `v1.0.0`
- **APK hay Module**: (Module ZIP / Companion APK / Cả hai)

## 3. Các bước tái hiện lỗi
1. ...
2. ...
3. ...

## 4. Báo cáo chẩn đoán đã ẩn thông tin nhạy cảm (`kgxctl diag`)
> **QUAN TRỌNG**: Chạy lệnh sau trong terminal có root (hoặc ADB shell) rồi dán kết quả vào đây. Không dán serial, IMEI, địa chỉ MAC hoặc token cá nhân.
```sh
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl diag"
```

```text
(Dán output của kgxctl diag vào đây)
```

## 5. Ảnh chụp màn hình / Log bổ sung (nếu có)
- Đính kèm ảnh (nhớ che thông tin cá nhân nếu có).
