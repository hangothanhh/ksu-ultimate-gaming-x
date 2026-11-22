# Gaming Performance Engine & Rust Daemon (`kgx-core`)

> **Language**: **English** | [Tiếng Việt](vi/gaming-engine.md)

## 1. Purpose
Explains how the engine detects foreground games, activates per-game optimization profiles (`session.sh` + `cpu_gpu.sh` + `ram.sh` + `touch.sh` + `freezer.sh`), and cleanly restores stock state when you exit a game or reboot.

---

## 2. How It Works

```text
  game foreground? ──(1–2s poll in kgx-core)──> session_should_optimize_pkg()
         │                                                   │ (Yes)
         │ (No, past EXIT_DEBOUNCE_SEC)                      ▼
         ▼                                           session_activate(pkg)
  session_deactivate()                         1. Read game DB + custom_games.tsv
  - reset wm size/density                      2. Thermal check + spoofing
  - restore net/touch/RAM/CPU/GPU/Hz           3. GameManager pre-apply / display_apply
  - unfreeze cgroup v2 apps                    4. Pin render threads + CPU/GPU/touch/RAM/net/freezer
```

### Safe Architecture Highlights (`v1.0.0`)
1. **Zero-Lock Daemon (`companion/rust-core/src/main.rs`)**:
   - Reads CPU/GPU/RAM/battery (`mW`/`mA`) metrics and SurfaceFlinger layer flips directly from `sysfs`/`/proc` with a 2-second layer cache (`ov_layer.cache`), avoiding heavy `dumpsys activity` / `dumpsys display` polling stalls.
2. **No `am kill-all` or `cmd netpolicy`**:
   - The RAM optimizer (`module/lib/ram.sh`) trims only allowlisted background processes via `kgx-core trim-list`, never killing Launcher, SystemUI, keyboards (`inputmethod`), or root managers.
3. **Safe Render-Thread Pinning (`kgx-core pin-threads`)**:
   - Assigns game threads (`RenderThread`, `UnityMain`, `GameThread`, `RHIThread`, `RenderWorker`, `AsyncRender`, `Vulkan`) to `cpuctl/top-app/cgroup.threads` (if present) and applies a mild priority boost (`renice -6`).
4. **View / Samsung DeX-Friendly Cgroup v2 Freezer (`module/lib/freezer.sh`)**:
   - Freezes packages in `freezer_apps.list` only when `oom_score_adj >= 500` **and** the app has no active SurfaceFlinger display layer (keeping Pop-up View and Samsung DeX windows alive).

---

## 3. Requirements & Conditions
- On ARM64 Android devices, the daemon runs `bin/kgx-core daemon` natively; in POSIX shell mock tests it falls back to `bin/gaming_daemon.sh`.
- Render-thread pinning and App Freezer require kernel support for `cpuctl` / `cgroup.freeze` v2.

---

## 4. Checking Runtime Status
```sh
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl daemon status"
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl status"
su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl logs 40"
```
When launching a configured game from `custom_games.tsv` or `games.tsv`, `engine.log` records:
`Activated session for <Game Name> (<package>): mode=..., fps=..., downscale=...`
After returning home longer than `EXIT_DEBOUNCE_SEC` (default `2s`), it logs:
`Deactivated session (<package>, reason=left_foreground); stock system state restored.`

---

## 5. Troubleshooting Quick Tips
- **Game does not auto-activate**: Verify `AUTO_OPTIMIZE=1`, verify the package exists in `custom_games.tsv` (`enabled=1`) or `games.tsv`, and verify the screen is `Awake`.
- **Running inside Samsung DeX**: Games on `Display #2` are detected if SurfaceFlinger / ActivityRecord reports them active, though max FPS still follows `Display #2`'s physical Hz (see [FPS Compatibility](fps-compatibility.md)).
- **Immediate rollback**: Run `kgxctl rollback` or tap **Action** in KernelSU Manager.
