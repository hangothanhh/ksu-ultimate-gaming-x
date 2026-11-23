#!/system/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# KSU Ultimate Gaming X - Auto Game Detection & Thermal Monitoring Daemon (v1.0.0)

MODDIR="${0%/*}/.."
[ -d "$MODDIR/lib" ] || MODDIR="${KGX_MODDIR:-/data/adb/modules/ksu_ultimate_gaming_x}"
export KGX_MODDIR="${KGX_MODDIR:-$MODDIR}"
export KGX_DATA_DIR="${KGX_DATA_DIR:-/data/adb/ksu_gaming_x}"

# Delegate directly to compiled ARM64 Rust native daemon when running on Android aarch64
if [ -z "${KGX_DISABLE_RUST_CORE:-}" ] && [ -x "$KGX_MODDIR/bin/kgx-core" ] && [ "$(uname -m 2>/dev/null)" = "aarch64" ]; then
    exec "$KGX_MODDIR/bin/kgx-core" daemon
fi

. "$KGX_MODDIR/lib/common.sh"
. "$KGX_MODDIR/lib/hw_detect.sh"
. "$KGX_MODDIR/lib/matcher.sh"
. "$KGX_MODDIR/lib/spoof.sh"
. "$KGX_MODDIR/lib/fps.sh"
. "$KGX_MODDIR/lib/cpu_gpu.sh"
. "$KGX_MODDIR/lib/ram.sh"
. "$KGX_MODDIR/lib/touch.sh"
. "$KGX_MODDIR/lib/display.sh"
. "$KGX_MODDIR/lib/thermal.sh"
. "$KGX_MODDIR/lib/power.sh"
. "$KGX_MODDIR/lib/network.sh"
. "$KGX_MODDIR/lib/session.sh"

kgx_init_dirs
kgx_load_config

PID_FILE="$KGX_DATA_DIR/state/daemon.pid"

# Single-instance guard (also clean any zombie duplicates across soft-reboot)
if [ -f "$PID_FILE" ]; then
    old_pid="$(cat "$PID_FILE" 2>/dev/null)"
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
        exit 0
    fi
fi
kgx_kill_stale_daemons
printf '%s\n' "$$" > "$PID_FILE"

cleanup_daemon() {
    session_deactivate "daemon_stop" 2>/dev/null || true
    [ -f "$KGX_DATA_DIR/state/active_display.env" ] && display_restore 2>/dev/null || true
    rm -f "$PID_FILE" 2>/dev/null || true
    exit 0
}
trap cleanup_daemon TERM INT HUP EXIT

hw_load
spoof_capture_original
display_capture_original

kgx_log "INFO" "daemon" "gaming_daemon started (pid=$$, hw=${REAL_MODEL:-unknown}, gpu=${GPU_VENDOR:-unknown})"

active_pkg=""
away_since=0

while true; do
    kgx_load_config

    if [ "${SAFE_MODE:-0}" = "1" ] || [ "${AUTO_OPTIMIZE:-1}" != "1" ]; then
        if [ -n "$active_pkg" ]; then
            session_deactivate "safe_or_disabled"
            active_pkg=""
            away_since=0
        fi
        sleep "${POLL_INTERVAL_IDLE:-3}"
        continue
    fi

    if ! session_is_screen_awake; then
        if [ -n "$active_pkg" ]; then
            session_deactivate "screen_off"
            active_pkg=""
            away_since=0
        fi
        sleep 8
        continue
    fi

    fg_pkg="$(session_get_foreground_pkg 2>/dev/null || true)"

    if [ -n "$fg_pkg" ] && session_should_optimize_pkg "$fg_pkg"; then
        away_since=0
        if [ "$fg_pkg" != "$active_pkg" ]; then
            if [ -n "$active_pkg" ]; then
                session_deactivate "switch_game"
            fi
            if session_activate "$fg_pkg"; then
                active_pkg="$fg_pkg"
            fi
        else
            if [ -f "$KGX_DATA_DIR/state/active_session.env" ]; then
                . "$KGX_DATA_DIR/state/active_session.env"
                thermal_monitor_step "$active_pkg" "${ACTIVE_BASE_MODE:-high_performance}" "${ACTIVE_BASE_FPS:-60}" "${ACTIVE_PID:-}"
            fi
        fi
        sleep "${POLL_INTERVAL_ACTIVE:-2}"
    else
        if [ -n "$active_pkg" ]; then
            now_ts="$(date '+%s' 2>/dev/null || printf '0')"
            if [ "$away_since" -eq 0 ] 2>/dev/null; then
                away_since="$now_ts"
            fi
            elapsed=$((now_ts - away_since))
            if [ "$elapsed" -ge "${EXIT_DEBOUNCE_SEC:-3}" ] 2>/dev/null; then
                session_deactivate "left_foreground"
                active_pkg=""
                away_since=0
            fi
        fi
        sleep "${POLL_INTERVAL_IDLE:-3}"
    fi
done
