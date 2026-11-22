## Summary of Changes
- What changed?
- Why is this change needed?

## Modified Files
- ...

## Verification Performed
- [ ] `python -u tests/verify_all.py` (or `--skip-apk` on Linux) passes 100%
- [ ] `python -u scripts/build_zip.py` packages cleanly with LF line endings
- [ ] Physical device testing (specify model, Android, KernelSU if tested; if mock-only, state so clearly):

## Compatibility, License & Rollback Impact
- I agree that contributions in this Pull Request are licensed under **GNU GPL v3.0 or later (`GPL-3.0-or-later`)**
- Does this touch `global.conf`, `orig_*.env`, `system.prop`, or `zygisk/arm64-v8a.so`?
- Does toggling `SAFE_MODE=1` or uninstalling the module restore stock state cleanly?

## AI Transparency & Anti-"AI Slop" Checklist (Required)
- [ ] I confirm this PR does NOT contain unreviewed bulk AI-generated code ("AI slop"), unverified `sysfs`/prop tweaks, or fabricated device compatibility claims.
- AI involvement level:
  - [ ] No AI used
  - [ ] AI-assisted — I personally reviewed every line of the diff and ran all tests
- Which parts were ONLY mock-tested or remain untested on real hardware?
