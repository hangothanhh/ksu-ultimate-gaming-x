# Ghi nhận Đóng góp AI (`AI_CONTRIBUTIONS.md`)

> **Ngôn ngữ**: [English](../../AI_CONTRIBUTIONS.md) | **Tiếng Việt**

Tài liệu này ghi nhận minh bạch sự đóng góp của công cụ AI (**Google Antigravity**) trong dự án **KSU Ultimate Gaming X**, phân tách rõ vai trò của maintainer, phạm vi hỗ trợ kỹ thuật, mức độ kiểm chứng và ranh giới pháp lý.

---

## 1. Maintainer & AI Coding Assistant

- **Maintainer & Chủ sở hữu dự án (`Copyright Holder`)**: **`hangothanhh`**
  - Định hướng tính năng, cung cấp log thực tế trên máy, rà soát thay đổi, trực tiếp kiểm chứng trên thiết bị thật và quản lý phát hành (`v1.0.0`).
- **Công cụ AI hỗ trợ phát triển (`AI Coding Assistant`)**: **Google Antigravity**
  - Tham gia hỗ trợ kiến trúc, viết và tái cấu trúc mã nguồn, xây dựng bộ kiểm thử giả lập, tài liệu hướng dẫn người mới và cấu hình CI theo chỉ đạo của maintainer.

---

## 2. Phạm vi Đóng góp Kỹ thuật của Google Antigravity

- **KernelSU Module Engine (`module/`)**: Xây dựng và sửa lỗi các script POSIX `sh` (`post-fs-data.sh`, `service.sh`, `customize.sh`, `uninstall.sh`, `action.sh`, `bin/kgxctl`, `lib/*.sh`), bao gồm bảo vệ chống bootloop, sửa lỗi `PlatformCompat killUid`, node bảo vệ Exynos `gpu_ifpo_control`, cô lập tần số quét LTPO 120Hz màn hình chính, xử lý giá trị `120.1` của SamHelper, Spoof Denylist và xuất báo cáo `kgxctl diag` tự động che PII.
- **Native Rust Core & JNI (`companion/rust-core/`, `companion/android-app/rust-jni/`)**: Viết daemon `kgx-core` (đọc sysfs/SurfaceFlinger FPS, điều phối thermal/bypass/freezer, xử lý tín hiệu hoàn nguyên khi tắt) và cầu nối JNI cho Android App.
- **Zygisk Stock-Identity & Denylist Shield (`companion/zygisk-spoof/src/main.cpp`)**: Xây dựng và sửa bộ lọc `.so` cho `pltHookRegister`, logic hoàn nguyên property gốc cho GMS/Settings/Denylist.
- **Standalone Companion APK (`companion/android-app/java/`)**: Xây dựng giao diện Material 3 không dùng Gradle (`MainActivity`, Overlay Service, Session Recorder, Quick Settings Tiles).
- **Kiểm thử tự động & CI (`tests/verify_all.py`, `.github/workflows/ci.yml`)**: Xây dựng bộ kiểm thử POSIX/mock 7 stage và workflow GitHub Actions.
- **Tài liệu dự án**: Biên soạn [README.md](../../README.vi.md), [CHANGELOG.md](CHANGELOG.md), [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md) và bộ hướng dẫn chi tiết trong `docs/`.

---

## 3. Phạm vi Kiểm chứng Thực tế & Cảnh báo "AI Slop"

- **`VERIFIED` (đã kiểm chứng trên phần cứng thật bởi maintainer `hangothanhh`)**:
  - Samsung Galaxy S22 Exynos (`SM-S901B` / `r0s`), Android 12 / One UI 4.1, KernelSU temproot + ReZygisk.
- **`PARTIAL` (chỉ kiểm thử giả lập POSIX/mock trong `tests/verify_all.py`)**:
  - Cấu hình Qualcomm Adreno và MediaTek Mali hiện chưa được xác minh trên thiết bị thật.
- **Lưu ý rủi ro**: Mã nguồn và tài liệu có sự hỗ trợ của AI có thể còn lỗi góc khuất trên thiết bị/ROM chưa kiểm thử. Người dùng và cộng đồng không nên coi danh sách profile mẫu là cam kết tương thích phần cứng.

---

## 4. Ranh giới Pháp lý & Quy tắc Git Attribution

1. Việc ghi nhận đóng góp của **Google Antigravity** chỉ thực hiện trong hệ thống tài liệu của repository (`AI_CONTRIBUTIONS.md`, `README.md`, `NOTICE`) — **không** gắn trailer `Co-authored-by:` vào Git commit để giữ lịch sử Git và mục Contributors gắn với tài khoản maintainer thật `hangothanhh`.
2. Ghi nhận AI **không** làm thay đổi quyền sở hữu bản quyền (`Copyright (C) 2026 hangothanhh`), không thay thế nghĩa vụ của giấy phép **GNU GPL v3.0 hoặc mới hơn (`GPL-3.0-or-later`)**, và giữ nguyên ghi công bên thứ ba trong [NOTICE](../../NOTICE).
3. Sự xuất hiện tên Google Antigravity trong tài liệu mô tả đúng công cụ hỗ trợ đã sử dụng, **không** hàm ý Google bảo trợ, chứng thực hay chịu trách nhiệm pháp lý đối với dự án.
