#!/system/bin/sh
# KSU Ultimate Gaming X - Dynamic Display Refresh Rate Engine

display_sanitize_hz_val() {
    local raw="$1" max_hz="${2:-60}" cleaned=""
    cleaned="$(printf '%s' "$raw" | tr -d '\r\n ')"
    if [ -z "$cleaned" ] || [ "$cleaned" = "null" ]; then
        printf 'null\n'
        return 0
    fi
    kgx_sanitize_int "$max_hz" || max_hz=60
    printf '%s\n' "$cleaned" | awk -v mx="$max_hz" '
        {
            raw = $0
            if (raw !~ /^[0-9]+(\.[0-9]+)?$/) {
                print raw
                exit
            }
            v = raw + 0
            if (v <= 0) {
                print "null"
                exit
            }
            if (mx >= 60 && v > mx) {
                printf "%.1f\n", mx
                exit
            }
            iv = int(v)
            frac = v - iv
            if (v >= 30 && v <= 240 && frac > 0.01 && frac < 0.45) {
                printf "%.1f\n", iv
                exit
            }
            print raw
        }'
}

display_is_samsung_rrm() {
    local cur_sr=""
    [ "${SOC_VENDOR:-}" = "exynos" ] && return 0
    [ -d "$KGX_SYS_ROOT/class/sec" ] && return 0
    if command -v settings >/dev/null 2>&1; then
        cur_sr="$(settings get secure refresh_rate_mode 2>/dev/null | tr -d '\r\n ')"
        case "$cur_sr" in
            0|1|2) return 0 ;;
        esac
    fi
    return 1
}

display_migrate_original() {
    local orig_file="$KGX_DATA_DIR/state/orig_display.env"
    local has_sec_rrm=0 has_sys_rrm=0 tmp_orig=""
    local ORIG_SYS_PEAK="" ORIG_SYS_MIN="" ORIG_SYS_USER="" ORIG_SEC_USER="" ORIG_SEC_RRM="" ORIG_SYS_RRM=""
    local new_peak="" new_min="" peak_int=0 live_sr="" live_sys_rrm="" changed=0

    [ -f "$orig_file" ] && [ -s "$orig_file" ] || return 0
    hw_load

    grep -q '^ORIG_SEC_RRM=' "$orig_file" 2>/dev/null && has_sec_rrm=1
    grep -q '^ORIG_SYS_RRM=' "$orig_file" 2>/dev/null && has_sys_rrm=1
    . "$orig_file"

    new_peak="$(display_sanitize_hz_val "${ORIG_SYS_PEAK:-null}" "${DISPLAY_MAX_HZ:-60}")"
    new_min="$(display_sanitize_hz_val "${ORIG_SYS_MIN:-null}" "${DISPLAY_MAX_HZ:-60}")"
    [ "$new_peak" != "${ORIG_SYS_PEAK:-null}" ] && changed=1
    [ "$new_min" != "${ORIG_SYS_MIN:-null}" ] && changed=1

    peak_int="${new_peak%%.*}"
    kgx_sanitize_int "$peak_int" || peak_int=0

    if [ "$has_sec_rrm" -eq 0 ]; then
        changed=1
        if command -v settings >/dev/null 2>&1; then
            live_sr="$(settings get secure refresh_rate_mode 2>/dev/null | tr -d '\r\n ')"
        fi
        case "$live_sr" in
            1|2) ORIG_SEC_RRM="$live_sr" ;;
            0)
                if [ "$peak_int" -ge 90 ] 2>/dev/null; then
                    ORIG_SEC_RRM="1"
                else
                    ORIG_SEC_RRM="0"
                fi
                ;;
            *)
                if [ "$peak_int" -ge 90 ] 2>/dev/null; then
                    ORIG_SEC_RRM="1"
                else
                    ORIG_SEC_RRM="null"
                fi
                ;;
        esac
    elif { [ -z "${ORIG_SEC_RRM:-}" ] || [ "$ORIG_SEC_RRM" = "null" ]; } && [ "$peak_int" -ge 90 ] 2>/dev/null && display_is_samsung_rrm; then
        ORIG_SEC_RRM="1"
        changed=1
    fi

    if [ "$has_sys_rrm" -eq 0 ]; then
        changed=1
        if command -v settings >/dev/null 2>&1; then
            live_sys_rrm="$(settings get system refresh_rate_mode 2>/dev/null | tr -d '\r\n ')"
        fi
        case "$live_sys_rrm" in
            0|1|2) ORIG_SYS_RRM="$live_sys_rrm" ;;
            *) ORIG_SYS_RRM="null" ;;
        esac
    fi

    [ "$changed" -eq 0 ] && return 0

    tmp_orig="${orig_file}.tmp.$$"
    cat > "$tmp_orig" <<EOF
