#!/system/bin/sh
# KSU Ultimate Gaming X - Honest 5-Factor FPS Analyzer & Engine

fps_min() {
    if [ "$1" -le "$2" ] 2>/dev/null; then
        printf '%s\n' "$1"
    else
        printf '%s\n' "$2"
    fi
}

# Evaluates 5-factor FPS limits and emits JSON analysis
fps_analyze_json() {
    local pkg="$1"
    local req_fps="${2:-0}"
    local thermal_stage="${3:-NORMAL}"
    local spoof_active="${4:-0}"
    local gline g_ltype g_emax g_dtfps g_gload
    local disp_cap therm_cap hw_cap effective
    local whitelist_gated=0 limiter="NONE" can_unlock="false" reason=""

    hw_load
    gline="$(matcher_get_effective_game "$pkg")"
    local _s
    IFS='	' read -r _s _s _s _s g_dtfps _s _s _s _s g_emax g_ltype _s g_gload _s <<EOF
$gline
EOF

    [ "$req_fps" -gt 0 ] 2>/dev/null || req_fps="$g_dtfps"
    disp_cap="${DISPLAY_MAX_HZ:-60}"

    case "$thermal_stage" in
        CRITICAL) therm_cap=60 ;;
        HOT) therm_cap=90 ;;
        *) therm_cap=144 ;;
    esac

    # Hardware sustainable FPS advisory based on real HW_TIER & game GPU load
    hw_cap=144
    case "${HW_TIER:-2}:$g_gload" in
        1:extreme) hw_cap=60 ;;
        1:high)    hw_cap=90 ;;
        2:extreme) hw_cap=90 ;;
        2:high)    hw_cap=120 ;;
        3:extreme) hw_cap=120 ;;
        *)         hw_cap=144 ;;
    esac

    [ "$g_ltype" = "WHITELIST" ] && whitelist_gated=1

    effective="$req_fps"
    effective="$(fps_min "$effective" "$g_emax")"
    effective="$(fps_min "$effective" "$disp_cap")"
    effective="$(fps_min "$effective" "$therm_cap")"

    # Identify primary bottleneck honestly
    if [ "$therm_cap" -lt "$req_fps" ] && [ "$effective" -eq "$therm_cap" ]; then
        limiter="THERMAL_LIMIT"
        reason="Thermal stage $thermal_stage limits target FPS to $therm_cap FPS to prevent throttling/shutdown."
    elif [ "$disp_cap" -lt "$req_fps" ] && [ "$disp_cap" -le "$g_emax" ]; then
        limiter="DISPLAY_LIMIT"
        reason="Hardware display max refresh rate is ${disp_cap}Hz; cannot display >${disp_cap} FPS."
    elif [ "$req_fps" -gt "$g_emax" ] && [ "$g_ltype" = "GAME_CAP" ]; then
        limiter="GAME_LIMIT"
        reason="Game engine hard-caps Android at ${g_emax} FPS; device spoof cannot exceed engine cap."
    elif [ "$whitelist_gated" -eq 1 ] && [ "$spoof_active" != "1" ]; then
        limiter="WHITELIST_LIMIT"
        reason="Game gates >60 FPS behind a device whitelist. Enable Device Spoof profile (up to ${effective} FPS)."
        can_unlock="true"
    elif [ "$effective" -gt "$hw_cap" ]; then
        limiter="HARDWARE_LIMIT"
        reason="GPU/SoC tier (${HW_TIER:-2}) under '$g_gload' load may sustain ~${hw_cap} FPS even with ${effective} FPS unlocked."
        can_unlock="true"
    else
        limiter="NONE"
        if [ "$whitelist_gated" -eq 1 ]; then
            reason="Whitelist requirement satisfied via hardware-aligned spoof; targeting ${effective} FPS on ${disp_cap}Hz panel."
            can_unlock="true"
        else
            reason="Open FPS tier; targeting ${effective} FPS within ${disp_cap}Hz display and ${thermal_stage} thermal budget."
            can_unlock="true"
        fi
    fi

    printf '{'
    printf '"package":"%s",' "$(json_escape "$pkg")"
    printf '"requested_fps":%s,' "$req_fps"
    printf '"effective_fps":%s,' "$effective"
    printf '"game_engine_cap":%s,' "$g_emax"
    printf '"limit_type":"%s",' "$g_ltype"
    printf '"whitelist_gated":%s,' "$whitelist_gated"
    printf '"display_cap":%s,' "$disp_cap"
    printf '"hw_sustainable_fps":%s,' "$hw_cap"
    printf '"thermal_cap":%s,' "$therm_cap"
    printf '"primary_limiter":"%s",' "$limiter"
    printf '"can_unlock":%s,' "$can_unlock"
    printf '"explanation":"%s"' "$(json_escape "$reason")"
    printf '}\n'
}

