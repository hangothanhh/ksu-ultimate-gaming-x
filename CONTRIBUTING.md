# Hướng dẫn Đóng góp (Contributing Guide)

Cảm ơn bạn đã quan tâm đóng góp cho **KSU Ultimate Gaming X**! Vui lòng đọc kỹ hướng dẫn và quy chuẩn dưới đây trước khi mở Issue hoặc Pull Request.

---

## 1. Minh bạch về AI & Chính sách chống "AI Slop" (BẮT BUỘC ĐỌC)

> [!WARNING]
> **Cảnh báo về AI Slop (mã nguồn / tài liệu kém chất lượng sinh tự động bởi AI):**
> Dự án này có sự hỗ trợ từ AI trong quá trình phát triển và tài liệu hóa, và tác giả đã kiểm thử thực tế trên thiết bị Samsung Galaxy S22 Exynos + bộ test giả lập. Tuy nhiên, **chúng tôi từ chối mọi Pull Request kiểu "AI slop"** — tức là code hoặc tài liệu do AI viết hàng loạt nhưng người gửi không đọc lại, không hiểu tác động, không chạy test hoặc tự bịa kết quả tương thích.

Khi gửi PR có dùng AI hỗ trợ:
1. **Phải khai báo trung thực** trong mẫu Pull Request (phần *Minh bạch về AI*).
2. **Phải tự đọc và hiểu từng dòng diff** trước khi gửi.
3. **Không bịa đặt kết quả kiểm thử hoặc danh sách máy hỗ trợ**: Nếu mới chỉ chạy test mock trên máy tính, phải ghi rõ `PARTIAL (Mock only)` — không được ghi `VERIFIED`.
4. **Không thêm tweak sysfs/prop "truyền miệng"** (những thông số không rõ tác dụng hoặc có thể gây kernel panic như `gpu_ifpo_control` / `trip_point_*`).

---

## 2. Quy trình Fork, Sửa code & Tạo Pull Request

### Bước 1: Fork & Clone mã nguồn
1. Bấm nút **Fork** trên https://github.com/hangothanhh/ksu-ultimate-gaming-x.
2. Clone bản fork về máy:
```sh
git clone https://github.com/<ten-tai-khoan-cua-ban>/ksu-ultimate-gaming-x.git
cd ksu-ultimate-gaming-x
```
3. Kiểm tra nhánh đang làm việc:
```sh
git checkout -b fix/mo-ta-ngan-gon
```

### Bước 2: Cài công cụ & Build thử
Xem chi tiết môi trường build tại [docs/development.md](docs/development.md). Tóm tắt:
- Build nhanh Module ZIP & chạy bộ test không cần Android SDK (Stages 1–6):
  ```sh
  python3 -u scripts/build_zip.py
  python3 -u tests/verify_all.py --skip-apk
  ```
- Build đầy đủ (Rust `kgx-core` + Zygisk `arm64-v8a.so` + Companion APK + ZIP + toàn bộ 7 stage test trên Windows/Android SDK+NDK):
  ```powershell
  python -u scripts/build_rust.py
  python -u scripts/build_apk.py
  python -u scripts/build_zip.py
  python -u tests/verify_all.py
  ```

### Bước 3: Quy chuẩn code & POSIX
- Toàn bộ script trong `module/` **phải dùng POSIX `sh` thuần** (sẽ bị Stage 1 & Stage 2 của `tests/verify_all.py` từ chối nếu có `[[`, `function`, `declare`, `source`, CRLF, BOM, `cmd netpolicy` hoặc đọc `/proc/*/cmdline` trực tiếp vào `tr`).
- Dùng ký tự xuống dòng **LF** (`\n`) đúng theo `.editorconfig`.
- Không sửa trực tiếp các file nhị phân được tạo ra nếu chưa build lại từ source tương ứng (`companion/rust-core/`, `companion/zygisk-spoof/`, `companion/android-app/`).

### Bước 4: Quy ước Commit (Conventional Commits)
Sử dụng tiền tố rõ ràng:
- `feat: add new gaming profile` — thêm tính năng / profile mới
- `fix: correct thermal monitoring` — sửa lỗi
- `docs: improve installation guide` — cập nhật tài liệu
- `refactor: simplify service manager` — tối ưu cấu trúc code
- `perf: reduce dashboard polling` — cải thiện hiệu năng
- `test: add module validation` — bổ sung kiểm thử
- `chore: update build dependencies` — việc bảo trì, CI, `.gitignore`

---

## 3. Các quy định an toàn bắt buộc

PR sẽ bị từ chối ngay nếu vi phạm một trong các mục sau:
- Không đồng ý phát hành phần đóng góp dưới giấy phép của dự án (**GNU GPL v3.0 hoặc mới hơn — `GPL-3.0-or-later`**).
- Chứa private key, file `*.keystore`, `*.jks`, API token, GitHub credentials, hoặc log cá nhân chưa ẩn IMEI/serial/MAC/email.
- Thêm dependency không rõ nguồn gốc (hoặc không tương thích GPLv3+) hay thư viện nhị phân đóng (closed-source) không kèm nguồn/giấy phép.
- Sửa đổi hoặc vô hiệu hóa kiểm tra chống ghi `ro.serialno`, `ro.boot.*`, `trip_point_*`, `*ifpo*`.
- Bổ sung mã bypass anti-cheat của game hoặc giả mạo hardware attestation keys.
- Không giữ nguyên copyright notice trong [companion/zygisk-spoof/include/zygisk.hpp](companion/zygisk-spoof/include/zygisk.hpp).