ORIG_SYS_PEAK='${new_peak:-null}'
ORIG_SYS_MIN='${new_min:-null}'
ORIG_SYS_USER='${ORIG_SYS_USER:-null}'
ORIG_SEC_USER='${ORIG_SEC_USER:-null}'
ORIG_SEC_RRM='${ORIG_SEC_RRM:-null}'
ORIG_SYS_RRM='${ORIG_SYS_RRM:-null}'
EOF
    mv "$tmp_orig" "$orig_file" 2>/dev/null || rm -f "$tmp_orig" 2>/dev/null
    kgx_log "INFO" "display" "Migrated orig_display.env (peak=${new_peak}, min=${new_min}, sec_rrm=${ORIG_SEC_RRM:-null}, sys_rrm=${ORIG_SYS_RRM:-null})."
}

display_capture_original() {
    local orig_file="$KGX_DATA_DIR/state/orig_display.env"
    local sys_peak="null" sys_min="null" sys_user="null" sec_user="null" sec_rrm="null" sys_rrm="null"
    local peak_int=0 min_int=0 tmp_orig=""

    hw_load
    if [ -f "$orig_file" ] && [ -s "$orig_file" ]; then
        display_migrate_original
        return 0
    fi
    if [ -f "$KGX_DATA_DIR/state/active_display.env" ]; then
        kgx_log "WARN" "display" "Skipped stock display snapshot while active_display.env exists."
        return 0
    fi
    mkdir -p "$KGX_DATA_DIR/state" 2>/dev/null || true

    if command -v settings >/dev/null 2>&1; then
        sys_peak="$(settings get system peak_refresh_rate 2>/dev/null | tr -d '\r\n ')"
        sys_min="$(settings get system min_refresh_rate 2>/dev/null | tr -d '\r\n ')"
        sys_user="$(settings get system user_refresh_rate 2>/dev/null | tr -d '\r\n ')"
        sec_user="$(settings get secure user_refresh_rate 2>/dev/null | tr -d '\r\n ')"
        sec_rrm="$(settings get secure refresh_rate_mode 2>/dev/null | tr -d '\r\n ')"
        sys_rrm="$(settings get system refresh_rate_mode 2>/dev/null | tr -d '\r\n ')"
    fi

    sys_peak="$(display_sanitize_hz_val "${sys_peak:-null}" "${DISPLAY_MAX_HZ:-60}")"
    sys_min="$(display_sanitize_hz_val "${sys_min:-null}" "${DISPLAY_MAX_HZ:-60}")"
    [ -n "$sys_user" ] || sys_user="null"
    [ -n "$sec_user" ] || sec_user="null"
    [ -n "$sec_rrm" ] || sec_rrm="null"
    [ -n "$sys_rrm" ] || sys_rrm="null"

    peak_int="${sys_peak%%.*}"
    min_int="${sys_min%%.*}"
    kgx_sanitize_int "$peak_int" || peak_int=0
    kgx_sanitize_int "$min_int" || min_int=0

    # Never snapshot a leftover stuck 60/60 lock as stock on a >=90Hz Seamless adaptive device
    if [ "${DISPLAY_MAX_HZ:-60}" -ge 90 ] 2>/dev/null && [ "$sec_rrm" = "1" ] && [ "$peak_int" -eq 60 ] && [ "$min_int" -eq 60 ]; then
        sys_peak="${DISPLAY_MAX_HZ}.0"
        sys_min="null"
        kgx_log "WARN" "display" "Detected stuck 60/60 settings with seamless 120Hz active; normalizing captured stock to ${sys_peak}/null."
    fi

    tmp_orig="${orig_file}.tmp.$$"
    cat > "$tmp_orig" <<EOF
ORIG_SYS_PEAK='${sys_peak}'
ORIG_SYS_MIN='${sys_min}'
ORIG_SYS_USER='${sys_user}'
ORIG_SEC_USER='${sec_user}'
ORIG_SEC_RRM='${sec_rrm}'
ORIG_SYS_RRM='${sys_rrm}'
EOF
    mv "$tmp_orig" "$orig_file" 2>/dev/null || rm -f "$tmp_orig" 2>/dev/null
    kgx_log "INFO" "display" "Captured stock display settings (peak=${sys_peak}, min=${sys_min}, sec_rrm=${sec_rrm})."
}

