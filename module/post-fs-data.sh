#!/system/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# KSU Ultimate Gaming X - post-fs-data stage (v1.0.0)
# Must remain fast (<200ms) and safe. Handles bootloop guard & safe whole-system spoof.

MODDIR="${0%/*}"
[ "$MODDIR" = "$0" ] && MODDIR="."
export KGX_MODDIR="${KGX_MODDIR:-$MODDIR}"
export KGX_DATA_DIR="${KGX_DATA_DIR:-/data/adb/ksu_gaming_x}"

. "$KGX_MODDIR/lib/common.sh"
. "$KGX_MODDIR/lib/hw_detect.sh"
. "$KGX_MODDIR/lib/matcher.sh"
. "$KGX_MODDIR/lib/spoof.sh"

kgx_init_dirs

# Terminate any leftover gaming_daemon processes from prior temproot/soft-reboot sessions
kgx_kill_stale_daemons

# Clear stale runtime locks/session flags from any prior unclean shutdown
rm -f \
    "$KGX_DATA_DIR/state/daemon.pid" \
    "$KGX_DATA_DIR/state/active_session.env" \
    "$KGX_DATA_DIR/state/active_spoof.env" \
    "$KGX_DATA_DIR/state/thermal_stage.state" \
    "$KGX_DATA_DIR/state/live_status.json" \
    "$KGX_DATA_DIR/state/zygisk_rules.conf" 2>/dev/null || true

# Bootloop protection counter: reset in service.sh once sys.boot_completed=1
BOOT_COUNTER_FILE="$KGX_DATA_DIR/state/boot_counter"
count=0
if [ -f "$BOOT_COUNTER_FILE" ]; then
    raw_count="$(cat "$BOOT_COUNTER_FILE" 2>/dev/null)"
    case "$raw_count" in
        ''|*[!0-9]*) count=0 ;;
        *) count="$raw_count" ;;
    esac
fi

count=$((count + 1))
printf '%s\n' "$count" > "$BOOT_COUNTER_FILE"

kgx_load_config

if [ "$count" -ge 2 ]; then
    kgx_set_config "SAFE_MODE" "1"
    spoof_clear_system_prop
    spoof_restore 0
    kgx_log "WARN" "boot_guard" "Detected $count consecutive incomplete boots; enabled SAFE_MODE=1 and restored stock props."
elif [ "${SAFE_MODE:-0}" = "1" ]; then
    spoof_clear_system_prop
    spoof_restore 0
elif [ "${SPOOF_ENABLED:-1}" = "1" ]; then
    spoof_apply_global_persistent "${GLOBAL_SPOOF_PROFILE:-realme_14_5g}"
else
    spoof_clear_system_prop
fi

exit 0