fps_get_effective() {
    local pkg="$1"
    local req_fps="$2"
    local thermal_stage="${3:-NORMAL}"
    local gline g_emax disp_cap therm_cap eff

    hw_load
    gline="$(matcher_get_effective_game "$pkg")"
    local _s
    IFS='	' read -r _s _s _s _s _s _s _s _s _s g_emax _s <<EOF
$gline
EOF
    disp_cap="${DISPLAY_MAX_HZ:-60}"
    case "$thermal_stage" in
        CRITICAL) therm_cap=60 ;;
        HOT) therm_cap=90 ;;
        *) therm_cap=144 ;;
    esac

    eff="$req_fps"
    eff="$(fps_min "$eff" "$g_emax")"
    eff="$(fps_min "$eff" "$disp_cap")"
    eff="$(fps_min "$eff" "$therm_cap")"
    printf '%s\n' "$eff"
}

fps_is_pkg_running() {
    local pkg="$1"
    local pid=""
    if command -v pidof >/dev/null 2>&1; then
        pid="$(pidof -s "$pkg" 2>/dev/null || pidof "$pkg" 2>/dev/null | awk '{print $1}')"
        [ -n "$pid" ] && return 0
    fi
    return 1
}

fps_get_applied_state() {
    local pkg="$1"
    local st="$KGX_DATA_DIR/state/gamemgr_applied.tsv"
    [ -f "$st" ] || return 0
    awk -F '\t' -v p="$pkg" '$1==p{print $2 "|" $3 "|" $4; exit}' "$st" 2>/dev/null
}

fps_set_applied_state() {
    local pkg="$1" mode="$2" fps="$3" dscale="$4"
    local st="$KGX_DATA_DIR/state/gamemgr_applied.tsv"
    local tmp="$st.tmp.$$"
    mkdir -p "$KGX_DATA_DIR/state" 2>/dev/null || true
    if [ -f "$st" ]; then
        awk -F '\t' -v p="$pkg" '$1!=p' "$st" > "$tmp" 2>/dev/null || : > "$tmp"
    else
        : > "$tmp"
    fi
    printf '%s\t%s\t%s\t%s\n' "$pkg" "$mode" "$fps" "$dscale" >> "$tmp"
    mv "$tmp" "$st" 2>/dev/null || rm -f "$tmp" 2>/dev/null || true
}

fps_del_applied_state() {
    local pkg="$1"
    local st="$KGX_DATA_DIR/state/gamemgr_applied.tsv"
    local tmp="$st.tmp.$$"
    [ -f "$st" ] || return 0
    awk -F '\t' -v p="$pkg" '$1!=p' "$st" > "$tmp" 2>/dev/null || : > "$tmp"
    mv "$tmp" "$st" 2>/dev/null || rm -f "$tmp" 2>/dev/null || true
}

fps_apply() {
    local pkg="$1"
    local target_fps="$2"
    local mode="${3:-high_performance}"
    local downscale="${4:-1.0}"
    local list_file="$KGX_DATA_DIR/state/fps_active.list"

    [ "${FPS_ENGINE_ENABLED:-1}" = "1" ] || return 0
    kgx_sanitize_pkg "$pkg" || return 1
    kgx_sanitize_int "$target_fps" || return 1

    case "$downscale" in
        1.0|0.9|0.85|0.8|0.75) ;;
        *) downscale="1.0" ;;
    esac

    mkdir -p "$KGX_DATA_DIR/state" 2>/dev/null || true
    if [ ! -f "$list_file" ] || ! grep -qx "$pkg" "$list_file" 2>/dev/null; then
        printf '%s\n' "$pkg" >> "$list_file"
    fi

    # Never invoke cmd game / device_config while process is running: Android 12+
    # PlatformCompat.putOverridesOnReleaseBuilds unconditionally calls killUid().
    if fps_is_pkg_running "$pkg"; then
        kgx_log "INFO" "fps" "Preserved pre-applied GameManager state for running $pkg (target=${target_fps}fps, downscale=$downscale) to prevent Android PlatformCompat killUid."
        return 0
    fi

    fps_preapply_downscale "$pkg" 1 "$downscale" "$target_fps" "$mode" 0 || true
    kgx_log "INFO" "fps" "Pre-applied Android GameManager mode=$mode, target=${target_fps}fps, downscale=$downscale for $pkg (not running)."
    return 0
}

