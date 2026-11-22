---
name: Device Compatibility Report
about: Share real-world physical device test results to keep our compatibility matrix honest (English preferred; Vietnamese also welcome)
title: "[Compat] "
labels: compatibility
assignees: ''
---

## 1. Tested Device Information
- **Brand / Model / Codename**:
- **SoC / GPU**:
- **Android / ROM**:
- **Kernel Version (`uname -r`)**:
- **KernelSU + Zygisk Provider**:
- **KSU Ultimate Gaming X Version**: `v1.0.0`

## 2. Feature Verification Status (Check ONLY what you personally tested)
| Feature | Status (`VERIFIED` / `PARTIAL` / `BROKEN`) | Notes |
|---|---|---|
| Module ZIP flash & clean boot | | |
| Companion APK root connection | | |
| `kgx-core` daemon & Scene FPS Overlay | | |
| Whole-system Device Spoof | | |
| Zygisk Stock-Identity Shield & Denylist | | |
| 120Hz / Max Refresh Rate retention & recovery | | |
| Thermal Guard / Sweet-Spot / Bypass Charging | | |
| External Display Screen-Off / Resolution Override | | |

## 3. Diagnostic Output (`kgxctl diag`)
```text
(Run `su -c "/data/adb/modules/ksu_ultimate_gaming_x/bin/kgxctl diag"` and paste output here)
```
