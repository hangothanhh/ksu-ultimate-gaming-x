#!/system/bin/sh
# KSU Ultimate Gaming X v3.2 - Safe Bypass Charging & Battery Power Engine

power_get_batt_pct() {
    local pct=""
    hw_load
    if [ -n "$BATT_CAPACITY_NODE" ] && [ -r "$BATT_CAPACITY_NODE" ]; then
        pct="$(cat "$BATT_CAPACITY_NODE" 2>/dev/null | head -n 1 | tr -dc '0-9')"
    fi
    case "$pct" in
        ''|*[!0-9]*) pct=0 ;;
    esac
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100
    printf '%s\n' "$pct"
}

power_is_plugged() {
    local st="" on="" any_online=0
    hw_load
    if [ -n "$BATT_STATUS_NODE" ] && [ -r "$BATT_STATUS_NODE" ]; then
        st="$(cat "$BATT_STATUS_NODE" 2>/dev/null | head -n 1 | tr -d '\r')"
        case "$st" in
            Charging|Full|"Not charging"|Not\ charging) return 0 ;;
            Discharging) return 1 ;;
        esac
    fi
    for on in "$KGX_SYS_ROOT/class/power_supply/usb/online" "$KGX_SYS_ROOT/class/power_supply/ac/online"; do
        if [ -r "$on" ]; then
            any_online=1
            if [ "$(cat "$on" 2>/dev/null | head -n 1 | tr -dc '0-9')" = "1" ]; then
                return 0
            fi
        fi
    done
    [ "$any_online" -eq 1 ] && return 1
    [ -n "$BATT_CAPACITY_NODE" ] && [ -r "$BATT_CAPACITY_NODE" ] && return 0
    return 1
}

power_bypass_on_val() {
    hw_load
    case "${BYPASS_MODE:-none}" in
        zero_off) printf '0\n' ;;
        slate|invert1) printf '1\n' ;;
        *) printf '\n' ;;
    esac
}

power_bypass_off_val() {
    hw_load
    case "${BYPASS_MODE:-none}" in
        zero_off) printf '1\n' ;;
        slate|invert1) printf '0\n' ;;
        *) printf '\n' ;;
    esac
}

power_bypass_apply() {
    local pct min_pct on_val
    [ "${BYPASS_CHARGING:-0}" = "1" ] || return 0
    hw_load
    [ -n "$BYPASS_NODE" ] && [ -w "$BYPASS_NODE" ] || return 0
    power_is_plugged || return 0

    pct="$(power_get_batt_pct)"
    min_pct="${BYPASS_MIN_PCT:-80}"
    kgx_sanitize_int "$min_pct" || min_pct=80
    [ "$min_pct" -lt 20 ] 2>/dev/null && min_pct=20

    if [ "$pct" -lt "$min_pct" ] 2>/dev/null; then
        return 0
    fi

    on_val="$(power_bypass_on_val)"
    [ -n "$on_val" ] || return 0
    mkdir -p "$KGX_DATA_DIR/state" 2>/dev/null || true
    if sysfs_safe_write "$BYPASS_NODE" "$on_val"; then
        printf '1\n' > "$KGX_DATA_DIR/state/bypass_active.state"
        kgx_log "INFO" "power" "Bypass charging ON ($BYPASS_NODE=$on_val, mode=$BYPASS_MODE, batt=${pct}% >= ${min_pct}%)."
    fi
    return 0
}

power_bypass_restore() {
    local state_file="$KGX_DATA_DIR/state/bypass_active.state"
    local off_val on_val cur_val=""
    hw_load
    if [ -n "$BYPASS_NODE" ] && [ -w "$BYPASS_NODE" ]; then
        on_val="$(power_bypass_on_val)"
        off_val="$(power_bypass_off_val)"
        cur_val="$(cat "$BYPASS_NODE" 2>/dev/null | head -n 1 | tr -dc '0-9')"
        if [ -f "$state_file" ] || { [ -n "$on_val" ] && [ "$cur_val" = "$on_val" ]; }; then
            if [ -n "$off_val" ]; then
                echo "$off_val" > "$BYPASS_NODE" 2>/dev/null || true
                kgx_log "INFO" "power" "Bypass charging OFF (restored $BYPASS_NODE=$off_val)."
            fi
        fi
    fi
    rm -f "$state_file" 2>/dev/null || true
    return 0
}

