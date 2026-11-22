#!/system/bin/sh
# KSU Ultimate Gaming X - Manager Action Button Handler

MODDIR="${0%/*}"
[ "$MODDIR" = "$0" ] && MODDIR="."
export KGX_MODDIR="${KGX_MODDIR:-$MODDIR}"
export KGX_DATA_DIR="${KGX_DATA_DIR:-/data/adb/ksu_gaming_x}"

. "$KGX_MODDIR/lib/common.sh"
kgx_init_dirs
kgx_load_config

printf '========================================\n'
printf ' KSU Ultimate Gaming X - Quick Action\n'
printf '========================================\n'

if [ -f "$KGX_DATA_DIR/state/hw_profile.env" ]; then
    . "$KGX_DATA_DIR/state/hw_profile.env"
fi

printf 'Real Device : %s (%s)\n' "${REAL_MODEL:-unknown}" "${REAL_DEVICE:-unknown}"
printf 'GPU / MaxHz : %s / %s Hz\n' "${GPU_VENDOR:-unknown}" "${DISPLAY_MAX_HZ:-60}"
printf 'Safe Mode   : %s\n' "${SAFE_MODE:-0}"

if [ -f "$KGX_DATA_DIR/state/active_session.env" ]; then
    . "$KGX_DATA_DIR/state/active_session.env"
    printf 'Active Game : %s (Mode=%s, FPS=%s)\n' "${ACTIVE_PKG:-none}" "${ACTIVE_MODE:-none}" "${ACTIVE_FPS:-0}"
else
    printf 'Active Game : Idle (Stock state)\n'
fi

if [ "${SAFE_MODE:-0}" = "1" ]; then
    kgx_set_config "SAFE_MODE" "0"
    printf 'Action      : Cleared SAFE_MODE -> starting daemon...\n'
    sh "$KGX_MODDIR/bin/kgxctl" daemon start >/dev/null 2>&1 || true
    exit 0
fi

if sh "$KGX_MODDIR/bin/kgxctl" daemon status | grep -q '"running":true'; then
    printf 'Daemon      : Running -> triggering immediate clean restore & restart\n'
    sh "$KGX_MODDIR/bin/kgxctl" rollback >/dev/null 2>&1 || true
    sh "$KGX_MODDIR/bin/kgxctl" daemon restart >/dev/null 2>&1 || true
else
    printf 'Daemon      : Stopped -> starting daemon\n'
    sh "$KGX_MODDIR/bin/kgxctl" daemon start >/dev/null 2>&1 || true
fi

exit 0
