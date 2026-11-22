# Security Policy & Safety Boundaries

## Supported Versions

| Version | Status | Notes |
|---|---|---|
| `v1.0.0` | Supported | First public release |

## Non-Negotiable Safety Boundaries

KSU Ultimate Gaming X operates with root privileges via KernelSU and Zygisk. To protect user security, hardware, and account integrity, the codebase enforces strict hard guards:

1. **Never modifies hardware identity or bootloader/verified-boot state**:
   - `spoof_set_prop_safe()` in `module/lib/spoof.sh` and `isSecuritySensitiveProp()` in `companion/zygisk-spoof/src/main.cpp` explicitly block touching `ro.serialno`, `ro.boot.*`, `ro.crypto.*`, `ro.debuggable`, `ro.secure`, `ro.adb.secure`, IMEI, or MAC addresses.
   - `ro.build.fingerprint` is excluded from `system.prop` and restored to stock when dirty.
2. **Never touches protected/critical kernel sysfs nodes**:
   - `kgx_is_protected_sysfs()` in `module/lib/common.sh` blocks writes to hardware silicon thermal trip points (`trip_point_*`), SError-prone `gpu_ifpo_control` (`*ifpo*`), SELinux nodes, or out-of-range frequency writes.
3. **Never uses destructive global kills or anti-cheat/attestation bypasses**:
   - Does not execute `am kill-all`, `cmd netpolicy`, or game memory/anti-cheat tampering.
   - Zygisk Stock-Identity Shield only restores genuine stock device properties for Google Services / Settings / user-selected denylist packages rather than spoofing hardware attestation keys.
4. **Diagnostic redaction (`kgxctl diag`)**:
   - Automatically masks serial numbers, 15+ digit IDs, MAC addresses, private IPv4 addresses, emails, tokens, and passwords before exporting reports.
5. **Local signing key isolation**:
   - `.gitignore` excludes `*.keystore`, `*.jks`, `*.idsig`, `dist/`, and generated `module/system.prop`. For custom/production APK releases, configure `KGX_KEYSTORE_PATH`, `KGX_KEYSTORE_PASS`, `KGX_KEY_PASS`, and `KGX_KEY_ALIAS` via environment variables instead of committing any keystore.

## Reporting a Vulnerability or Unsafe Behaviour

- Do **NOT** post unredacted logs containing serial numbers, tokens, IP addresses, or IMEIs in public issues.
- Run `kgxctl diag` to verify sensitive fields are replaced with `[REDACTED_*]` before sharing logs.
- For public bugs that do not expose sensitive exploit details, open an issue at: https://github.com/hangothanhh/ksu-ultimate-gaming-x/issues
- For security-sensitive root/privilege/crash findings where public disclosure puts users at risk, contact maintainer `hangothanhh` privately or summarize only minimal reproduction steps without exploit payloads until a patch is available.