display_select_valid_hz() {
    local req_hz="${1:-60}"
    local chosen="" hz

    hw_load
    kgx_sanitize_int "$req_hz" || req_hz="${DISPLAY_MAX_HZ:-60}"

    for hz in $DISPLAY_SUPPORTED_HZ; do
        if [ "$hz" -ge "$req_hz" ] 2>/dev/null; then
            chosen="$hz"
            break
        fi
    done
    [ -n "$chosen" ] || chosen="${DISPLAY_MAX_HZ:-60}"
    printf '%s\n' "$chosen"
}

display_apply() {
    local req_hz="$1"
    local req_origin="${2:-}"
    local chosen="" was_auto=0 sys_rrm="" cur_peak="" cur_peak_int=0

    [ "${DISPLAY_AUTO_HZ:-1}" = "1" ] || return 0
    hw_load
    display_capture_original

    if [ "$req_hz" = "auto" ] || [ -z "$req_hz" ]; then
        was_auto=1
        req_hz="${DISPLAY_MAX_HZ:-60}"
    elif [ "$req_origin" = "auto" ]; then
        was_auto=1
    fi

    chosen="$(display_select_valid_hz "$req_hz")"

    # Never allow high-Hz requests on a >=90Hz panel to be squeezed down below 90Hz
    if [ "${DISPLAY_MAX_HZ:-60}" -ge 90 ] 2>/dev/null; then
        kgx_sanitize_int "$req_hz" || req_hz="${DISPLAY_MAX_HZ:-60}"
        if [ "$req_hz" -ge 90 ] 2>/dev/null && [ "${chosen:-0}" -lt 90 ] 2>/dev/null; then
            chosen="${DISPLAY_MAX_HZ}"
        fi
    fi

    mkdir -p "$KGX_DATA_DIR/state" 2>/dev/null || true
    printf 'ACTIVE_DISPLAY_HZ=%s\n' "$chosen" > "$KGX_DATA_DIR/state/active_display.env"

    if command -v settings >/dev/null 2>&1; then
        if [ "${chosen:-0}" -ge 90 ] 2>/dev/null; then
            if display_is_samsung_rrm; then
                settings put secure refresh_rate_mode 1 >/dev/null 2>&1 || true
                sys_rrm="$(settings get system refresh_rate_mode 2>/dev/null | tr -d '\r\n ')"
                [ -n "$sys_rrm" ] && [ "$sys_rrm" != "null" ] && settings put system refresh_rate_mode 1 >/dev/null 2>&1 || true
            fi
            settings put system peak_refresh_rate "$chosen" >/dev/null 2>&1 || true
            settings put system min_refresh_rate "$chosen" >/dev/null 2>&1 || true
        elif [ "${DISPLAY_MAX_HZ:-60}" -ge 90 ] 2>/dev/null && [ "$was_auto" -eq 1 ]; then
            # Auto 60fps on >=90Hz panel: never lower peak_refresh_rate to 60 so a hard reboot
            # cannot trap system-wide peak_refresh_rate=60.
            cur_peak="$(settings get system peak_refresh_rate 2>/dev/null | tr -dc '0-9.')"
            cur_peak_int="${cur_peak%%.*}"
            kgx_sanitize_int "$cur_peak_int" || cur_peak_int=0
            if [ "$cur_peak_int" -lt 90 ] 2>/dev/null; then
                settings put system peak_refresh_rate "${DISPLAY_MAX_HZ}.0" >/dev/null 2>&1 || true
            fi
            settings put system min_refresh_rate "$chosen" >/dev/null 2>&1 || true
        else
            settings put system min_refresh_rate "$chosen" >/dev/null 2>&1 || true
            settings put system peak_refresh_rate "$chosen" >/dev/null 2>&1 || true
        fi
    fi

    kgx_log "INFO" "display" "Switched display refresh rate to supported ${chosen}Hz (requested=$req_hz)"
    return 0
}

display_restore_setting() {
    local ns="$1" key="$2" orig="$3"
    command -v settings >/dev/null 2>&1 || return 0
    if [ -z "$orig" ] || [ "$orig" = "null" ]; then
        settings delete "$ns" "$key" >/dev/null 2>&1 || true
    else
        settings put "$ns" "$key" "$orig" >/dev/null 2>&1 || true
    fi
}