fps_preapply_downscale() {
    local pkg="$1" en="${2:-1}" dscale="${3:-1.0}" tfps="${4:-60}" mode="${5:-high_performance}" force="${6:-0}"
    local game_mode="performance" want="" prev="" prev_dscale=""

    kgx_sanitize_pkg "$pkg" || return 1
    case "$dscale" in
        1.0|0.9|0.85|0.8|0.75) ;;
        *) dscale="1.0" ;;
    esac
    case "$mode" in
        battery_gaming) game_mode="battery" ;;
        balanced) game_mode="standard" ;;
        *) game_mode="performance" ;;
    esac

    if [ "${SAFE_MODE:-0}" != "1" ] && [ "${FPS_ENGINE_ENABLED:-1}" = "1" ] && [ "$en" = "1" ]; then
        want="${game_mode}|${tfps}|${dscale}"
    else
        want="disabled"
    fi

    prev="$(fps_get_applied_state "$pkg")"
    [ "$want" = "$prev" ] && return 0
    [ "$want" = "disabled" ] && [ -z "$prev" ] && return 0

    if [ "$force" != "1" ] && [ "$KGX_PROC_ROOT" = "/proc" ] && fps_is_pkg_running "$pkg"; then
        kgx_log "INFO" "fps" "Deferred GameManager update for running $pkg (downscale=$dscale) until process closes to prevent PlatformCompat killUid."
        return 0
    fi

    if [ "$want" = "disabled" ]; then
        if command -v cmd >/dev/null 2>&1; then
            cmd game downscale disable "$pkg" >/dev/null 2>&1 || true
            cmd game mode standard "$pkg" >/dev/null 2>&1 || true
            cmd game reset "$pkg" >/dev/null 2>&1 || true
        fi
        command -v device_config >/dev/null 2>&1 && device_config delete game_overlay "$pkg" >/dev/null 2>&1 || true
        fps_del_applied_state "$pkg"
        return 0
    fi

    if [ "$dscale" != "1.0" ]; then
        # Set game_overlay & mode first, then cmd game downscale so Android 12
        # DeviceConfig listener does not overwrite DOWNSCALED=false afterwards.
        command -v device_config >/dev/null 2>&1 && device_config put game_overlay "$pkg" "mode=2,fps=$tfps,downscaleFactor=$dscale" >/dev/null 2>&1 || true
        if command -v cmd >/dev/null 2>&1; then
            cmd game mode "$game_mode" "$pkg" >/dev/null 2>&1 || true
            cmd game downscale "$dscale" "$pkg" >/dev/null 2>&1 || true
            cmd game set --mode 2 --fps "$tfps" --downscale "$dscale" "$pkg" >/dev/null 2>&1 || true
        fi
    else
        prev_dscale="${prev##*|}"
        if command -v cmd >/dev/null 2>&1 && [ -n "$prev_dscale" ] && [ "$prev_dscale" != "1.0" ]; then
            cmd game downscale disable "$pkg" >/dev/null 2>&1 || true
        fi
        command -v device_config >/dev/null 2>&1 && device_config delete game_overlay "$pkg" >/dev/null 2>&1 || true
        if command -v cmd >/dev/null 2>&1; then
            cmd game mode "$game_mode" "$pkg" >/dev/null 2>&1 || true
            cmd game set --mode 2 --fps "$tfps" "$pkg" >/dev/null 2>&1 || true
        fi
    fi

    fps_set_applied_state "$pkg" "$game_mode" "$tfps" "$dscale"
    return 0
}

