#!/system/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# KSU Ultimate Gaming X - late_start service stage (v1.0.0)

MODDIR="${0%/*}"
[ "$MODDIR" = "$0" ] && MODDIR="."
export KGX_MODDIR="${KGX_MODDIR:-$MODDIR}"
export KGX_DATA_DIR="${KGX_DATA_DIR:-/data/adb/ksu_gaming_x}"

. "$KGX_MODDIR/lib/common.sh"
. "$KGX_MODDIR/lib/hw_detect.sh"
. "$KGX_MODDIR/lib/matcher.sh"
. "$KGX_MODDIR/lib/spoof.sh"
. "$KGX_MODDIR/lib/display.sh"
. "$KGX_MODDIR/lib/network.sh"
. "$KGX_MODDIR/lib/fps.sh"
. "$KGX_MODDIR/lib/cpu_gpu.sh"
. "$KGX_MODDIR/lib/ram.sh"
. "$KGX_MODDIR/lib/touch.sh"
. "$KGX_MODDIR/lib/thermal.sh"
. "$KGX_MODDIR/lib/power.sh"
. "$KGX_MODDIR/lib/gos.sh"
. "$KGX_MODDIR/lib/freezer.sh"

kgx_init_dirs

# Wait for Android boot completion (bounded 120s timeout)
wait_sec=0
while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ]; do
    [ "$wait_sec" -ge 120 ] && break
    sleep 1
    wait_sec=$((wait_sec + 1))
done

# Boot completed cleanly -> reset bootloop guard counter
printf '0\n' > "$KGX_DATA_DIR/state/boot_counter"

kgx_load_config

# Detect hardware capabilities and recover any interrupted session before capturing baseline
hw_detect_all
freezer_unfreeze_all 2>/dev/null || true
display_internal_power_on 2>/dev/null || true
if [ -f "$KGX_DATA_DIR/state/active_res.env" ] && grep -q "ACTIVE_RES_SOURCE='game'" "$KGX_DATA_DIR/state/active_res.env" 2>/dev/null; then
    display_res_reset 0 2>/dev/null || true
fi
display_recover_on_boot 2>/dev/null || true
if [ -f "$KGX_DATA_DIR/state/active_session.env" ] || [ -f "$KGX_DATA_DIR/state/orig_thermal_unlock.env" ]; then
    thermal_restore_unlock 2>/dev/null || true
fi
rm -f "$KGX_DATA_DIR/state/active_session.env" "$KGX_DATA_DIR/state/active_display.env" "$KGX_DATA_DIR/state/thermal_stage.state" "$KGX_DATA_DIR/state/live_fps.env" "$KGX_DATA_DIR/state/soft_step.tier" 2>/dev/null || true
spoof_capture_original
display_capture_original

kgx_log "INFO" "service" "Boot sequence ready (API=${REAL_ANDROID_API:-?}, GPU=${GPU_VENDOR:-?}, MaxHz=${DISPLAY_MAX_HZ:-60}, SAFE_MODE=${SAFE_MODE:-0})"

if [ "${SAFE_MODE:-0}" = "1" ]; then
    kgx_log "WARN" "service" "SAFE_MODE=1 active; ensuring stock settings and skipping daemon startup."
    spoof_restore 0
    display_res_reset 1
    display_restore
    display_internal_power_on
    gos_restore
    network_restore
    fps_restore_all 1
    thermal_restore_unlock
    cpu_gpu_restore
    ram_restore
    touch_restore
    power_bypass_restore
    exit 0
fi

fps_sync_custom_downscales 2>/dev/null || true

if [ "${SPOOF_ENABLED:-1}" = "1" ]; then
    spoof_apply_global_persistent "${GLOBAL_SPOOF_PROFILE:-realme_14_5g}"
fi

if [ "${GOS_NEUTRALIZE:-0}" = "1" ]; then
    gos_apply
fi

display_ext_sync 2>/dev/null || true
display_res_sync 2>/dev/null || true

if [ "${AUTO_OPTIMIZE:-1}" = "1" ]; then
    sh "$KGX_MODDIR/bin/gaming_daemon.sh" >/dev/null 2>&1 &
    kgx_log "INFO" "service" "Started gaming_daemon.sh in background."
else
    kgx_log "INFO" "service" "AUTO_OPTIMIZE=0; daemon left stopped."
fi

exit 0
