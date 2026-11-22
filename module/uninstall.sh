#!/system/bin/sh
# KSU Ultimate Gaming X - Clean Uninstall & Full Rollback Script

MODDIR="${0%/*}"
[ "$MODDIR" = "$0" ] && MODDIR="."
export KGX_MODDIR="${KGX_MODDIR:-$MODDIR}"
export KGX_DATA_DIR="${KGX_DATA_DIR:-/data/adb/ksu_gaming_x}"

if [ -f "$KGX_MODDIR/lib/common.sh" ]; then
    . "$KGX_MODDIR/lib/common.sh"
    . "$KGX_MODDIR/lib/spoof.sh"
    . "$KGX_MODDIR/lib/display.sh"
    . "$KGX_MODDIR/lib/fps.sh"
    . "$KGX_MODDIR/lib/cpu_gpu.sh"
    . "$KGX_MODDIR/lib/ram.sh"
    . "$KGX_MODDIR/lib/touch.sh"
    . "$KGX_MODDIR/lib/network.sh"
    . "$KGX_MODDIR/lib/thermal.sh"
    . "$KGX_MODDIR/lib/power.sh"
    . "$KGX_MODDIR/lib/gos.sh"
    . "$KGX_MODDIR/lib/freezer.sh"

    kgx_init_dirs
    kgx_load_config

    # Stop background daemon cleanly
    PID_FILE="$KGX_DATA_DIR/state/daemon.pid"
    if [ -f "$PID_FILE" ]; then
        dpid="$(cat "$PID_FILE" 2>/dev/null)"
        if [ -n "$dpid" ] && [ "$dpid" -gt 0 ] 2>/dev/null; then
            kill "$dpid" 2>/dev/null || true
            sleep 1
            kill -9 "$dpid" 2>/dev/null || true
        fi
    fi

    # Full rollback of all subsystems in safe reverse order
    gos_restore 2>/dev/null || true
    network_restore 2>/dev/null || true
    touch_restore 2>/dev/null || true
    freezer_unfreeze_all 2>/dev/null || true
    power_bypass_restore 2>/dev/null || true
    ram_restore 2>/dev/null || true
    thermal_unlock_sysfs_ceilings 2>/dev/null || true
    thermal_restore_unlock 2>/dev/null || true
    cpu_gpu_restore 2>/dev/null || true
    display_res_reset 1 2>/dev/null || true
    display_internal_power_on 2>/dev/null || true
    display_restore 2>/dev/null || true
    fps_restore_all 2>/dev/null || true
    spoof_clear_system_prop 2>/dev/null || true
    spoof_restore 0 2>/dev/null || true
    sysfs_restore_all 2>/dev/null || true

    kgx_log "INFO" "uninstall" "Full subsystem rollback complete; removing $KGX_DATA_DIR."
fi

# Clean up persistent module data unless user explicitly kept backups
if [ "${KEEP_BACKUPS_ON_UNINSTALL:-0}" = "1" ] && [ -d "$KGX_DATA_DIR/backups" ]; then
    rm -rf "$KGX_DATA_DIR/config" "$KGX_DATA_DIR/state" "$KGX_DATA_DIR/logs" "$KGX_DATA_DIR/profiles" 2>/dev/null || true
else
    rm -rf "$KGX_DATA_DIR" 2>/dev/null || true
fi

exit 0