display_restore() {
    local orig_file="$KGX_DATA_DIR/state/orig_display.env"
    local rest_peak="deleted" rest_min="deleted" peak_int=0
    local ORIG_SYS_PEAK="" ORIG_SYS_MIN="" ORIG_SYS_USER="" ORIG_SEC_USER="" ORIG_SEC_RRM="" ORIG_SYS_RRM=""

    hw_load
    if [ -f "$orig_file" ] && [ -s "$orig_file" ]; then
        display_migrate_original
        . "$orig_file"
        rest_peak="$(display_sanitize_hz_val "${ORIG_SYS_PEAK:-null}" "${DISPLAY_MAX_HZ:-60}")"
        rest_min="$(display_sanitize_hz_val "${ORIG_SYS_MIN:-null}" "${DISPLAY_MAX_HZ:-60}")"
        peak_int="${rest_peak%%.*}"
        kgx_sanitize_int "$peak_int" || peak_int=0

        if [ -n "${ORIG_SEC_RRM:-}" ] && [ "$ORIG_SEC_RRM" != "null" ]; then
            display_restore_setting secure refresh_rate_mode "$ORIG_SEC_RRM"
        elif [ "$peak_int" -ge 90 ] 2>/dev/null && display_is_samsung_rrm; then
            display_restore_setting secure refresh_rate_mode 1
        fi
        if [ -n "${ORIG_SYS_RRM:-}" ] && [ "$ORIG_SYS_RRM" != "null" ]; then
            display_restore_setting system refresh_rate_mode "$ORIG_SYS_RRM"
        fi
        display_restore_setting system peak_refresh_rate "$rest_peak"
        display_restore_setting system min_refresh_rate "$rest_min"
        display_restore_setting system user_refresh_rate "${ORIG_SYS_USER:-null}"
        display_restore_setting secure user_refresh_rate "${ORIG_SEC_USER:-null}"
    else
        if command -v settings >/dev/null 2>&1; then
            settings delete system min_refresh_rate >/dev/null 2>&1 || true
            settings delete system peak_refresh_rate >/dev/null 2>&1 || true
        fi
    fi
    rm -f "$KGX_DATA_DIR/state/active_display.env" 2>/dev/null || true
    kgx_log "INFO" "display" "Restored stock display refresh rate settings (peak=${rest_peak}, min=${rest_min})."
    return 0
}

display_get_current_hz() {
    local cur=""
    if [ -f "$KGX_DATA_DIR/state/active_display.env" ]; then
        . "$KGX_DATA_DIR/state/active_display.env"
        [ -n "${ACTIVE_DISPLAY_HZ:-}" ] && { printf '%s\n' "$ACTIVE_DISPLAY_HZ"; return 0; }
    fi
    if command -v settings >/dev/null 2>&1; then
        cur="$(settings get system peak_refresh_rate 2>/dev/null | tr -dc '0-9.')"
        cur="${cur%%.*}"
        if [ -n "$cur" ] && [ "$cur" -gt 0 ] 2>/dev/null; then
            printf '%s\n' "$cur"
            return 0
        fi
    fi
    hw_load
    printf '%s\n' "${DISPLAY_MAX_HZ:-60}"
}

display_defend_hz() {
    local target_hz="" cur_min="" cur_peak="" cur_rrm="" sys_rrm="" defended=0
    [ "${DISPLAY_AUTO_HZ:-1}" = "1" ] || return 0
    [ -f "$KGX_DATA_DIR/state/active_display.env" ] || return 0
    . "$KGX_DATA_DIR/state/active_display.env"
    target_hz="${ACTIVE_DISPLAY_HZ:-}"
    [ -n "$target_hz" ] && [ "$target_hz" -ge 90 ] 2>/dev/null || return 0
    command -v settings >/dev/null 2>&1 || return 0

    cur_min="$(settings get system min_refresh_rate 2>/dev/null | tr -dc '0-9.')"
    cur_min="${cur_min%%.*}"
    cur_peak="$(settings get system peak_refresh_rate 2>/dev/null | tr -dc '0-9.')"
    cur_peak="${cur_peak%%.*}"
    cur_rrm="$(settings get secure refresh_rate_mode 2>/dev/null | tr -d '\r\n ')"

    if { [ -n "$cur_min" ] && [ "$cur_min" -lt "$target_hz" ] 2>/dev/null; } \
       || { [ -n "$cur_peak" ] && [ "$cur_peak" -lt "$target_hz" ] 2>/dev/null; } \
       || { [ "$cur_rrm" = "0" ] && display_is_samsung_rrm; }; then
        defended=1
    fi

    if [ "$defended" -eq 1 ]; then
        if display_is_samsung_rrm; then
            settings put secure refresh_rate_mode 1 >/dev/null 2>&1 || true
            sys_rrm="$(settings get system refresh_rate_mode 2>/dev/null | tr -d '\r\n ')"
            [ -n "$sys_rrm" ] && [ "$sys_rrm" != "null" ] && settings put system refresh_rate_mode 1 >/dev/null 2>&1 || true
        fi
        settings put system peak_refresh_rate "$target_hz" >/dev/null 2>&1 || true
        settings put system min_refresh_rate "$target_hz" >/dev/null 2>&1 || true
        kgx_log "WARN" "display" "Defended ${target_hz}Hz refresh rate after external drop (min=${cur_min:-null}, peak=${cur_peak:-null}, rrm=${cur_rrm:-null})."
    fi
    return 0
}

