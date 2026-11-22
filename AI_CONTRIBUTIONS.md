# AI Contributions Disclosure (`AI_CONTRIBUTIONS.md`)

> **Language**: **English** | [Tiếng Việt](docs/vi/AI_CONTRIBUTIONS.md)

This document transparently discloses the role of **Google Antigravity** (AI coding assistant) in **KSU Ultimate Gaming X**, separating human maintainer ownership, technical assistance scope, hardware verification coverage, and legal attribution boundaries.

---

## 1. Maintainer & AI Coding Assistant

- **Maintainer & Project Owner (`Copyright Holder`)**: **`hangothanhh`**
  - Defines product requirements, supplies physical device diagnostics and logs, reviews changes, tests on real hardware, and manages releases (`v1.0.0`).
- **AI Coding Assistant**: **Google Antigravity**
  - Assisted with software architecture, implementation, refactoring, automated mock test suite authoring, bilingual documentation, and CI setup under maintainer direction.

---

## 2. Technical Scope Assisted by Google Antigravity

- **KernelSU Module Engine (`module/`)**: Authored and debugged POSIX `sh` scripts (`post-fs-data.sh`, `service.sh`, `customize.sh`, `uninstall.sh`, `action.sh`, `bin/kgxctl`, `lib/*.sh`), including bootloop protection, `PlatformCompat killUid` crash fixes, Exynos `gpu_ifpo_control` protection, LTPO 120Hz primary display isolation, SamHelper `120.1` sanitization, Spoof Denylist, and redacted `kgxctl diag` exports.
- **Native Rust Core & JNI (`companion/rust-core/`, `companion/android-app/rust-jni/`)**: Implemented the `kgx-core` daemon (sysfs/SurfaceFlinger FPS telemetry, thermal/bypass/freezer coordination, signal restoration) and JNI bridge.
- **Zygisk Stock-Identity & Denylist Shield (`companion/zygisk-spoof/src/main.cpp`)**: Implemented and fixed `.so`-only PLT filtering and stock property restoration for GMS/Settings/Denylist packages.
- **Standalone Companion APK (`companion/android-app/java/`)**: Built the Zero-Gradle Material 3 Android UI (`MainActivity`, Overlay Service, Session Recorder, Quick Settings Tiles).
- **Automated Testing & CI (`tests/verify_all.py`, `.github/workflows/ci.yml`)**: Built the 7-stage POSIX/mock test suite and GitHub Actions workflow.
- **Documentation**: Prepared [README.md](README.md), [README.vi.md](README.vi.md), [CHANGELOG.md](CHANGELOG.md), [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), and all guides under `docs/` and `docs/vi/`.

---

## 3. Hardware Verification Boundaries & "AI Slop" Notice

- **`VERIFIED` (physically tested by maintainer `hangothanhh`)**:
  - Samsung Galaxy S22 Exynos (`SM-S901B` / `r0s`), Android 12 / One UI 4.1, KernelSU temproot + ReZygisk.
- **`PARTIAL` (tested via POSIX/mock suite in `tests/verify_all.py` only)**:
  - Qualcomm Adreno and MediaTek Mali device profiles have not been verified on physical hardware.
- **Risk Disclaimer**: AI-assisted code and documentation may contain edge-case assumptions on untested devices or ROMs. Do not treat sample database entries as guaranteed hardware compatibility.

---

## 4. Legal & Git Attribution Boundaries

1. Contributions from **Google Antigravity** are credited purely inside repository documentation (`AI_CONTRIBUTIONS.md`, `README.md`, `NOTICE`) — **without** appending bot `Co-authored-by:` trailers to Git commits, keeping Git commit history and GitHub Contributors linked strictly to maintainer `hangothanhh`.
2. AI attribution does **not** alter copyright ownership (`Copyright (C) 2026 hangothanhh`), does **not** override **GNU GPL v3.0 or later (`GPL-3.0-or-later`)** obligations, and preserves third-party notices in [NOTICE](NOTICE).
3. Mentioning Google Antigravity strictly records tooling assistance and implies **no** endorsement, sponsorship, or warranty from Google.
