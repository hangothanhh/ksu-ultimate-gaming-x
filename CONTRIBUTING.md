# Contributing Guide

> **Language**: **English** | [Tiếng Việt](docs/vi/CONTRIBUTING.md)

Thank you for your interest in contributing to **KSU Ultimate Gaming X**! Please review these guidelines before opening an Issue or Pull Request.

---

## 1. AI Transparency & Anti-"AI Slop" Policy (REQUIRED READING)

> [!WARNING]
> **Warning About "AI Slop" (Low-Quality Auto-Generated Code or Docs):**
> This project was built with assistance from AI tools (Google Antigravity) and verified on Samsung Galaxy S22 Exynos hardware plus our automated mock suite. However, **we reject all "AI slop" Pull Requests** — including bulk AI-generated code or docs where the contributor did not read every line of the diff, understand hardware/kernel impacts, run tests, or fabricated device compatibility claims.

When submitting an AI-assisted PR:
1. **Disclose honestly** in the Pull Request template (*AI Transparency* section).
2. **Read and verify every line of your diff** before submitting.
3. **Never fabricate test results or device support**: if tested only in mock/emulator runs, state `PARTIAL (Mock only)` — never label untested hardware as `VERIFIED`.
4. **Never add unverified "word-of-mouth" `sysfs` or property tweaks** that risk kernel panics (e.g., touching `gpu_ifpo_control` or hardware thermal `trip_point_*`).

---

## 2. Fork, Build & Pull Request Workflow

### Step 1: Fork & Clone
1. Fork https://github.com/hangothanhh/ksu-ultimate-gaming-x.
2. Clone your fork:
   ```sh
   git clone https://github.com/<your-username>/ksu-ultimate-gaming-x.git
   cd ksu-ultimate-gaming-x
   ```
3. Create a descriptive branch:
   ```sh
   git checkout -b fix/short-description
   ```

### Step 2: Toolchain, Build & Test
See full toolchain instructions in [docs/development.md](docs/development.md). Summary:
- Package Module ZIP & run POSIX/mock tests without Android SDK (Stages 1–6):
  ```sh
  python3 -u scripts/build_zip.py
  python3 -u tests/verify_all.py --skip-apk
  ```
- Full Windows build (Rust `kgx-core` + Zygisk `arm64-v8a.so` + Companion APK + ZIP + all 7 test stages):
  ```powershell
  python -u scripts/build_rust.py
  python -u scripts/build_apk.py
  python -u scripts/build_zip.py
  python -u tests/verify_all.py
  ```

### Step 3: Code Standards & POSIX Hygiene
- Every shell script under `module/` **must be pure POSIX `sh`** (Stages 1 & 2 of `tests/verify_all.py` reject `[[`, `function`, `declare`, `source`, CRLF, BOM, `cmd netpolicy`, `am kill-all`, or direct `/proc/*/cmdline | tr` patterns).
- Use **LF (`\n`)** line endings matching `.editorconfig`.
- Do not hand-edit compiled binaries without updating their corresponding source under `companion/rust-core/`, `companion/zygisk-spoof/`, `companion/display-helper/`, or `companion/android-app/`.

### Step 4: Commit Conventions (Conventional Commits)
Use clear prefixes:
- `feat: add new gaming profile` — new feature or profile
- `fix: correct thermal monitoring` — bug fix
- `docs: improve installation guide` — documentation changes
- `refactor: simplify service manager` — code refactoring
- `perf: reduce dashboard polling` — performance improvement
- `test: add module validation` — test additions/fixes
- `chore: update build dependencies` — maintenance, CI, `.gitignore`

---

## 3. Mandatory Safety & License Rules

Pull Requests will be rejected immediately if they violate any of the following:
- Contributors do not agree to license their contribution under **GNU GPL v3.0 or later (`GPL-3.0-or-later`)**.
- Contains private keys, `*.keystore`, `*.jks`, API tokens, GitHub credentials, or unredacted user logs containing IMEI/serial/MAC/email.
- Adds unknown-origin dependencies, GPL-incompatible dependencies, or closed-source binaries without source/license.
- Weakens or removes guards protecting `ro.serialno`, `ro.boot.*`, `trip_point_*`, or `*ifpo*`.
- Adds game anti-cheat bypasses or hardware attestation key spoofing.
- Removes or alters the copyright notice inside [companion/zygisk-spoof/include/zygisk.hpp](companion/zygisk-spoof/include/zygisk.hpp).