display_recover_on_boot() {
    local orig_file="$KGX_DATA_DIR/state/orig_display.env"
    local cur_peak="" cur_min="" cur_rrm="" sys_rrm=""
    local cur_peak_int=0 cur_min_int=0 stock_peak="" stock_peak_int=0
    local san_peak="" san_min="" san_peak_int=0
    local ORIG_SYS_PEAK="" ORIG_SYS_MIN="" ORIG_SYS_USER="" ORIG_SEC_USER="" ORIG_SEC_RRM="" ORIG_SYS_RRM=""

    hw_load
    if [ -f "$orig_file" ] && [ -s "$orig_file" ]; then
        display_migrate_original
    fi

    if [ -f "$KGX_DATA_DIR/state/active_display.env" ] || [ -f "$KGX_DATA_DIR/state/active_session.env" ]; then
        kgx_log "WARN" "display" "Detected interrupted session display state; restoring stock refresh rate."
        display_restore
        return 0
    fi

    command -v settings >/dev/null 2>&1 || return 0
    cur_peak="$(settings get system peak_refresh_rate 2>/dev/null | tr -d '\r\n ')"
    cur_min="$(settings get system min_refresh_rate 2>/dev/null | tr -d '\r\n ')"
    cur_rrm="$(settings get secure refresh_rate_mode 2>/dev/null | tr -d '\r\n ')"

    cur_peak_int="${cur_peak%%.*}"
    cur_min_int="${cur_min%%.*}"
    kgx_sanitize_int "$cur_peak_int" || cur_peak_int=0
    kgx_sanitize_int "$cur_min_int" || cur_min_int=0

    # Auto-unstick 60Hz lock on >=90Hz device when no game session is active
    if [ "${DISPLAY_MAX_HZ:-60}" -ge 90 ] 2>/dev/null; then
        if [ "$cur_peak_int" -eq 60 ] || [ "$cur_min_int" -eq 60 ]; then
            if [ -f "$orig_file" ] && [ -s "$orig_file" ]; then
                . "$orig_file"
                stock_peak="$(display_sanitize_hz_val "${ORIG_SYS_PEAK:-null}" "${DISPLAY_MAX_HZ:-60}")"
                stock_peak_int="${stock_peak%%.*}"
                kgx_sanitize_int "$stock_peak_int" || stock_peak_int=0
                if [ "$stock_peak" = "null" ] || [ "$stock_peak_int" -gt 60 ] 2>/dev/null; then
                    kgx_log "WARN" "display" "Detected stuck 60Hz settings (peak=${cur_peak}, min=${cur_min}) while stock allows ${stock_peak}; auto-restoring."
                    display_restore
                    return 0
                fi
            elif [ "$cur_rrm" = "1" ]; then
                kgx_log "WARN" "display" "Detected stuck 60Hz settings with seamless refresh_rate_mode=1 and no baseline; clearing locks."
                settings delete system min_refresh_rate >/dev/null 2>&1 || true
                settings delete system peak_refresh_rate >/dev/null 2>&1 || true
                return 0
            fi
        fi
    fi

    # Sanitize live SamHelper fractional overshoot (e.g., 120.1 > 120.00001 breaks DisplayModeDirector)
    san_peak="$(display_sanitize_hz_val "${cur_peak:-null}" "${DISPLAY_MAX_HZ:-60}")"
    san_min="$(display_sanitize_hz_val "${cur_min:-null}" "${DISPLAY_MAX_HZ:-60}")"
    if [ "$san_peak" != "${cur_peak:-null}" ] || [ "$san_min" != "${cur_min:-null}" ]; then
        san_peak_int="${san_peak%%.*}"
        kgx_sanitize_int "$san_peak_int" || san_peak_int=0
        if [ "$san_peak_int" -ge 90 ] 2>/dev/null && display_is_samsung_rrm; then
            settings put secure refresh_rate_mode 1 >/dev/null 2>&1 || true
            sys_rrm="$(settings get system refresh_rate_mode 2>/dev/null | tr -d '\r\n ')"
            [ -n "$sys_rrm" ] && [ "$sys_rrm" != "null" ] && settings put system refresh_rate_mode 1 >/dev/null 2>&1 || true
        fi
        [ "$san_peak" != "null" ] && settings put system peak_refresh_rate "$san_peak" >/dev/null 2>&1 || true
        [ "$san_min" != "null" ] && settings put system min_refresh_rate "$san_min" >/dev/null 2>&1 || true
        kgx_log "INFO" "display" "Sanitized live refresh rate settings (${cur_peak}/${cur_min} -> ${san_peak}/${san_min})."
    fi
    return 0
}