power_bypass_update() {
    local state_file="$KGX_DATA_DIR/state/bypass_active.state"
    local pct min_pct drop_floor

    if [ "${BYPASS_CHARGING:-0}" != "1" ]; then
        power_bypass_restore
        return 0
    fi

    pct="$(power_get_batt_pct)"
    min_pct="${BYPASS_MIN_PCT:-80}"
    kgx_sanitize_int "$min_pct" || min_pct=80
    [ "$min_pct" -lt 20 ] 2>/dev/null && min_pct=20
    drop_floor=$((min_pct - 3))
    [ "$drop_floor" -lt 15 ] && drop_floor=15

    if [ -f "$state_file" ]; then
        if [ "$pct" -lt "$drop_floor" ] 2>/dev/null || ! power_is_plugged; then
            power_bypass_restore
        fi
    else
        if [ "$pct" -ge "$min_pct" ] 2>/dev/null && power_is_plugged; then
            power_bypass_apply
        fi
    fi
    return 0
}

power_read_mw() {
    local bdir="$KGX_SYS_ROOT/class/power_supply/battery"
    local cur_raw="" volt_raw="" st="" ma=0 mv=3850 abs_ma=0 mw=0 chg=0

    if [ -r "$bdir/current_now" ]; then
        cur_raw="$(cat "$bdir/current_now" 2>/dev/null | head -n 1 | tr -dc '0-9-')"
    elif [ -r "$bdir/current_avg" ]; then
        cur_raw="$(cat "$bdir/current_avg" 2>/dev/null | head -n 1 | tr -dc '0-9-')"
    fi
    if [ -r "$bdir/voltage_now" ]; then
        volt_raw="$(cat "$bdir/voltage_now" 2>/dev/null | head -n 1 | tr -dc '0-9')"
    elif [ -r "$bdir/voltage_avg" ]; then
        volt_raw="$(cat "$bdir/voltage_avg" 2>/dev/null | head -n 1 | tr -dc '0-9')"
    fi

    kgx_sanitize_int "${cur_raw:-0}" && ma="$cur_raw" || ma=0
    if [ "$ma" -gt 25000 ] 2>/dev/null || [ "$ma" -lt -25000 ] 2>/dev/null; then
        ma=$((ma / 1000))
    fi
    abs_ma="$ma"
    [ "$abs_ma" -lt 0 ] 2>/dev/null && abs_ma=$((-abs_ma))

    if [ -n "$volt_raw" ] && [ "$volt_raw" -gt 100000 ] 2>/dev/null; then
        mv=$((volt_raw / 1000))
    elif [ -n "$volt_raw" ] && [ "$volt_raw" -gt 100 ] 2>/dev/null; then
        mv="$volt_raw"
    fi
    [ "$mv" -gt 0 ] 2>/dev/null || mv=3850

    mw=$(( (abs_ma * mv) / 1000 ))
    if [ -n "$BATT_STATUS_NODE" ] && [ -r "$BATT_STATUS_NODE" ]; then
        st="$(cat "$BATT_STATUS_NODE" 2>/dev/null | head -n 1 | tr -d '\r')"
    elif [ -r "$bdir/status" ]; then
        st="$(cat "$bdir/status" 2>/dev/null | head -n 1 | tr -d '\r')"
    fi
    case "$st" in
        Charging|Full) chg=1 ;;
    esac

    printf '%s|%s|%s\n' "$mw" "$ma" "$chg"
}

power_bypass_force_emergency() {
    local on_val
    hw_load
    [ -n "$BYPASS_NODE" ] && [ -e "$BYPASS_NODE" ] || return 0
    power_is_plugged || return 0
    [ -f "$KGX_DATA_DIR/state/bypass_active.state" ] && return 0

    on_val="$(power_bypass_on_val)"
    [ -n "$on_val" ] || return 0
    mkdir -p "$KGX_DATA_DIR/state" 2>/dev/null || true
    if sysfs_safe_write "$BYPASS_NODE" "$on_val"; then
        printf '1\n' > "$KGX_DATA_DIR/state/bypass_active.state"
        kgx_log "WARN" "power" "Emergency thermal bypass charging ON ($BYPASS_NODE=$on_val)."
    fi
    return 0
}
