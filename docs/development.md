# Hướng dẫn Build từ Mã nguồn (Build from Source)

## 1. Mục đích
Tài liệu dành cho lập trình viên muốn tự biên dịch Module KernelSU ZIP, nhị phân Rust ARM64 (`kgx-core`, `libkgx_rust.so`), thư viện Zygisk C++ (`arm64-v8a.so`), và Companion Android APK (`KSU-Ultimate-Gaming-X-v1.0.0.apk`) trực tiếp từ mã nguồn.

---

## 2. Yêu cầu môi trường thực tế
Dựa theo [scripts/build_rust.py](../scripts/build_rust.py), [scripts/build_apk.py](../scripts/build_apk.py), [scripts/build_zip.py](../scripts/build_zip.py) và [tests/verify_all.py](../tests/verify_all.py):

| Thành phần | Yêu cầu đã kiểm chứng | Ghi chú |
|---|---|---|
| **Hệ điều hành** | Windows 10/11 *(full build + 7 stages)*; Linux (`ubuntu-latest`) *(build ZIP + Stages 1–6 CI)* | Scripts `build_rust.py` / `build_apk.py` mặc định đường dẫn Windows (hỗ trợ env override một phần SDK/Java) |
| **Python** | Python 3.12+ | Không cần package pip ngoài (chỉ dùng thư viện chuẩn Python) |
| **Rust toolchain** | `rustc` với target `aarch64-linux-android` | Zero external crates (thuần `std`) |
| **Android NDK** | NDK `29.0.14206865` (`aarch64-linux-android29-clang`, `clang++`, `llvm-strip`) | Link C++ Zygisk với `-static-libstdc++ -llog -ldl` |
| **Android SDK** | Platform `android-34` (`android.jar`) & Build-Tools `34.0.0` (`aapt2`, `d8`, `zipalign`, `apksigner`) | Hỗ trợ biến môi trường `ANDROID_SDK_ROOT` / `ANDROID_HOME` |
| **Java JDK** | OpenJDK 17 (`javac`, `keytool`) | Compile target Java 8 |
| **POSIX shell (để chạy test)** | Git for Windows `sh.exe` (hoặc `/bin/sh` + `awk` + `tar` trên Linux) | Không cần Gradle hay CMake để đóng gói APK |
| **Dung lượng trống** | ~2 GB (tính cả Android SDK + NDK + Rust target) | Phần mã nguồn & artifact repo chỉ < 5 MB |

---

## 3. Các bước Build & Kiểm thử

### Bước 1: Clone mã nguồn
```sh
git clone https://github.com/hangothanhh/ksu-ultimate-gaming-x.git
cd ksu-ultimate-gaming-x
```
*(Dự án không sử dụng Git submodule.)*

### Bước 2: Build nhị phân Rust & Zygisk (Windows với NDK + Rust đã cài)
```powershell
python -u scripts/build_rust.py
```
Lệnh này biên dịch lần lượt:
1. `companion/rust-core/src/main.rs` → `module/bin/kgx-core` (AArch64 ELF)
2. `companion/zygisk-spoof/src/main.cpp` → `module/zygisk/arm64-v8a.so` (Zygisk API v4 SO, không phụ thuộc `libc++_shared.so`)
3. `companion/android-app/rust-jni/src/lib.rs` → `companion/android-app/jniLibs/arm64-v8a/libkgx_rust.so`

### Bước 3: Build Display Helper DEX & Companion APK
*(Tùy chọn ký bằng keystore riêng qua biến môi trường; nếu bỏ trống sẽ tạo debug keystore cục bộ tại `companion/android-app/kgx.keystore` — đã bị `.gitignore` bỏ qua, không commit lên Git):*
```powershell
# Tùy chọn nếu dùng keystore riêng của bạn:
# $env:KGX_KEYSTORE_PATH = "C:\path\to\your-release.keystore"
# $env:KGX_KEYSTORE_PASS = "..."
# $env:KGX_KEY_PASS = "..."
# $env:KGX_KEY_ALIAS = "..."

python -u scripts/build_apk.py
```
Kết quả:
- `module/data/kgx-display.dex`
- `dist/KSU-Ultimate-Gaming-X-v1.0.0.apk` + `.sha256`

### Bước 4: Đóng gói KernelSU Module ZIP (Windows hoặc Linux)
```sh
python3 -u scripts/build_zip.py
```
Kết quả:
- `dist/KSU-Ultimate-Gaming-X-v1.0.0.zip` + `.sha256`
- Tự chuẩn hóa ký tự xuống dòng LF (`\n`), xóa UTF-8 BOM, gán quyền UNIX `0755` cho script/binary và `0644` cho file dữ liệu/SO, cấm tuyệt đối `module/system.prop` hay `module/webroot`.

### Bước 5: Chạy bộ kiểm thử toàn diện
- **Chạy đủ cả 7 stage (cần có cả APK trong `dist/`)**:
  ```powershell
  python -u tests/verify_all.py
  ```
- **Chạy Stages 1–6 (trên Linux CI hoặc khi chỉ test Module ZIP)**:
  ```sh
  python3 -u tests/verify_all.py --skip-apk
  ```

### Bước 6: Kiểm tra kết quả & SHA-256
- **Windows (PowerShell)**:
  ```powershell
  Get-FileHash dist\KSU-Ultimate-Gaming-X-v1.0.0.zip, dist\KSU-Ultimate-Gaming-X-v1.0.0.apk -Algorithm SHA256
  ```
- **Linux**:
  ```sh
  sha256sum dist/KSU-Ultimate-Gaming-X-v1.0.0.zip dist/KSU-Ultimate-Gaming-X-v1.0.0.apk
  ```

---

## 4. Lưu ý cho người muốn sửa `build_rust.py` / `build_apk.py` trên Linux
Hiện tại các hằng số đường dẫn NDK/SDK/JDK mặc định trong `build_rust.py` (`.cmd` / `.exe`) và `build_apk.py` (`build-tools/34.0.0/*.bat`) được viết cho môi trường Windows host của maintainer. Nếu bạn muốn cross-compile Rust/APK trên Linux, cần điều chỉnh tên binary toolchain bỏ đuôi `.cmd`/`.bat`/`.exe` hoặc dùng trực tiếp GitHub Actions chỉ đóng gói ZIP & kiểm thử POSIX (`--skip-apk`).