display_ext_detect() {
    local st_file cdir cname st_val ds_line ext_name="" dex_v="" mon_v="" saw_hw=0

    if [ -d "$KGX_SYS_ROOT/class/drm" ]; then
        for st_file in "$KGX_SYS_ROOT/class/drm"/*/status; do
            [ -r "$st_file" ] || continue
            cdir="${st_file%/*}"
            cname="${cdir##*/}"
            case "$cname" in
                *eDP*|*DSI*|*LVDS*|*Virtual*) continue ;;
                *-DP-*|*-HDMI-*|*-DVI-*|*-VGA-*)
                    saw_hw=1
                    st_val="$(cat "$st_file" 2>/dev/null | head -n 1 | tr -d '\r\n ')"
                    if [ "$st_val" = "connected" ]; then
                        printf '%s\n' "$cname"
                        return 0
                    fi
                    ;;
            esac
        done
    fi

    if [ -d "$KGX_SYS_ROOT/class/dp_sec" ]; then
        saw_hw=1
        if [ -r "$KGX_SYS_ROOT/class/dp_sec/dex" ]; then
            dex_v="$(cat "$KGX_SYS_ROOT/class/dp_sec/dex" 2>/dev/null | head -n 1 | tr -dc '0-9')"
            if [ "$dex_v" = "1" ]; then
                printf 'samsung-dex\n'
                return 0
            fi
        fi
        if [ -r "$KGX_SYS_ROOT/class/dp_sec/monitor_info" ]; then
            mon_v="$(cat "$KGX_SYS_ROOT/class/dp_sec/monitor_info" 2>/dev/null | head -n 1 | tr -d '\r\n ')"
            case "$mon_v" in
                ''|',0x0,0x0'|'0x0,0x0') ;;
                *) printf 'samsung-dp\n'; return 0 ;;
            esac
        fi
    fi

    [ "$saw_hw" -eq 1 ] && return 1

    if command -v dumpsys >/dev/null 2>&1; then
        ds_line="$(dumpsys display 2>/dev/null | awk '
            /DisplayDeviceInfo\{/ && /type EXTERNAL/ && !/state OFF/ {
                print $0; exit
            }')"
        if [ -n "$ds_line" ]; then
            ext_name="$(printf '%s\n' "$ds_line" | sed -n 's/.*DisplayDeviceInfo{"\([^"]*\)".*/\1/p')"
            [ -n "$ext_name" ] || ext_name="EXTERNAL"
            printf '%s\n' "$ext_name"
            return 0
        fi
    fi

    return 1
}

display_ext_is_connected() {
    local d
    d="$(display_ext_detect 2>/dev/null || true)"
    [ -n "$d" ]
}

display_internal_power_off() {
    local state_file="$KGX_DATA_DIR/state/ext_internal_off.state"
    local bl_bkp="$KGX_DATA_DIR/state/orig_ext_bl.val"
    local ext_name="" dex_ok=0 cur_bl=""

    ext_name="$(display_ext_detect 2>/dev/null || true)"
    if [ -z "$ext_name" ]; then
        kgx_log "WARN" "display" "Safety guard: refused turning off internal screen without external display."
        display_internal_power_on >/dev/null 2>&1 || true
        return 1
    fi

    mkdir -p "$KGX_DATA_DIR/state" 2>/dev/null || true
    if command -v app_process >/dev/null 2>&1 && [ -f "$KGX_MODDIR/data/kgx-display.dex" ]; then
        if CLASSPATH="$KGX_MODDIR/data/kgx-display.dex" app_process / com.kgx.display.DisplayPowerCtrl off >/dev/null 2>&1; then
            dex_ok=1
        fi
    fi

    if [ "$dex_ok" -eq 0 ]; then
        hw_load
        if [ -n "${BACKLIGHT_NODE:-}" ] && [ -w "$BACKLIGHT_NODE" ]; then
            if [ ! -f "$bl_bkp" ]; then
                cur_bl="$(cat "$BACKLIGHT_NODE" 2>/dev/null | head -n 1 | tr -dc '0-9')"
                [ -n "$cur_bl" ] && printf '%s\n' "$cur_bl" > "$bl_bkp"
            fi
            echo '0' > "$BACKLIGHT_NODE" 2>/dev/null || true
        else
            kgx_log "WARN" "display" "Unable to power off internal panel (helper DEX & backlight unavailable)."
            return 1
        fi
    fi

    printf '1\n' > "$state_file"
    kgx_log "INFO" "display" "Internal screen OFF while external display connected ($ext_name, dex=$dex_ok)."
    return 0
}

display_internal_power_on() {
    local state_file="$KGX_DATA_DIR/state/ext_internal_off.state"
    local bl_bkp="$KGX_DATA_DIR/state/orig_ext_bl.val"
    local orig_bl=""

    if command -v app_process >/dev/null 2>&1 && [ -f "$KGX_MODDIR/data/kgx-display.dex" ]; then
        CLASSPATH="$KGX_MODDIR/data/kgx-display.dex" app_process / com.kgx.display.DisplayPowerCtrl on >/dev/null 2>&1 || true
    fi

    if [ -f "$bl_bkp" ]; then
        hw_load
        orig_bl="$(cat "$bl_bkp" 2>/dev/null | head -n 1 | tr -dc '0-9')"
        if [ -n "$orig_bl" ] && [ -n "${BACKLIGHT_NODE:-}" ] && [ -w "$BACKLIGHT_NODE" ]; then
            echo "$orig_bl" > "$BACKLIGHT_NODE" 2>/dev/null || true
        fi
        rm -f "$bl_bkp" 2>/dev/null || true
    fi

    if [ -f "$state_file" ]; then
        rm -f "$state_file" 2>/dev/null || true
        kgx_log "INFO" "display" "Restored internal screen power ON."
    fi
    return 0
}

display_ext_sync() {
    local state_file="$KGX_DATA_DIR/state/ext_internal_off.state"
    if [ "${SAFE_MODE:-0}" = "1" ] || [ "${EXT_DISPLAY_SCREEN_OFF:-0}" != "1" ]; then
        [ -f "$state_file" ] && display_internal_power_on
        return 0
    fi
    if display_ext_is_connected; then
        [ -f "$state_file" ] || display_internal_power_off || true
    else
        [ -f "$state_file" ] && display_internal_power_on
    fi
    return 0
}

display_scrcpy_is_active() {
    local p
    [ -d "$KGX_PROC_ROOT" ] || return 1
    for p in "$KGX_PROC_ROOT"/[0-9]*; do
        [ -r "$p/cmdline" ] || continue
        case "$(kgx_read_cmdline "$p/cmdline")" in
            *scrcpy*) return 0 ;;
        esac
    done
    return 1
}

display_res_validate() {
    local wxh="$1" w h
    case "$wxh" in
        *x*) ;;
        *) return 1 ;;
    esac
    w="${wxh%%x*}"
    h="${wxh#*x}"
    kgx_sanitize_int "$w" && kgx_sanitize_int "$h" || return 1
    [ "$w" -ge 480 ] && [ "$w" -le 3840 ] && [ "$h" -ge 480 ] && [ "$h" -le 3840 ]
}