fps_sync_custom_downscales() {
    local cfg="$KGX_DATA_DIR/config/custom_games.tsv"
    local line pkg en prof tfps mode dhz tprof net dscale wres
    [ -f "$cfg" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            ''|\#*) continue ;;
        esac
        IFS='	' read -r pkg en prof tfps mode dhz tprof net dscale wres <<EOF
$line
EOF
        kgx_sanitize_pkg "$pkg" || continue
        fps_preapply_downscale "$pkg" "${en:-1}" "${dscale:-1.0}" "${tfps:-60}" "${mode:-high_performance}" || true
    done < "$cfg"
    return 0
}

fps_restore() {
    local pkg="$1"
    local list_file="$KGX_DATA_DIR/state/fps_active.list"
    kgx_sanitize_pkg "$pkg" || return 1

    if [ "$KGX_PROC_ROOT" != "/proc" ] || ! fps_is_pkg_running "$pkg"; then
        if command -v cmd >/dev/null 2>&1; then
            cmd game downscale disable "$pkg" >/dev/null 2>&1 || true
            cmd game mode standard "$pkg" >/dev/null 2>&1 || true
            cmd game reset "$pkg" >/dev/null 2>&1 || true
        fi
        if command -v device_config >/dev/null 2>&1; then
            device_config delete game_overlay "$pkg" >/dev/null 2>&1 || true
        fi
    fi
    if [ -f "$list_file" ]; then
        grep -vx "$pkg" "$list_file" > "${list_file}.tmp.$$" 2>/dev/null || true
        mv "${list_file}.tmp.$$" "$list_file"
    fi
    fps_del_applied_state "$pkg"
    kgx_log "INFO" "fps" "Reset GameManager overlay/mode for $pkg"
}

fps_restore_all() {
    local clear_downscale="${1:-1}"
    local list_file="$KGX_DATA_DIR/state/fps_active.list"
    local state_tsv="$KGX_DATA_DIR/state/gamemgr_applied.tsv"
    local cfg="$KGX_DATA_DIR/config/custom_games.tsv"
    local pkg line seen_pkgs="" p

    if [ "$clear_downscale" != "1" ]; then
        rm -f "$list_file" 2>/dev/null || true
        kgx_log "INFO" "fps" "Cleared active FPS session tracking (preserved GameManager state to avoid background killUid)."
        return 0
    fi

    if [ -f "$list_file" ]; then
        while IFS= read -r pkg || [ -n "$pkg" ]; do
            [ -n "$pkg" ] || continue
            kgx_sanitize_pkg "$pkg" || continue
            case " $seen_pkgs " in
                *" $pkg "*) ;;
                *) seen_pkgs="$seen_pkgs $pkg" ;;
            esac
        done < "$list_file"
    fi

    if [ -f "$state_tsv" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in
                ''|\#*) continue ;;
            esac
            pkg="${line%%	*}"
            kgx_sanitize_pkg "$pkg" || continue
            case " $seen_pkgs " in
                *" $pkg "*) ;;
                *) seen_pkgs="$seen_pkgs $pkg" ;;
            esac
        done < "$state_tsv"
    fi

    if [ -f "$cfg" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in
                ''|\#*) continue ;;
            esac
            pkg="${line%%	*}"
            kgx_sanitize_pkg "$pkg" || continue
            case " $seen_pkgs " in
                *" $pkg "*) ;;
                *) seen_pkgs="$seen_pkgs $pkg" ;;
            esac
        done < "$cfg"
    fi

    for p in $seen_pkgs; do
        if command -v cmd >/dev/null 2>&1; then
            cmd game downscale disable "$p" >/dev/null 2>&1 || true
            cmd game mode standard "$p" >/dev/null 2>&1 || true
            cmd game reset "$p" >/dev/null 2>&1 || true
        fi
        if command -v device_config >/dev/null 2>&1; then
            device_config delete game_overlay "$p" >/dev/null 2>&1 || true
        fi
    done
    rm -f "$list_file" "$state_tsv" 2>/dev/null || true
    kgx_log "INFO" "fps" "Restored all active GameManager FPS entries."
}

fps_read_live() {
    local pkg="${1:-}"
    local fast="${2:-0}"
    local raw fps_val=""

    # 1. Check real kernel DRM measured_fps node (Snapdragon SDE / MTK)
    for node in \
        "$KGX_SYS_ROOT/class/drm/sde-crtc-0/measured_fps" \
        "$KGX_SYS_ROOT/class/drm/card0-DSI-1/measured_fps" \
        "$KGX_SYS_ROOT/class/graphics/fb0/measured_fps"; do
        if [ -r "$node" ]; then
            raw="$(cat "$node" 2>/dev/null | head -n 1)"
            fps_val="$(printf '%s\n' "$raw" | awk 'match($0, /[0-9]+(\.[0-9]+)?/) { split(substr($0, RSTART, RLENGTH), a, "."); print a[1]; exit }')"
            if [ -n "$fps_val" ] && [ "$fps_val" -gt 0 ] 2>/dev/null; then
                printf '%s\n' "$fps_val"
                return 0
            fi
        fi
    done

    [ "$fast" = "1" ] && { printf 'null\n'; return 0; }

    # 2. Fallback: parse framestats timestamps from dumpsys gfxinfo if game is active
    if [ -n "$pkg" ] && command -v dumpsys >/dev/null 2>&1; then
        fps_val="$(dumpsys gfxinfo "$pkg" framestats 2>/dev/null | awk -F ',' '
            /^[0-9]+,[0-9]+,/ && $2 ~ /^[0-9]+$/ {
                ts = $2 + 0
                if (ts > 1000000000) {
                    if (first == 0) first = ts
                    last = ts
                    cnt++
                }
            }
            END {
                if (cnt >= 5 && last > first) {
                    dur_s = (last - first) / 1000000000.0
                    if (dur_s > 0.05) {
                        fps = int((cnt - 1) / dur_s + 0.5)
                        if (fps >= 1 && fps <= 240) print fps
                    }
                }
            }')"
        if [ -n "$fps_val" ] && [ "$fps_val" -gt 0 ] 2>/dev/null; then
            printf '%s\n' "$fps_val"
            return 0
        fi
    fi

    printf 'null\n'
}
