# Gaming Performance Engine & Rust Daemon (`kgx-core`)

> **Ngôn ngữ**: [English](../gaming-engine.md) | **Tiếng Việt**

## 1. Mục đích
Giải thích cách hệ thống tự nhận diện game foreground, kích hoạt cấu hình tối ưu theo từng trò chơi (`session.sh` + `cpu_gpu.sh` + `ram.sh` + `touch.sh` + `freezer.sh`) và đảm bảo hoàn nguyên sạch sẽ khi thoát game hoặc khởi động lại.

---

## 2. Cách hoạt động

```text
  game foreground? ──(poll 1–2s trong kgx-core)──> session_should_optimize_pkg()
         │                                                   │ (Có)
         │ (Không, quá EXIT_DEBOUNCE_SEC)                    ▼
         ▼                                           session_activate(pkg)
  session_deactivate()                         1. Đọc game DB + custom_games.tsv
  - reset wm size/density                      2. Thermal check + spoofing
  - khôi phục mạng/touch/RAM/CPU/GPU/Hz        3. GameManager pre-apply / display_apply
  - gỡ đóng băng cgroup v2                     4. Pin luồng render + CPU/GPU/touch/RAM/net/freezer
```

### Điểm khác biệt an toàn của kiến trúc v1.0.0
1. **Zero-Lock Daemon (`companion/rust-core/src/main.rs`)**:
   - Đọc telemetry CPU/GPU/RAM/pin (`mW`/`mA`) và SurfaceFlinger layer flips trực tiếp qua sysfs/`/proc` với cache 2 giây (`ov_layer.cache`), tránh gọi `dumpsys activity` / `dumpsys display` nặng trong vòng lặp polling.
2. **Không dùng `am kill-all` hay `cmd netpolicy`**:
   - RAM optimizer (`module/lib/ram.sh`) chỉ trim/dọn theo danh sách tiến trình nền được phép qua `kgx-core trim-list`, không bao giờ đụng Launcher, SystemUI, bàn phím (`inputmethod`) hay trình quản lý root.
3. **Render-thread pinning an toàn (`kgx-core pin-threads`)**:
   - Đẩy các thread game như `RenderThread`, `UnityMain`, `GameThread`, `RHIThread`, `RenderWorker`, `AsyncRender`, `Vulkan` vào `cpuctl/top-app/cgroup.threads` (nếu tồn tại) và nâng nhẹ priority `renice -6`.
4. **Cgroup v2 Freezer thân thiện với View / Samsung DeX (`module/lib/freezer.sh`)**:
   - Chỉ đóng băng app trong `freezer_apps.list` khi `oom_score_adj >= 500` **và** app đó không có surface đang hiển thị trên SurfaceFlinger (giữ nguyên các app đang mở ở cửa sổ Pop-up View hoặc Samsung DeX).

---

## 3. Yêu cầu & Điều kiện sử dụng
- Daemon mặc định chạy `bin/kgx-core daemon` trên thiết bị ARM64; trên môi trường mô phỏng shell POSIX sẽ fallback sang `bin/gaming_daemon.sh`.
- Tính năng pin luồng `top-app` và App Freezer phụ thuộc kernel có hỗ trợ `cpuctl` / `cgroup.freeze` v2.

---

## 4. Kiểm tra trạng thái hoạt động
```sh
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl daemon status"
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl status"
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl logs 40"
```
Khi bạn mở game có trong `custom_games.tsv` hoặc `games.tsv`, log `engine.log` sẽ có dòng:
`Activated session for <Ten game> (<package>): mode=..., fps=..., downscale=...`
Và khi về màn hình chính quá `EXIT_DEBOUNCE_SEC` (mặc định 2 giây):
`Deactivated session (<package>, reason=left_foreground); stock system state restored.`

---

## 5. Cảnh báo & Khắc phục nhanh
- **Game không được tự kích hoạt khi mở**: Kiểm tra công tắc `AUTO_OPTIMIZE=1` trong app, kiểm tra xem package game có nằm trong `custom_games.tsv` (và cột `enabled=1`) hoặc `games.tsv` không, và kiểm tra màn hình có đang bật (`Awake`) hay không.
- **Nếu đang chạy trong Samsung DeX**: Game chạy ở `Display #2` vẫn được nhận diện foreground nếu SurfaceFlinger / ActivityRecord báo hoạt động, nhưng giới hạn Hz tối đa phụ thuộc chính `Display #2` (xem [Tương thích FPS & Tần số quét](fps-compatibility.md)).
- **Cách hoàn nguyên ngay**: Chạy `kgxctl rollback` hoặc bấm nút **Action** trong KernelSU Manager.