display_res_capture_orig() {
    local orig_file="$KGX_DATA_DIR/state/orig_res.env"
    local sz="" dn="" ow=1080 oh=2340 od=480

    [ -f "$orig_file" ] && [ -s "$orig_file" ] && return 0
    mkdir -p "$KGX_DATA_DIR/state" 2>/dev/null || true
    if command -v wm >/dev/null 2>&1; then
        sz="$(wm size 2>/dev/null | awk '/Physical size:/{print $3; exit}' | tr -d '\r')"
        if display_res_validate "$sz"; then
            ow="${sz%%x*}"
            oh="${sz#*x}"
        fi
        dn="$(wm density 2>/dev/null | awk '/Physical density:/{print $3; exit}' | tr -dc '0-9')"
        if [ -n "$dn" ] && [ "$dn" -ge 120 ] 2>/dev/null; then
            od="$dn"
        fi
    fi
    cat > "$orig_file" <<EOF
ORIG_W='$ow'
ORIG_H='$oh'
ORIG_DENS='$od'
EOF
    return 0
}

display_res_apply() {
    local wxh="$1" dens_mode="${2:-auto}" source="${3:-global}"
    local state_file="$KGX_DATA_DIR/state/active_res.env"
    local orig_file="$KGX_DATA_DIR/state/orig_res.env"
    local w target_d ACTIVE_RES="" ACTIVE_DENSITY="" ACTIVE_RES_SOURCE=""
    local ORIG_W=1080 ORIG_H=2340 ORIG_DENS=480

    display_res_validate "$wxh" || return 1
    display_res_capture_orig
    [ -f "$orig_file" ] && . "$orig_file"

    w="${wxh%%x*}"
    if [ -z "$dens_mode" ] || [ "$dens_mode" = "auto" ]; then
        target_d=$(( (ORIG_DENS * w + ORIG_W / 2) / ORIG_W ))
        [ "$target_d" -lt 240 ] 2>/dev/null && target_d=240
        [ "$target_d" -gt 640 ] 2>/dev/null && target_d=640
    else
        kgx_sanitize_int "$dens_mode" || return 1
        target_d="$dens_mode"
        [ "$target_d" -lt 240 ] 2>/dev/null && target_d=240
        [ "$target_d" -gt 640 ] 2>/dev/null && target_d=640
    fi

    if [ -f "$state_file" ]; then
        . "$state_file"
        if [ "$ACTIVE_RES" = "$wxh" ] && [ "$ACTIVE_DENSITY" = "$target_d" ] && [ "$ACTIVE_RES_SOURCE" = "$source" ]; then
            return 0
        fi
    fi

    if command -v wm >/dev/null 2>&1; then
        wm size "$wxh" >/dev/null 2>&1 || return 1
        wm density "$target_d" >/dev/null 2>&1 || true
    fi
    cat > "$state_file" <<EOF
ACTIVE_RES='$wxh'
ACTIVE_DENSITY='$target_d'
ACTIVE_RES_SOURCE='$source'
EOF
    kgx_log "INFO" "display" "Applied resolution override ${wxh} @ ${target_d}dpi (source=$source)."
    return 0
}

