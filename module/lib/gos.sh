#!/system/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# KSU Ultimate Gaming X v3.3 - Safe Reversible Samsung GOS Neutralizer

GOS_PKG="com.samsung.android.game.gos"

gos_is_present() {
    command -v pm >/dev/null 2>&1 || return 1
    [ -n "$(pm path "$GOS_PKG" 2>/dev/null)" ]
}

gos_is_disabled() {
    command -v pm >/dev/null 2>&1 || return 1
    pm list packages -d 2>/dev/null | grep -qx "package:$GOS_PKG"
}

gos_capture_original() {
    local orig_file="$KGX_DATA_DIR/state/orig_gos.env"
    [ -f "$orig_file" ] && [ -s "$orig_file" ] && return 0
    gos_is_present || return 0
    mkdir -p "$KGX_DATA_DIR/state" 2>/dev/null || true
    if gos_is_disabled; then
        printf 'ORIG_GOS_STATE=disabled\n' > "$orig_file"
    else
        printf 'ORIG_GOS_STATE=enabled\n' > "$orig_file"
    fi
    return 0
}

gos_apply() {
    local state_file="$KGX_DATA_DIR/state/gos_neutralized.state"
    [ "${SAFE_MODE:-0}" = "1" ] && return 0
    [ "${GOS_NEUTRALIZE:-0}" = "1" ] || return 0
    gos_is_present || return 0

    gos_capture_original
    command -v am >/dev/null 2>&1 && am force-stop "$GOS_PKG" >/dev/null 2>&1 || true
    if ! gos_is_disabled; then
        if pm disable-user --user 0 "$GOS_PKG" >/dev/null 2>&1; then
            mkdir -p "$KGX_DATA_DIR/state" 2>/dev/null || true
            printf '1\n' > "$state_file"
            kgx_log "INFO" "gos" "Neutralized Samsung GOS ($GOS_PKG) safely via disable-user."
        else
            kgx_log "WARN" "gos" "Failed to disable $GOS_PKG cleanly."
        fi
    else
        mkdir -p "$KGX_DATA_DIR/state" 2>/dev/null || true
        printf '1\n' > "$state_file"
    fi
    return 0
}

gos_restore() {
    local orig_file="$KGX_DATA_DIR/state/orig_gos.env"
    local state_file="$KGX_DATA_DIR/state/gos_neutralized.state"
    local need_enable=0 ORIG_GOS_STATE=""

    if [ -f "$state_file" ]; then
        need_enable=1
    elif [ -f "$orig_file" ]; then
        . "$orig_file"
        if [ "${ORIG_GOS_STATE:-}" = "enabled" ] && gos_is_disabled; then
            need_enable=1
        fi
    fi

    if [ "$need_enable" -eq 1 ] && gos_is_present; then
        pm enable "$GOS_PKG" >/dev/null 2>&1 || true
        kgx_log "INFO" "gos" "Restored Samsung GOS ($GOS_PKG) to stock enabled state."
    fi
    rm -f "$state_file" 2>/dev/null || true
    return 0
}
