# KSU Ultimate Gaming X (`v1.0.0`)

> **Ngôn ngữ**: [English](README.md) | **Tiếng Việt**

Bộ tối ưu hiệu năng chơi game, điều phối xung nhiệt, bảo vệ tần số quét màn hình và spoof danh tính thiết bị toàn hệ thống cho **KernelSU** — vận hành bởi **Daemon Rust Native (`kgx-core`)**, **Lá chắn Zygisk Stock-Identity Shield (`arm64-v8a.so`)** và **Ứng dụng điều khiển Material 3 độc lập (`KSU-Ultimate-Gaming-X-v1.0.0.apk`)**.

- **Phiên bản hiện tại**: `v1.0.0` (`versionCode: 100`)
- **Trạng thái phát triển**: Phát hành công khai đầu tiên (`VERIFIED` trên Samsung Galaxy S22 Exynos; `PARTIAL` dạng mock cho Adreno/Mali)
- **Nền tảng**: Android ARM64 (`arm64-v8a`, Android 8.0+ / API >= 26, tối ưu đầy đủ cho Android 12+ / API >= 31)
- **Công nghệ**: POSIX Shell (`module/`), Native Rust ARM64 (`companion/rust-core`, không crate ngoài), C++17 Zygisk API v4 (`companion/zygisk-spoof`), Android SDK Java + Rust JNI (`companion/android-app`)
- **Liên kết chính thức**: [GitHub Releases](https://github.com/hangothanhh/ksu-ultimate-gaming-x/releases) · [Báo lỗi (Issues)](https://github.com/hangothanhh/ksu-ultimate-gaming-x/issues) · [Giấy phép (GNU GPLv3+)](LICENSE) · [CHANGELOG](docs/vi/CHANGELOG.md)

> [!WARNING]
> **Minh bạch về AI & Cảnh báo "AI Slop":**
> Dự án này được phát triển và biên soạn tài liệu với **sự hỗ trợ của Google Antigravity (AI coding assistant)**, sau đó được kiểm tra thực tế trên Samsung Galaxy S22 Exynos (Android 12 / One UI 4.1) và qua bộ kiểm thử giả lập POSIX 7 stage ([tests/verify_all.py](tests/verify_all.py)).
> - **Cảnh báo AI Slop**: Mã nguồn hoặc cấu hình do AI tạo ra vẫn có thể tồn tại lỗi góc khuất trên những thiết bị/ROM mà tác giả **chưa tự tay kiểm thử**. Không coi tên một thiết bị xuất hiện trong cơ sở dữ liệu là cam kết tương thích.
> - Chỉ những hạng mục ghi **`VERIFIED`** mới đã chạy thực tế trên phần cứng thật; mọi đóng góp PR chứa code AI chưa kiểm thử sẽ bị từ chối theo [CONTRIBUTING.md](docs/vi/CONTRIBUTING.md).

---

## Mục lục nhanh
1. [Dự án này làm được gì? (What This Project Does)](#what-this-project-does)
2. [Đọc trước khi cài — CẢNH BÁO RỦI RO](#read-before-installing--cảnh-báo)
3. [Bảng tương thích thực tế (Compatibility)](#compatibility)
4. [Yêu cầu trước khi cài (Requirements)](#requirements)
5. [Hướng dẫn cài đặt cho người mới (A → Z)](#installation-guide)
6. [Cập nhật, Rollback, Gỡ cài đặt & Cứu hộ (Recovery)](#update-rollback-uninstall--recovery)
7. [Xử lý sự cố & Báo cáo lỗi an toàn (`kgxctl diag`)](#troubleshooting--diagnostic-report)
8. [Cấu trúc mã nguồn & Build từ Source](#repository-structure--build-from-source)
9. [Đóng góp, Giấy phép & Nguồn bên thứ ba](#contributing-license--credits)

---

<a id="what-this-project-does"></a>
## 1. Dự án này làm được gì? (What This Project Does)

*Giải thích thuật ngữ nhanh cho người mới:* **KernelSU** là công cụ cấp quyền quản trị (`root`) chạy từ nhân hệ điều hành Linux của điện thoại, cho phép nạp *module* chạy ngầm mà không sửa cứng phân vùng hệ thống.

| Thành phần | Chức năng & Cách hoạt động | Tình trạng | Giới hạn / Cách bật tắt | Tài liệu chi tiết |
|---|---|---|---|---|
| **Gaming Performance Engine & Rust Daemon (`kgx-core`)** | Tự phát hiện game đang mở, áp chế độ CPU/GPU, pin luồng render vào `top-app`, tối ưu RAM/I/O, hoàn nguyên khi thoát game hoặc `SIGHUP`/`SIGTERM` | `VERIFIED` *(S22)* / `PARTIAL` *(Adreno/Mali mock)* | Không đụng `am kill-all` hay `cmd netpolicy`; bật/tắt qua `AUTO_OPTIMIZE` (app hoặc `kgxctl`) | [docs/gaming-engine.md](docs/vi/gaming-engine.md) |
| **FPS Compatibility Engine (5 yếu tố)** | Tính FPS khả thi dựa trên $\min(\text{Yêu cầu}, \text{Game Cap}, \text{Display Hz}, \text{Thermal Cap})$; pre-apply `cmd game` / `downscale` khi game **không chạy** để tránh crash `PlatformCompat killUid` | `VERIFIED` *(S22 Android 12)* | Không vượt được giới hạn cứng từ engine game (VD Genshin 60 FPS Android); bật/tắt qua `FPS_ENGINE_ENABLED` | [docs/fps-compatibility.md](docs/vi/fps-compatibility.md) |
| **LTPO 120Hz Refresh Rate Manager** | Cô lập thông số màn chính (`INTERNAL`) khỏi màn ngoài HDMI/DeX (50/70/75Hz), chống tụt/hạ cấp `hw_profile.env`, chuẩn hóa `120.1 -> 120.0`, tự phục hồi sau crash/Soft-Reboot | `VERIFIED` *(S22 LTPO)* | Chế độ mặc định qua `DISPLAY_AUTO_HZ`; trên Samsung DeX vẫn theo trần Hz của `Display #2` | [docs/fps-compatibility.md](docs/vi/fps-compatibility.md) |
| **Device Profile Database & Whole-System Spoof** | Bộ **34 profile thiết bị** (`devices.tsv`) & **31 game** (`games.tsv`); chấm điểm khớp GPU (`matcher.sh`), áp qua `resetprop` + `system.prop` | `VERIFIED` *(S22)* | Profile chỉ là gợi ý khớp GPU, **không đảm bảo** máy chơi mượt hay game nào cũng mở 120 FPS; bật/tắt qua `SPOOF_ENABLED` | [docs/device-database.md](docs/vi/device-database.md) |
| **Zygisk Stock-Identity Shield & Spoof Denylist** | Thư viện `zygisk/arm64-v8a.so` (Zygisk API v4) trả thông số máy gốc cho GMS/Play Store/Wallet (`PLAY_INTEGRITY_SHIELD`), app Cài đặt (`SPOOF_EXCLUDE_SETTINGS`) và app bạn chọn trong `spoof_denylist.list` | `VERIFIED` *(S22 + ReZygisk)* | Cần có ReZygisk/Zygisk Next và khởi động lại/Soft-Reboot sau khi cập nhật `.so`; không hứa hẹn vượt Play Integrity | [docs/device-database.md](docs/vi/device-database.md) |
| **CPU / GPU / Power Telemetry & Scene FPS Overlay** | Đọc trực tiếp xung/tải CPU/GPU, công suất pin (`mW`/`mA`), SurfaceFlinger FPS + 1% Low qua `kgx-core`; hiển thị thẻ nổi Scene mini & ghi biểu đồ CSV (`SessionRecorder`) | `VERIFIED` *(S22)* | Chỉ bật overlay khi người dùng cho phép quyền vẽ đè cửa sổ và bật công tắc Overlay | [docs/gaming-engine.md](docs/vi/gaming-engine.md) |
| **Thermal Intelligence, Exynos Sweet-Spot & Bypass Charging** | Guard 4 mức nhiệt (`THERMAL_GUARD_ENABLED`), Exynos 2200 Sustained Sweet-Spot (~82% peak), Soft Thermal Step-Down, Bypass Charging hysteresis (`>= BYPASS_MIN_PCT`), Samsung GOS Neutralizer | `VERIFIED` *(S22)* / `EXPERIMENTAL` *(máy khác)* | **Không** tắt Thermal Protection phần cứng (`trip_point_*`); `THERMAL_UNLOCK` trên máy lạ là thử nghiệm | [docs/thermal-management.md](docs/vi/thermal-management.md) |
| **External Display, Res Override & DeX-Safe Freezer** | Tắt chỉ màn hình trong khi cắm HDMI/DP (`EXT_DISPLAY_SCREEN_OFF` có safety guard); đổi độ phân giải (`RES_OVERRIDE_ENABLED`); đóng băng app nền `cgroup.freeze` v2 bỏ qua app mở ở View/DeX | `VERIFIED` *(S22 HDMI/DP + cgroup v2)* | Cấm tắt màn trong nếu không có màn ngoài; Freezer cần kernel hỗ trợ `cgroup.freeze` | [docs/configuration.md](docs/vi/configuration.md) |
| **Touch & Network Diagnostics** | Áp node cảm ứng nếu kernel hỗ trợ (`touch_game_node`) + đo tần số lấy mẫu (`touch measure`) và độ trễ ping (`net test 1.1.1.1`) | `PARTIAL` *(đã cài, phụ thuộc node từng máy)* | Bật/tắt qua `TOUCH_OPT_ENABLED` & `NET_OPT_ENABLED` | [docs/configuration.md](docs/vi/configuration.md) |
| **Standalone Material 3 Android APK** | Ứng dụng Android giao tiếp JNI Rust (`com.kgx.ultimate`) thay thế WebUI, tích hợp 3 Quick Settings Tiles | `VERIFIED` *(S22 Android 12)* | Cần Android 8.0+ và quyền Superuser KernelSU | [docs/installation.md](docs/vi/installation.md) |
| **Material 3 WebUI cũ (`module/webroot`)** | Giao diện web trong KernelSU | `UNSUPPORTED` *(Đã xóa)* | Đã loại bỏ hoàn toàn từ v3.3+ → dùng Standalone APK thay thế | — |

---

<a id="read-before-installing--cảnh-báo"></a>
## 2. Đọc trước khi cài — CẢNH BÁO RỦI RO

> [!CAUTION]
> **Hãy đọc kỹ trước khi tải hoặc flash module:**
> 1. Dự án này **can thiệp sâu vào hệ thống Android ở quyền Root** (properties hệ thống, `GameManager`, tần số quét màn hình, `sysfs` CPU/GPU/pin, `pm disable-user` GOS, Zygisk hooks).
> 2. Yêu cầu thiết bị đã cài sẵn **KernelSU** tương thích. Root và chỉnh sửa hệ thống luôn tiềm ẩn rủi ro gây văng app, hao pin, nóng máy hoặc lỗi hệ thống.
> 3. Cấu hình không tương thích trên thiết bị/kernel chưa được kiểm thử **có thể làm điện thoại khởi động lỗi (bootloop)**.
> 4. **Có thể mất toàn bộ dữ liệu** nếu thiết bị gặp sự cố nghiêm trọng và bạn buộc phải Wipe Data / chạy lại firmware gốc để khôi phục.
> 5. Không phải mọi thiết bị đều có đầy đủ các node phần cứng (Bypass Charging, Exynos UFCC, node touch game, `cgroup.freeze`).
> 6. **120 FPS không được đảm bảo trên mọi tựa game**: Nhiều game khóa cứng 60 FPS ở tầng engine hoặc giới hạn theo tần số màn hình thực tế (VD trong Samsung DeX 75Hz).
> 7. **Device Profile không đồng nghĩa tương thích thật**: Thông số spoof chỉ thay đổi nhận diện model/thương hiệu ở tầng app/property.
> 8. **Không đảm bảo vượt qua Play Integrity**: *Stock-Identity Shield* giúp GMS không đọc nhầm tên máy spoof của module, nhưng kết quả chứng thực còn phụ thuộc bootloader, trạng thái root và module Play Integrity riêng của bạn.
> 9. **Không đảm bảo mọi game cho phép module chạy** hoặc không phát hiện môi trường root/Zygisk.
> 10. **Module KHÔNG vô hiệu hóa Thermal Protection phần cứng**: Các ngưỡng ngắt nhiệt bảo vệ chip (`trip_point_*`) luôn được giữ nguyên.
> 11. **Tính năng Experimental (`THERMAL_UNLOCK=1`, áp dụng trên SoC/máy chưa kiểm chứng thực tế)**: Có thể làm máy nóng rất nhanh và sụt FPS vì thermal throttling nặng hơn — không bật nếu chưa có tản nhiệt và chưa sao lưu.
> 12. **Người dùng tự chịu hoàn toàn trách nhiệm** khi cài đặt và sử dụng phần mềm này theo điều khoản giấy phép GNU GPL v3.0 hoặc mới hơn (`GPL-3.0-or-later`).

### 6 việc BẮT BUỘC phải làm trước khi cài
1. **Sao lưu dữ liệu quan trọng** (ảnh, tin nhắn, tài liệu, mã 2FA) ra ngoài điện thoại.
2. Đọc [Bảng tương thích](#compatibility) bên dưới để biết máy bạn đang ở mức `VERIFIED`, `PARTIAL` hay `UNKNOWN`.
3. Kiểm tra **phiên bản Android** (tối thiểu Android 8.0 / khuyến nghị Android 12+).
4. Kiểm tra **phiên bản KernelSU** đang hoạt động ổn định.
5. Tải đúng gói **Module ZIP** và **Companion APK** từ Releases, **kiểm tra SHA-256** trước khi cài.
6. Đọc trước mục [Recovery — Cứu hộ khi gặp lỗi](#54-recovery--cứu-hộ-khi-gặp-lỗi) để biết đường xử lý nếu gặp sự cố.

---

<a id="compatibility"></a>
## 3. Bảng tương thích thực tế (Compatibility)

**Quy ước phân loại trung thực:**
- `VERIFIED`: Đã kiểm thử trực tiếp trên máy thật.
- `PARTIAL`: Mới kiểm thử qua bộ mock giả lập trên máy tính (`tests/verify_all.py`) hoặc mới xác minh một phần.
- `EXPERIMENTAL`: Tính năng thử nghiệm rủi ro nhiệt/xung cao hoặc chưa kiểm chứng chéo trên nhiều máy.
- `UNSUPPORTED`: Không hỗ trợ về mặt kiến trúc.
- `UNKNOWN`: Chưa có dữ liệu kiểm thử thực tế *(không tự tuyên bố hỗ trợ chỉ vì chung tên hãng/SoC)*.

| Hạng mục | Thông tin thực tế | Trạng thái | Ghi chú kiểm chứng |
|---|---|---|---|
| **Thiết bị thật đã kiểm thử** | **Samsung Galaxy S22 Exynos (`SM-S901B` / `r0s`)**, Exynos 2200 (`s5e9925`), Xclipse 920 (`sgpu`), màn LTPO 10–120Hz | `VERIFIED` | Đã kiểm thử thực tế trên phần cứng của maintainer |
| **Android** | **Android 12 / One UI 4.1 (API 31)** *(VERIFIED)*; API 26–34 *(mức mã nguồn)* | `VERIFIED` *(API 31)* / `UNKNOWN` *(bản khác)* | Kiểm tra tối thiểu Android >= 8.0 (API 26) trong `customize.sh` |
| **Architecture** | **ARM64 (`arm64-v8a`)** | `VERIFIED` | `armeabi-v7a`, `x86`, `x86_64`: `UNSUPPORTED` |
| **Root solution** | **KernelSU temproot (`samsung-v2.2`, code `32687`) + ReZygisk** | `VERIFIED` | APatch / KernelSU Next / Zygisk Next: `UNKNOWN` (chưa test thật) |
| **Kernel** | Kernel stock Samsung S22 Exynos + KernelSU temproot | `VERIFIED` | Kernel custom trên máy khác: `UNKNOWN` |
| **Companion APK** | `KSU-Ultimate-Gaming-X-v1.0.0.apk` (minSdk 26 / targetSdk 34) | `VERIFIED` *(Android 12)* | Yêu cầu quyền Superuser KernelSU |
| **WebUI (KernelSU)** | Đã xóa `module/webroot` | `UNSUPPORTED` | Thay thế hoàn toàn bằng Companion APK |
| **Rust Binary** | Target `aarch64-linux-android` (`kgx-core`, `libkgx_rust.so`) | `VERIFIED` | Không dùng external crates |
| **SoC Adreno / MediaTek Mali** | Snapdragon / Dimensity trong DB & mock test Stage 4A/4B | `PARTIAL` *(Mock only)* | Chưa kiểm thử trên máy thật → cẩn trọng trước khi bật tweak xung |
| **Tương thích theo Game** | Đánh giá từng tựa game (`WHITELIST`, `GAME_CAP`, `OPEN`) qua DB 31 game | `VERIFIED` *(Free Fire / Delta Force VN trên Display #0)* | Nhiều game tự khóa FPS ở tầng engine hoặc DeX 75Hz (`GAME_CAP`/`DISPLAY_LIMIT`) |

---

<a id="requirements"></a>
## 4. Yêu cầu trước khi cài (Requirements)

- **Thiết bị & CPU**: Máy Android sử dụng chip **ARM64 (`arm64-v8a`)**.
- **Hệ điều hành**: Android **8.0+ (API 26+)**; khuyến nghị **Android 12+ (API 31+)** để hỗ trợ đầy đủ `cmd game downscale` và `GameManager`.
- **Root**: Đã cài sẵn **KernelSU** đang hoạt động (trên máy temproot, phải nạp temproot thành công trước khi mở app hoặc flash).
- **Zygisk (khuyên dùng)**: Cài **ReZygisk** (hoặc provider Zygisk API v4 tương thích) nếu muốn sử dụng **Play Integrity Shield**, **Exclude Settings** và **Spoof Denylist**.
- **Dung lượng trống**: Tối thiểu ~20 MB trống trên `/data` để giải nén module, lưu trạng thái gốc và backup.
- **Quyền cho Companion APK**: Quyền Superuser (`su`) trong KernelSU Manager; quyền Vẽ đè trên ứng dụng khác (`SYSTEM_ALERT_WINDOW`) + Thông báo chỉ cần khi bạn bật **Scene FPS Overlay**.

---

<a id="installation-guide"></a>
## 5. Hướng dẫn cài đặt cho người mới (A → Z)

Xem hướng dẫn cực kỳ chi tiết từng bước tại **[docs/installation.md](docs/vi/installation.md)**. Tóm tắt quy trình chuẩn:

### 5.1. Download (Tải đúng file)
1. Mở trang **[GitHub Releases v1.0.0](https://github.com/hangothanhh/ksu-ultimate-gaming-x/releases/tag/v1.0.0)**.
2. Phân biệt rõ **2 file** cần tải:
   - `KSU-Ultimate-Gaming-X-v1.0.0.zip` → **Module KernelSU** (flash trong KernelSU Manager).
   - `KSU-Ultimate-Gaming-X-v1.0.0.apk` → **Companion App** (cài như app Android bình thường).
3. **KHÔNG** tải `Source code (zip)` ở mục Assets/Code để đem đi flash — KernelSU sẽ báo lỗi không cài được.

### 5.2. Verify Download (Xác minh SHA-256 trước khi cài)
Kiểm tra mã băm SHA-256 để bảo đảm file tải về nguyên vẹn, không bị lỗi mạng:

- **Windows:**
  ```cmd
  certutil -hashfile KSU-Ultimate-Gaming-X-v1.0.0.zip SHA256
  certutil -hashfile KSU-Ultimate-Gaming-X-v1.0.0.apk SHA256
  ```
- **Linux / Android Termux:**
  ```sh
  sha256sum KSU-Ultimate-Gaming-X-v1.0.0.zip KSU-Ultimate-Gaming-X-v1.0.0.apk
  ```
- **macOS:**
  ```sh
  shasum -a 256 KSU-Ultimate-Gaming-X-v1.0.0.zip KSU-Ultimate-Gaming-X-v1.0.0.apk
  ```

Đối chiếu với mã băm thực tế của bản phát hành **`v1.0.0`** (tính trực tiếp từ file build đã vượt qua đủ 7 stage kiểm thử):

| Tên file | Kích thước | Mã SHA-256 chuẩn |
|---|---|---|
| `KSU-Ultimate-Gaming-X-v1.0.0.zip` | `633,482` bytes | `700c1449e3db4fc901d346e9f427f51161ae279b23851649e3566b82b91c5bd7` |
| `KSU-Ultimate-Gaming-X-v1.0.0.apk` | `369,411` bytes | `fc5f04e4f2ddafa037f9a7c0951580500de38c11e571939a8b793499e962722a` |

*(Nếu chuỗi hash trên máy bạn khác dù chỉ 1 ký tự, hãy xóa file và tải lại.)*

### 5.3. Install Module & Companion APK
1. Mở **KernelSU Manager**, xác nhận dòng trạng thái đang hoạt động bình thường.
2. Vào mục **Mô-đun (Modules)** → chọn nút **Cài đặt (Install)** *(vị trí tùy phiên bản KSU Manager)* → chọn `KSU-Ultimate-Gaming-X-v1.0.0.zip`.
3. Chờ màn hình cài đặt hiện `- Installation complete!`. Nếu thấy dòng bắt đầu bằng `!`, xem phần lỗi trong [docs/installation.md](docs/vi/installation.md).
4. Khởi động lại máy (hoặc **Soft-Reboot** nếu dùng KernelSU temproot theo đúng hướng dẫn thiết bị của bạn).
5. Cài đặt file `KSU-Ultimate-Gaming-X-v1.0.0.apk`, cấp quyền Superuser cho `KSU Gaming X` trong KernelSU Manager → Tab **Siêu người dùng**.

### 5.4. Kiểm tra lần đầu (First Launch Verification)
Mở **KSU Gaming X** và xác minh bằng mắt lẫn lệnh thực tế:
- Daemon báo **Running (`pid > 0`)**.
- Hiển thị đúng SoC/GPU và `Display Max Hz` gốc (không tụt về `60 Hz` nếu máy bạn màn `120 Hz`).
- Kiểm tra cấu hình mặc định trong `global.conf`: `SPOOF_ENABLED=1`, `PLAY_INTEGRITY_SHIELD=1`, `SPOOF_EXCLUDE_SETTINGS=1`, `THERMAL_GUARD_ENABLED=1`, `THERMAL_UNLOCK=0`.
- Kiểm tra nhanh bằng dòng lệnh (qua Termux root hoặc `adb shell su -c ...`):
  ```sh
  /data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl status
  /data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl spoof diag
  ```

---

<a id="update-rollback-uninstall--recovery"></a>
## 6. Cập nhật, Rollback, Gỡ cài đặt & Cứu hộ (Recovery)

Hướng dẫn chi tiết nằm tại **[docs/backup-restore.md](docs/vi/backup-restore.md)**. Tóm tắt:
- **Cập nhật (Update)**: Luôn sao lưu (`kgxctl backup create pre_update`), kiểm tra SHA-256 bản mới rồi flash qua KernelSU Manager. Theo `module/customize.sh`, nâng cấp **giữ lại** `global.conf`, `custom_games.tsv`, `spoof_denylist.list`, `custom_profiles.tsv` và tự chuẩn hóa cấu hình cũ. Sau khi nâng cấp `.so`, khởi động lại/Soft-Reboot sạch (không chép đè `.so` khi `zygote64` đang chạy).
- **Rollback tức thì**: Bật **Safe Mode** trong app, hoặc bấm nút **Action** của module trong KernelSU Manager (`action.sh`), hoặc chạy `kgxctl safemode on && kgxctl rollback`.
- **Gỡ cài đặt (Uninstall)**: Gỡ module trong **KernelSU Manager → Mô-đun** rồi khởi động lại. `module/uninstall.sh` tự hoàn nguyên GOS, mạng, touch, gỡ đóng băng `cgroup.freeze`, tắt bypass sạc, hoàn nguyên `wm size`/`density`, tần số quét và xóa `system.prop` + `/data/adb/ksu_gaming_x` (hoặc giữ thư mục `backups/` nếu `KEEP_BACKUPS_ON_UNINSTALL=1`). Không xóa thủ công các file hệ thống `/system`.

### 5.4. Recovery — Cứu hộ khi gặp lỗi
- **Chỉ APK crash / không mở được**: Xóa dữ liệu cache của APK và cài lại bản đúng SHA-256.
- **Module không nạp / kẹt dịch vụ**: Bật `SAFE_MODE=1` hoặc bấm nút **Action** trong KernelSU Manager.
- **Module gây bootloop**: Module tích hợp sẵn bộ đếm `boot_counter` trong `module/post-fs-data.sh` — nếu khởi động lỗi **2 lần liên tiếp**, module tự động bật `SAFE_MODE=1`, xóa `system.prop` và khôi phục thông số gốc.
- **Không vào được Android dù đã qua bootloop guard**: Dùng **KernelSU Safe Mode** (tổ hợp phím giảm âm lượng lúc boot tùy bản KSU), hoặc khởi động lại bình thường nếu dùng **temproot** để trở về ROM sạch chưa kích hoạt KSU. *(Cảnh báo: chỉ Factory Reset / Wipe Data khi bất khả kháng vì thao tác đó sẽ **XÓA MẤT DỮ LIỆU CÁ NHÂN** trên máy.)*

---

<a id="troubleshooting--diagnostic-report"></a>
## 7. Xử lý sự cố & Báo cáo lỗi an toàn (`kgxctl diag`)

Xem danh sách đầy đủ **14 tình huống lỗi thường gặp cho người mới** (từ không thấy module, WebUI không mở, không tăng FPS, tụt 60Hz, nóng máy, đến xung đột & Play Integrity) tại **[docs/troubleshooting.md](docs/vi/troubleshooting.md)**.

### Xuất báo cáo chẩn đoán đã ẩn thông tin cá nhân (`kgxctl diag`)
```sh
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl diag /sdcard/Download/kgx_diag.txt"
```
Lệnh trên ghi file báo cáo gồm version module, Android/API, kernel, KernelSU, SoC/GPU, trạng thái daemon, các cờ cấu hình và 40 dòng log gần nhất — đồng thời **tự động che kín** serial, IMEI, địa chỉ MAC, email, IP riêng và token/mật khẩu thành `[REDACTED_*]` trước khi bạn dán lên **[GitHub Issues](https://github.com/hangothanhh/ksu-ultimate-gaming-x/issues)**.

---

<a id="repository-structure--build-from-source"></a>
## 8. Cấu trúc mã nguồn & Build từ Source

### Cấu trúc thư mục thực tế
```text
ksu-ultimate-gaming-x/
├── README.md                          # Tài liệu tổng quan tiếng Anh (chính)
├── README.vi.md                       # Tài liệu tổng quan tiếng Việt
├── CHANGELOG.md                       # Lịch sử phiên bản chính thức
├── CONTRIBUTING.md                    # Quy chuẩn đóng góp & chính sách chống AI slop
├── LICENSE                            # Giấy phép GNU GPL v3.0+ (GPL-3.0-or-later)
├── NOTICE                             # Ghi công bên thứ ba & minh bạch AI
├── AI_CONTRIBUTIONS.md                # Công bố minh bạch đóng góp của Google Antigravity
├── SECURITY.md                        # Chính sách bảo mật & ranh giới an toàn root
├── .gitignore                         # Loại trừ keystore, dist/, system.prop, cache build
├── .editorconfig                      # Chuẩn UTF-8 & LF
├── .github/
│   ├── workflows/ci.yml               # GitHub Actions kiểm tra ZIP + Stages 1-6 (--skip-apk)
│   ├── ISSUE_TEMPLATE/                # Bug Report, Feature Request, Compatibility Report
│   └── PULL_REQUEST_TEMPLATE.md       # Mẫu PR có mục kiểm tra AI & rollback
├── docs/                              # Tài liệu chuyên sâu từng phân hệ
│   ├── installation.md
│   ├── configuration.md
│   ├── gaming-engine.md
│   ├── fps-compatibility.md
│   ├── device-database.md
│   ├── thermal-management.md
│   ├── backup-restore.md
│   ├── troubleshooting.md
│   ├── development.md
│   └── vi/                            # Bản dịch tiếng Việt của bộ docs/
├── module/                            # Lõi KernelSU module (POSIX sh + ARM64 binaries)
│   ├── module.prop                    # Metadata module (v1.0.0 / versionCode=100)
│   ├── post-fs-data.sh                # Bootloop guard & safe global spoof lúc boot sớm
│   ├── service.sh                     # Khôi phục crash/reboot & khởi chạy daemon nền
│   ├── action.sh                      # Nút Action nhanh trong KernelSU Manager
│   ├── customize.sh                   # Trình cài đặt & migrate config khi nâng cấp
│   ├── uninstall.sh                   # Hoàn nguyên toàn bộ hệ thống khi gỡ
│   ├── bin/
│   │   ├── kgxctl                     # CLI điều khiển JSON & xuất chẩn đoán diag
│   │   ├── kgx-core                   # Daemon & bộ đọc telemetry Rust AArch64
│   │   └── gaming_daemon.sh           # Wrapper daemon & fallback POSIX
│   ├── lib/                           # 16 thư viện module POSIX sh
│   ├── data/                          # devices.tsv/json, games.tsv/json, default_global.conf, kgx-display.dex
│   └── zygisk/arm64-v8a.so            # Thư viện Zygisk Stock-Identity & Denylist Shield
├── companion/
│   ├── rust-core/src/main.rs          # Mã nguồn daemon Rust native
│   ├── zygisk-spoof/                  # Mã nguồn C++17 Zygisk API v4 & header zygisk.hpp
│   ├── display-helper/                # DisplayPowerCtrl.java cho kgx-display.dex
│   └── android-app/                   # Companion Android APK (Java + Material 3 + Rust JNI)
├── scripts/
│   ├── build_rust.py                  # Biên dịch kgx-core, zygisk arm64-v8a.so, libkgx_rust.so
│   ├── build_apk.py                   # Build DEX & ký Companion APK (không cần Gradle)
│   └── build_zip.py                   # Đóng gói deterministic ZIP chuẩn UNIX LF/quyền hạn
└── tests/
    └── verify_all.py                  # Bộ kiểm thử tự động 7 stage (hỗ trợ --skip-apk trên CI)
```

### Lệnh Build & Kiểm thử nhanh
Xem hướng dẫn chi tiết từng công cụ (Rust, Android NDK `29.0.14206865`, Android SDK `android-34`, Build-Tools `34.0.0`, OpenJDK 17) tại **[docs/development.md](docs/vi/development.md)**:
```powershell
python -u scripts/build_rust.py
python -u scripts/build_apk.py
python -u scripts/build_zip.py
python -u tests/verify_all.py
```

---

<a id="contributing-license--credits"></a>
## 9. Đóng góp, Giấy phép & Nguồn bên thứ ba

- **Đóng góp (Credits / Contributions)**:
  - Maintainer chính: `hangothanhh` (thiết kế, kiểm chứng thực tế trên phần cứng thật và bảo trì dự án).
  - Hỗ trợ phát triển: **Google Antigravity** (hỗ trợ mã nguồn, kiểm thử và tài liệu — xem chi tiết tại **[AI_CONTRIBUTIONS.md](docs/vi/AI_CONTRIBUTIONS.md)**).
- **Quy chuẩn PR**: Xem **[CONTRIBUTING.md](docs/vi/CONTRIBUTING.md)** (chú ý quy tắc bắt buộc về minh bạch AI và chống *AI slop*).
- **Chính sách bảo mật**: Xem **[SECURITY.md](docs/vi/SECURITY.md)**.
- **Giấy phép**: Phát hành theo **[GNU General Public License v3.0 hoặc mới hơn (`GPL-3.0-or-later`)](LICENSE)** — Copyright (C) 2026 `hangothanhh`.
- **Ghi công & Nguồn bên thứ ba**: Xem **[NOTICE](NOTICE)** (bao gồm header public Zygisk API v4 trong `companion/zygisk-spoof/include/zygisk.hpp` — Copyright 2022–2023 John "topjohnwu" Wu).