display_res_reset() {
    local force="${1:-0}"
    local state_file="$KGX_DATA_DIR/state/active_res.env"
    if [ "$force" = "1" ] || [ -f "$state_file" ]; then
        if command -v wm >/dev/null 2>&1; then
            wm size reset >/dev/null 2>&1 || true
            wm density reset >/dev/null 2>&1 || true
        fi
        if [ -f "$state_file" ]; then
            rm -f "$state_file" 2>/dev/null || true
            kgx_log "INFO" "display" "Reset wm size & density back to stock."
        fi
    fi
    return 0
}

display_res_sync() {
    local state_file="$KGX_DATA_DIR/state/active_res.env"
    local ACTIVE_RES="" ACTIVE_DENSITY="" ACTIVE_RES_SOURCE=""
    local need_global=0

    kgx_load_config
    [ -f "$state_file" ] && . "$state_file"

    if [ "${SAFE_MODE:-0}" = "1" ] || [ "${RES_OVERRIDE_ENABLED:-0}" != "1" ]; then
        [ "$ACTIVE_RES_SOURCE" = "global" ] && display_res_reset 0
        return 0
    fi

    if [ "${RES_OVERRIDE_SCOPE:-ext_scrcpy}" = "always" ]; then
        need_global=1
    elif display_ext_is_connected || display_scrcpy_is_active; then
        need_global=1
    fi

    if [ "$need_global" -eq 1 ]; then
        display_res_apply "${RES_OVERRIDE_PRESET:-1080x1920}" "${RES_OVERRIDE_DENSITY:-auto}" "global" || true
    elif [ "$ACTIVE_RES_SOURCE" = "global" ]; then
        display_res_reset 0
    fi
    return 0
}
