# Device Profile Database, Whole-System Spoof & Zygisk Stock-Identity Shield

> **Ngôn ngữ**: [English](../device-database.md) | **Tiếng Việt**

## 1. Mục đích
Giải thích cách cơ sở dữ liệu 34 thiết bị (`devices.tsv`/`devices.json`), hệ thống chấm điểm khớp GPU (`matcher.sh`), spoof toàn hệ thống an toàn (`spoof.sh`) và lá chắn Zygisk (`companion/zygisk-spoof/`) hoạt động cùng nhau mà không làm hỏng thông tin nhận diện cho Cài đặt, Google Play hay các app bạn muốn loại trừ.

---

## 2. Cơ sở dữ liệu thiết bị & chấm điểm tương thích
Module đi kèm **34 hồ sơ thiết bị mẫu** trong [module/data/devices.tsv](../../module/data/devices.tsv) và **31 tựa game** trong [module/data/games.tsv](../../module/data/games.tsv).
Khi ở chế độ `auto`, `matcher_select_auto_profile()` tính điểm dựa trên:
- Họ GPU thật của máy (`adreno`, `mali`, `xclipse`, hoặc neutral khi `unknown`) vs GPU của profile.
- Ưu tiên whitelist của game (`preferred_adreno` / `preferred_mali`).
- Khoảng cách phân khúc phần cứng (`HW_TIER`).
- Khả năng hỗ trợ tần số quét của màn hình (`DISPLAY_MAX_HZ`).

> [!IMPORTANT]
> **Cảnh báo hiểu đúng**: Khớp điểm trong cơ sở dữ liệu (*OPTIMAL / COMPATIBLE*) là phép so logic theo GPU/tier, **không đồng nghĩa thiết bị của bạn chắc chắn chạy mượt hoặc được nhà phát hành game mở khóa 120 FPS**. Một số game kiểm tra thêm chứng thực phần cứng, GPU renderer string (`GL_RENDERER`) hoặc tần số màn hình thực tế.

---

## 3. Spoof toàn hệ thống an toàn (`spoof.sh`)
- Trước khi áp bất kỳ profile nào, `spoof_capture_original()` lưu nguyên trạng các thuộc tính gốc vào `/data/adb/ksu_gaming_x/state/orig_props.tsv`.
- Áp thuộc tính qua `resetprop` và ghi `system.prop` **chỉ gồm** thông tin model/brand/manufacturer/device/product/marketname (`GLOBAL_SPOOF_PROFILE`).
- **Tuyệt đối không** sửa: `ro.serialno`, `ro.boot.*`, `ro.crypto.*`, `ro.debuggable`, `ro.secure`, `ro.adb.secure`, IMEI, và không ép `ro.build.fingerprint` vào `system.prop`.

---

## 4. Zygisk Stock-Identity Shield & Spoof Denylist (`arm64-v8a.so`)
Vì Spoof áp toàn hệ thống để game đọc đúng `android.os.Build` + `SystemProperties` ngay từ khi khởi động, những ứng dụng cần thấy máy thật sẽ dùng thư viện Zygisk API v4 tại `companion/zygisk-spoof/src/main.cpp`:
1. **Google Play Services / Store / GSF / Wallet** (khi `PLAY_INTEGRITY_SHIELD=1`): Tự động trả về thông số máy gốc cho GMS/DroidGuard, Play Store, GSF, Google Wallet.
   - *Lưu ý minh bạch*: Tính năng này chỉ giúp tránh việc spoof tên máy của module làm sai lệch danh tính máy khi kiểm tra Play Integrity. Module **không** cam kết vượt qua Play Integrity (`BASIC`/`DEVICE`/`STRONG`) — kết quả Play Integrity phụ thuộc trạng thái bootloader, KernelSU, TrickyStore/PIF và môi trường riêng của từng máy.
2. **Ứng dụng Cài đặt Android / Samsung / OEM** (khi `SPOOF_EXCLUDE_SETTINGS=1`): Tự khôi phục tên máy gốc cho `com.android.settings*`, `com.samsung.android.app.settings*`, `com.samsung.android.settings*`, `com.miui.settings`, `com.oplus.settings`, `com.coloros.settings`.
3. **Spoof Denylist do người dùng chọn (`config/spoof_denylist.list`)**: Mọi app bạn tick trong thẻ **Spoof Denylist** trên Companion APK (hoặc thêm qua `kgxctl spoof denylist-add <pkg>`) đều nhận thông tin máy gốc thay vì máy spoof.

---

## 5. Cách kiểm tra & điều khiển
```sh
# Kiểm tra trạng thái Zygisk Shield & Play Integrity diag
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl spoof diag"

# Xem danh sách app đang loại trừ spoof
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl spoof denylist"

# Thêm hoặc xóa 1 package khỏi denylist
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl spoof denylist-add ru.andr7e.deviceinfohw"
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl spoof denylist-remove ru.andr7e.deviceinfohw"

# Tắt hoàn toàn spoof (về thông số gốc)
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl engine set SPOOF_ENABLED 0"
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl spoof restore"
```
Log trên máy khi Zygisk Shield hoạt động (`logcat -d -s KGX_PIShield`):
`I KGX_PIShield: Shield active in com.google.android.gms.unstable (20 props, jni=1, scope=pi): V2425A -> stock SM-S901B (r0s)`

---

## 6. Lưu ý quan trọng khi cập nhật Denylist
- Danh sách `spoof_denylist.list` và `SPOOF_EXCLUDE_SETTINGS` được companion của Zygisk kiểm tra theo `mtime`/`size`, nên có hiệu lực cho **lần khởi chạy tiến trình mới** tiếp theo của app (hãy buộc dừng/mở lại app đó nếu app đang chạy sẵn).
- Riêng nếu vừa nâng cấp chính file `zygisk/arm64-v8a.so`, cần khởi động lại (hoặc Soft-Reboot đúng quy trình) để `zygote64` nạp bản `.so` mới. **Tuyệt đối không** dùng `unzip -o` ghi đè trực tiếp file `.so` đang được `zygote64` mở trong RAM.
