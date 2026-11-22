---
name: Feature Request
about: Propose a new feature or improvement for KSU Ultimate Gaming X (English preferred; Vietnamese also welcome)
title: "[Feature] "
labels: enhancement
assignees: ''
---

## 1. Proposed Feature
Clearly describe the problem you want to solve and the proposed behavior.

## 2. Scope & Affected Subsystems
- [ ] Module shell scripts (`module/lib/*.sh`)
- [ ] Rust daemon / CLI (`companion/rust-core/`)
- [ ] Zygisk Stock-Identity Shield (`companion/zygisk-spoof/`)
- [ ] Companion Android APK (`companion/android-app/`)
- [ ] Documentation / Device or Game database

## 3. Safety & Rollback Criteria
- Does this add new system property or `sysfs` writes? If yes, how does `SAFE_MODE=1` or `uninstall.sh` revert them cleanly?
- If any part of the proposal came from AI assistance, clearly mark what is still an untested hypothesis vs hardware-verified behavior.
