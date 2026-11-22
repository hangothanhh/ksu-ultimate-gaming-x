# Sao lưu, Cập nhật, Khôi phục & Gỡ cài đặt

> **Ngôn ngữ**: [English](../backup-restore.md) | **Tiếng Việt**

## 1. Mục đích
Hướng dẫn chi tiết cách sao lưu cấu hình (`backup.sh`), cập nhật phiên bản mới, rollback cấu hình khi gặp sự cố, gỡ bỏ hoàn toàn module và các phương án cứu hộ nếu máy bị treo khởi động.

---

## 2. Sao lưu & Khôi phục cấu hình (`kgxctl backup`)

### Tạo bản sao lưu
Lưu toàn bộ `config/`, `profiles/`, và ảnh chụp gốc (`state/orig_props.tsv`, `state/orig_display.env`, `state/orig_net.env`) vào `/data/adb/ksu_gaming_x/backups/kgx_backup_<ngay>_<ten>.tar.gz`:
```sh
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl backup create manual"
```

### Liệt kê & Phục hồi bản sao lưu
```sh
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl backup list"
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl backup restore kgx_backup_20261122_120000_manual.tar.gz"
```

---

## 3. Cập nhật phiên bản mới (Update)
1. **Kiểm tra phiên bản hiện tại**: Mở Companion APK hoặc đọc `/data/adb/modules/ksu_ultimate_gaming_x/module.prop`.
2. **Sao lưu cấu hình**: Chạy `kgxctl backup create pre_update` (hoặc tạo backup trong app).
3. **Tải đúng bản phát hành mới** trên [GitHub Releases](https://github.com/hangothanhh/ksu-ultimate-gaming-x/releases) và **xác minh SHA-256** theo [docs/installation.md](installation.md).
4. **Cập nhật có giữ cấu hình không?**:
   - Đọc `CHANGELOG.md` trước khi cài.
   - Theo kiểm tra `customize.sh` trong phiên bản `v1.0.0`: trình cài đặt **giữ lại** các file trong `/data/adb/ksu_gaming_x/config/` (`global.conf`, `custom_games.tsv`, `spoof_denylist.list`), `profiles/custom_profiles.tsv`, và tự migrate bổ sung khóa còn thiếu (`PLAY_INTEGRITY_SHIELD`, `SPOOF_EXCLUDE_SETTINGS`, `orig_display.env`).
5. **Cài đặt bản mới**: Flash Module ZIP mới qua KernelSU Manager và cài đè Companion APK mới (nếu có). Sau đó khởi động lại (hoặc Soft-Reboot đúng quy trình nếu có cập nhật `zygisk/arm64-v8a.so`).
6. **Kiểm tra sau cập nhật**: Chạy `kgxctl status` và `kgxctl hw`.

---

## 4. Rollback cấu hình (khi mới chỉnh nhầm gây nóng/lag/lỗi)
- **Cách 1 (Trong app)**: Gạt bật **Safe Mode (`SAFE_MODE=1`)** — daemon dừng và khôi phục ngay toàn bộ thuộc tính, độ phân giải, tần số quét, GOS, freezer.
- **Cách 2 (Nút Action trong KernelSU Manager)**: Bấm nút **Action** bên cạnh module `KSU Ultimate Gaming X` (`module/action.sh`), lệnh này chạy `kgxctl rollback` rồi khởi động lại daemon sạch.
- **Cách 3 (Qua ADB / Terminal root)**:
  ```sh
  su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl safemode on"
  su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl rollback"
  ```

---

## 5. Gỡ cài đặt hoàn toàn (Uninstall)

### Quy trình chuẩn
1. Mở **KernelSU Manager → Mô-đun**.
2. Để tắt tạm thời (không xóa cấu hình): gạt **tắt công tắc** của `KSU Ultimate Gaming X` rồi khởi động lại.
3. Để gỡ hoàn toàn: bấm nút **Thùng rác / Gỡ bỏ (Uninstall)** rồi khởi động lại máy. Script `module/uninstall.sh` sẽ tự chạy ở lần boot kế tiếp để:
   - Dừng daemon `kgx-core`.
   - Khôi phục GOS, mạng, touch, gỡ đóng băng toàn bộ app `cgroup.freeze`, tắt Bypass Charging, khôi phục RAM/thermal/CPU/GPU, reset `wm size`/`density`, bật lại màn hình trong, khôi phục tần số quét, hoàn nguyên `GameManager` và xóa `system.prop` / spoof props.
   - Xóa `/data/adb/ksu_gaming_x` (nếu `KEEP_BACKUPS_ON_UNINSTALL=1`, giữ lại duy nhất thư mục `backups/`).
4. Gỡ **KSU Gaming X APK** như ứng dụng Android bình thường.

### Kiểm tra sau khi gỡ không còn service chạy
```sh
ps -A | grep -E 'kgx-core|gaming_daemon' || echo "Clean"
ls -la /data/adb/modules/ksu_ultimate_gaming_x 2>/dev/null || echo "Module removed"
```

---

## 6. Recovery — Cứu hộ khi gặp sự cố theo từng mức độ

| Tình huống | Phương pháp cứu hộ phù hợp & đã kiểm tra | Cảnh báo mất dữ liệu |
|---|---|---|
| **Chỉ APK bị crash / giao diện lỗi** | Xóa cache app APK hoặc cài lại APK bản đúng SHA-256; module nền vẫn an toàn | Không mất dữ liệu |
| **Module không tải / không hiệu lực** | Kiểm tra KernelSU còn hoạt động không (đặc biệt trên máy temproot), kiểm tra `SAFE_MODE` có đang `=1` không | Không mất dữ liệu |
| **Máy lag/nóng bất thường sau khi chỉnh** | Bấm **Action** trong KernelSU Manager hoặc `kgxctl safemode on` | Không mất dữ liệu |
| **Module gây bootloop (treo logo Android)** | **Cơ chế tự động của module**: `post-fs-data.sh` đếm `boot_counter`. Nếu khởi động lỗi liên tiếp **2 lần**, lần boot thứ 2 tự động bật `SAFE_MODE=1`, xóa `system.prop` và khôi phục thuộc tính gốc. | Không mất dữ liệu |
| **Không vào được Android dù đã qua bootloop guard** | Dùng **KernelSU Safe Mode** (tổ hợp phím giảm âm lượng lúc boot tùy phiên bản KernelSU để vô hiệu hóa toàn bộ module), hoặc trên **KernelSU temproot** chỉ cần ép tắt nguồn / khởi động lại bình thường là về ROM gốc chưa inject KSU, hoặc flash lại `boot.img` gốc qua Odin/Fastboot nếu cài KSU vĩnh viễn. | **CẢNH BÁO**: Flash nhầm phân vùng hoặc Wipe Data / Factory Reset trong Recovery sẽ **XÓA SẠCH DỮ LIỆU CÁ NHÂN** trên máy! Không tự ý xóa thủ công file hệ thống `/system`. |
