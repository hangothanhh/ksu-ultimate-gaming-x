#!/system/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# KSU Ultimate Gaming X - Unified Game Session Activation & Clean Rollback Orchestrator

session_get_foreground_pkg() {
    local pkg=""
    command -v dumpsys >/dev/null 2>&1 || return 0

    pkg="$(dumpsys activity activities 2>/dev/null | awk '
        /topResumedActivity=|mResumedActivity=|ResumedActivity:/ {
            if (match($0, /[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+\//)) {
                s = substr($0, RSTART, RLENGTH - 1)
                print s; exit
            }
        }')"
    if [ -z "$pkg" ]; then
        pkg="$(dumpsys window windows 2>/dev/null | awk '
            /mCurrentFocus=|mFocusedApp=/ {
                if (match($0, /[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+\//)) {
                    s = substr($0, RSTART, RLENGTH - 1)
                    print s; exit
                }
            }')"
    fi
    printf '%s\n' "$pkg"
}

session_is_screen_awake() {
    local pwr=""
    command -v dumpsys >/dev/null 2>&1 || return 0
    pwr="$(dumpsys power 2>/dev/null | grep -E 'mWakefulness=|Display Power:' | head -n 5)"
    [ -z "$pwr" ] && return 0
    case "$pwr" in
        *Asleep*|*Dozing*|*OFF*) return 1 ;;
        *) return 0 ;;
    esac
}

session_get_pid() {
    local pkg="$1"
    local pid="" cdir cmd
    if command -v pidof >/dev/null 2>&1; then
        pid="$(pidof -s "$pkg" 2>/dev/null || pidof "$pkg" 2>/dev/null | awk '{print $1}')"
        [ -n "$pid" ] && { printf '%s\n' "$pid"; return 0; }
        [ "$KGX_PROC_ROOT" = "/proc" ] && return 1
    fi
    for cdir in "$KGX_PROC_ROOT"/[0-9]*; do
        [ -r "$cdir/cmdline" ] || continue
        cmd="$(kgx_read_cmdline "$cdir/cmdline" | awk '{print $1}')"
        if [ "$cmd" = "$pkg" ]; then
            pid="${cdir##*/}"
            printf '%s\n' "$pid"
            return 0
        fi
    done
    return 1
}

session_should_optimize_pkg() {
    local pkg="$1"
    local crow brow c_en

    kgx_sanitize_pkg "$pkg" || return 1
    crow="$(matcher_get_custom_game_row "$pkg")"
    if [ -n "$crow" ]; then
        c_en="$(printf '%s\n' "$crow" | cut -f2)"
        [ "$c_en" = "1" ] && return 0 || return 1
    fi
    brow="$(matcher_get_builtin_game_row "$pkg")"
    [ -n "$brow" ] && return 0
    return 1
}

session_activate() {
    local pkg="$1"
    local gline g_name g_prof g_tfps g_mode g_dhz g_tprof g_net g_nfp g_dscale g_wres="default"
    local temps batt_c cpu_c gpu_c therm_eval stage mode_cap eff_mode eff_fps req_hz game_pid relief=0
    local start_ts

    kgx_sanitize_pkg "$pkg" || return 1
    kgx_load_config

    if [ "${SAFE_MODE:-0}" = "1" ]; then
        kgx_log "WARN" "session" "Skipped activation for $pkg because SAFE_MODE=1."
        return 1
    fi

    # Ensure immutable stock baseline exists before touching anything
    hw_load
    spoof_capture_original
    display_capture_original

    gline="$(matcher_get_effective_game "$pkg")"
    local _s
    IFS='	' read -r _s g_name _s g_prof g_tfps g_mode g_dhz g_tprof g_net _s _s g_nfp _s _s _s _s _s g_dscale g_wres <<EOF
$gline
EOF
    [ -n "$g_dscale" ] || g_dscale="1.0"
    [ -n "$g_wres" ] || g_wres="default"

    # 0. Apply per-game wm_res immediately (0ms perceived res change, before slower sysfs/RAM hooks)
    if [ "$g_wres" != "default" ]; then
        local active_res_src=""
        if [ -f "$KGX_DATA_DIR/state/active_res.env" ]; then
            active_res_src="$(awk -F '=' '$1=="ACTIVE_RES_SOURCE"{gsub(/'\''/, "", $2); print $2}' "$KGX_DATA_DIR/state/active_res.env" 2>/dev/null)"
        fi
        if [ "$active_res_src" != "global" ]; then
            display_res_apply "$g_wres" "auto" "game" || true
        fi
    fi

    # Thermal check prior to applying mode/FPS
    stage="NORMAL"
    eff_mode="$g_mode"
    temps="$(thermal_read_temps)"
    IFS='|' read -r batt_c cpu_c gpu_c <<EOF
$temps
EOF
    if [ "${SUSTAINED_SWEET_SPOT:-0}" = "1" ]; then
        therm_eval="$(thermal_evaluate_stage "$batt_c" "$cpu_c" "SWEET_SPOT" "$gpu_c")"
        IFS='|' read -r stage _s _s <<EOF
$therm_eval
EOF
        [ "$stage" = "SWEET_SPOT_COOL" ] && relief=1
    elif [ "${THERMAL_UNLOCK:-0}" = "1" ]; then
        therm_eval="$(thermal_evaluate_stage "$batt_c" "$cpu_c" "UNLOCKED" "$gpu_c")"
        IFS='|' read -r stage _s _s <<EOF
$therm_eval
EOF
        [ "$stage" = "UNLOCKED_COOL" ] && relief=1
    elif [ "${THERMAL_GUARD_ENABLED:-1}" = "1" ]; then
        therm_eval="$(thermal_evaluate_stage "$batt_c" "$cpu_c" "NORMAL" "$gpu_c")"
        IFS='|' read -r stage _s mode_cap <<EOF
$therm_eval
EOF
        eff_mode="$(thermal_cap_mode "$g_mode" "$mode_cap")"
    fi
    printf '%s\n' "$stage" > "$KGX_DATA_DIR/state/thermal_stage.state"

    # 1. Ensure Whole-System Persistent Spoof is active if enabled globally
    if [ "${SPOOF_ENABLED:-1}" = "1" ]; then
        spoof_apply "$pkg" "$g_prof" "$g_nfp"
    fi

    # 2. Effective FPS, Resolution Downscale & Display Hz
    eff_fps="$(fps_get_effective "$pkg" "$g_tfps" "$stage")"
    fps_apply "$pkg" "$eff_fps" "$eff_mode" "$g_dscale"

    if [ "$g_dhz" = "auto" ] || [ -z "$g_dhz" ]; then
        display_apply "$eff_fps" "auto"
    else
        display_apply "$g_dhz" "explicit"
    fi

    # 2B. Optional Peak Thermal Unlock or Sustained Sweet-Spot Ceilings
    if [ "${THERMAL_UNLOCK:-0}" = "1" ] || [ "${SUSTAINED_SWEET_SPOT:-0}" = "1" ]; then
        thermal_apply_unlock
    fi

    # 2C. Safe Bypass Charging (when plugged in and batt >= BYPASS_MIN_PCT)
    if command -v power_bypass_apply >/dev/null 2>&1; then
        power_bypass_apply
    fi

    # 3. CPU, GPU, Bus, I/O & game PID + render-thread priority
    game_pid="$(session_get_pid "$pkg" 2>/dev/null || true)"
    cpu_gpu_apply "$eff_mode" "$game_pid" "$relief"

    # 4. RAM, Freezer, Touch & Network
    ram_apply "$eff_mode" "$pkg"
    if [ "${FREEZER_ENABLED:-0}" = "1" ] && command -v freezer_sync >/dev/null 2>&1; then
        freezer_sync "$pkg" || true
    fi
    touch_apply "$g_tprof"
    if [ "$g_net" = "1" ]; then
        network_apply "$pkg"
    fi

    start_ts="$(date '+%s' 2>/dev/null || printf '0')"
    cat > "$KGX_DATA_DIR/state/active_session.env" <<EOF
ACTIVE_PKG='$pkg'
ACTIVE_NAME='$g_name'
ACTIVE_BASE_MODE='$g_mode'
ACTIVE_BASE_FPS='$g_tfps'
ACTIVE_MODE='$eff_mode'
ACTIVE_FPS='$eff_fps'
ACTIVE_DOWNSCALE='$g_dscale'
ACTIVE_WM_RES='$g_wres'
ACTIVE_SPOOF_PROFILE='$g_prof'
ACTIVE_START_TS='$start_ts'
ACTIVE_PID='$game_pid'
EOF
    kgx_log "INFO" "session" "Activated session for $g_name ($pkg): mode=$eff_mode, fps=$eff_fps, downscale=$g_dscale, wm_res=$g_wres, spoof=$g_prof, thermal=$stage"
    return 0
}

session_deactivate() {
    local reason="${1:-game_exit}"
    local active_file="$KGX_DATA_DIR/state/active_session.env"
    local old_pkg="none"

    if [ -f "$active_file" ]; then
        . "$active_file"
        old_pkg="${ACTIVE_PKG:-none}"
    fi

    # Reset per-game wm size/density FIRST before slower sysfs/proc restores
    if [ -f "$KGX_DATA_DIR/state/active_res.env" ]; then
        if grep -q "ACTIVE_RES_SOURCE='game'" "$KGX_DATA_DIR/state/active_res.env" 2>/dev/null; then
            display_res_reset 0
        fi
    fi

    network_restore
    touch_restore
    command -v freezer_unfreeze_all >/dev/null 2>&1 && freezer_unfreeze_all || true
    command -v power_bypass_restore >/dev/null 2>&1 && power_bypass_restore || true
    ram_restore
    thermal_restore_unlock
    cpu_gpu_restore
    display_restore
    case "$reason" in
        full_rollback|safe_mode_on|safe_mode_enabled)
            fps_restore_all 1
            spoof_restore 0
            ;;
        *)
            fps_restore_all 0
            spoof_restore 1
            ;;
    esac

    rm -f "$active_file" "$KGX_DATA_DIR/state/thermal_stage.state" "$KGX_DATA_DIR/state/live_fps.env" "$KGX_DATA_DIR/state/soft_step.tier" 2>/dev/null || true
    kgx_log "INFO" "session" "Deactivated session ($old_pkg, reason=$reason); stock system state restored."
    return 0
}
