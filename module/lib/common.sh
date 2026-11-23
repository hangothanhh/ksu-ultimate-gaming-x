#!/system/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# KSU Ultimate Gaming X - Common utilities, config, logging, JSON helpers & safe sysfs wrapper

KGX_MODDIR="${KGX_MODDIR:-/data/adb/modules/ksu_ultimate_gaming_x}"
KGX_DATA_DIR="${KGX_DATA_DIR:-/data/adb/ksu_gaming_x}"
KGX_SYS_ROOT="${KGX_SYS_ROOT:-/sys}"
KGX_PROC_ROOT="${KGX_PROC_ROOT:-/proc}"
KGX_DEV_ROOT="${KGX_DEV_ROOT:-/dev}"
KGX_CGROUP_ROOT="${KGX_CGROUP_ROOT:-/sys/fs/cgroup}"
KGX_MODULES_ROOT="${KGX_MODULES_ROOT:-/data/adb/modules}"

kgx_init_dirs() {
    mkdir -p \
        "$KGX_DATA_DIR/config" \
        "$KGX_DATA_DIR/state" \
        "$KGX_DATA_DIR/backups" \
        "$KGX_DATA_DIR/logs" \
        "$KGX_DATA_DIR/profiles" 2>/dev/null || true

    if [ ! -f "$KGX_DATA_DIR/config/global.conf" ] && [ -f "$KGX_MODDIR/data/default_global.conf" ]; then
        cp "$KGX_MODDIR/data/default_global.conf" "$KGX_DATA_DIR/config/global.conf"
    fi

    if [ ! -f "$KGX_DATA_DIR/config/custom_games.tsv" ]; then
        printf '# package\tenabled\tspoof_profile\ttarget_fps\tmode\tdisplay_hz\ttouch_profile\tnet_opt\tdownscale\twm_res\n' > "$KGX_DATA_DIR/config/custom_games.tsv"
    fi

    if [ ! -f "$KGX_DATA_DIR/config/freezer_apps.list" ]; then
        printf '# One package per line\n' > "$KGX_DATA_DIR/config/freezer_apps.list"
    fi

    if [ ! -f "$KGX_DATA_DIR/profiles/custom_profiles.tsv" ]; then
        printf '# id\tlabel\tcategory\tsoc_family\tgpu_family\ttier\tmax_hz\tram_gb\tbrand\tmanufacturer\tmodel\tdevice\tproduct\tfingerprint\tnotes\n' > "$KGX_DATA_DIR/profiles/custom_profiles.tsv"
    fi
}

kgx_log() {
    local level comp msg log_file sz ts
    level="${1:-INFO}"
    comp="${2:-core}"
    msg="${3:-}"
    log_file="$KGX_DATA_DIR/logs/engine.log"

    mkdir -p "$KGX_DATA_DIR/logs" 2>/dev/null || true
    if [ -f "$log_file" ]; then
        sz="$(wc -c < "$log_file" 2>/dev/null || printf '0')"
        case "$sz" in
            ''|*[!0-9]*) sz=0 ;;
        esac
        if [ "$sz" -gt 524288 ]; then
            mv -f "$log_file" "${log_file}.1" 2>/dev/null || true
        fi
    fi

    ts="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || printf '1970-01-01 00:00:00')"
    printf '[%s] [%s] [%s] %s\n' "$ts" "$level" "$comp" "$msg" >> "$log_file" 2>/dev/null || true
}

KGX_NL='
'
KGX_CR="$(printf '\r')"

json_escape() {
    case "$1" in
        *\\*|*\"*|*'	'*|*"$KGX_CR"*|*"$KGX_NL"*)
            printf '%s\n' "$1" | awk '
            {
                gsub(/\\/, "\\\\")
                gsub(/"/, "\\\"")
                gsub(/\t/, "\\t")
                gsub(/\r/, "")
                if (NR > 1) printf "\\n"
                printf "%s", $0
            }'
            ;;
        *)
            printf '%s' "$1"
            ;;
    esac
}

kgx_sanitize_pkg() {
    case "$1" in
        [A-Za-z]*) ;;
        *) return 1 ;;
    esac
    case "$1" in
        *[!A-Za-z0-9_.]*|.*|*.|*..*) return 1 ;;
        *.*) return 0 ;;
        *) return 1 ;;
    esac
}

kgx_sanitize_id() {
    case "$1" in
        ''|*[!A-Za-z0-9_.-]*|*..*) return 1 ;;
    esac
    return 0
}

kgx_sanitize_int() {
    case "$1" in
        ''|-) return 1 ;;
        -*)
            case "${1#-}" in
                ''|*[!0-9]*) return 1 ;;
            esac
            return 0
            ;;
        *[!0-9]*) return 1 ;;
    esac
    return 0
}

kgx_sanitize_prop_val() {
    local v="$1"
    [ -n "$v" ] || return 1
    case "$v" in
        *';'*|*'`'*|*'$'*|*'<'*|*'>'*|*'|'*|*'&'*|*'	'*) return 1 ;;
    esac
    printf '%s' "$v" | grep -Eq '^[A-Za-z0-9 ._:/+,()_-]+$'
}

kgx_is_valid_mode() {
    case "$1" in
        balanced|high_performance|extreme_gaming|battery_gaming) return 0 ;;
        *) return 1 ;;
    esac
}

kgx_is_valid_config_key() {
    case "$1" in
        AUTO_OPTIMIZE|SAFE_MODE|SPOOF_ENABLED|PLAY_INTEGRITY_SHIELD|SPOOF_EXCLUDE_SETTINGS|GLOBAL_SPOOF_PROFILE|DEFAULT_MODE|\
        FPS_ENGINE_ENABLED|DISPLAY_AUTO_HZ|TOUCH_OPT_ENABLED|RAM_OPT_ENABLED|\
        THERMAL_GUARD_ENABLED|THERMAL_UNLOCK|SUSTAINED_SWEET_SPOT|MAX_CLOCK_LOCK|\
        SOFT_THERMAL_STEP|GOS_NEUTRALIZE|EXT_DISPLAY_SCREEN_OFF|\
        RES_OVERRIDE_ENABLED|RES_OVERRIDE_SCOPE|RES_OVERRIDE_PRESET|RES_OVERRIDE_DENSITY|\
        FREEZER_ENABLED|THERMAL_ALERT_ENABLED|THERMAL_ALERT_BATT_C|THERMAL_ALERT_CPU_C|THERMAL_ALERT_ACTION|\
        BYPASS_CHARGING|BYPASS_MIN_PCT|\
        THERMAL_WARN_BATT|THERMAL_HOT_BATT|THERMAL_CRIT_BATT|\
        THERMAL_WARN_CPU|THERMAL_HOT_CPU|THERMAL_CRIT_CPU|NET_OPT_ENABLED|\
        NET_WIFI_LOW_LATENCY|NET_PING_HOST|POLL_INTERVAL_ACTIVE|\
        POLL_INTERVAL_IDLE|EXIT_DEBOUNCE_SEC|LOG_LEVEL|KEEP_BACKUPS_ON_UNINSTALL)
            return 0 ;;
        *) return 1 ;;
    esac
}

kgx_apply_kv() {
    local k="$1"
    local v="$2"
    case "$k" in
        AUTO_OPTIMIZE) AUTO_OPTIMIZE="$v" ;;
        SAFE_MODE) SAFE_MODE="$v" ;;
        SPOOF_ENABLED) SPOOF_ENABLED="$v" ;;
        PLAY_INTEGRITY_SHIELD) PLAY_INTEGRITY_SHIELD="$v" ;;
        SPOOF_EXCLUDE_SETTINGS) SPOOF_EXCLUDE_SETTINGS="$v" ;;
        GLOBAL_SPOOF_PROFILE) GLOBAL_SPOOF_PROFILE="$v" ;;
        DEFAULT_MODE) DEFAULT_MODE="$v" ;;
        FPS_ENGINE_ENABLED) FPS_ENGINE_ENABLED="$v" ;;
        DISPLAY_AUTO_HZ) DISPLAY_AUTO_HZ="$v" ;;
        TOUCH_OPT_ENABLED) TOUCH_OPT_ENABLED="$v" ;;
        RAM_OPT_ENABLED) RAM_OPT_ENABLED="$v" ;;
        THERMAL_GUARD_ENABLED) THERMAL_GUARD_ENABLED="$v" ;;
        THERMAL_UNLOCK) THERMAL_UNLOCK="$v" ;;
        SUSTAINED_SWEET_SPOT) SUSTAINED_SWEET_SPOT="$v" ;;
        MAX_CLOCK_LOCK) MAX_CLOCK_LOCK="$v" ;;
        SOFT_THERMAL_STEP) SOFT_THERMAL_STEP="$v" ;;
        GOS_NEUTRALIZE) GOS_NEUTRALIZE="$v" ;;
        EXT_DISPLAY_SCREEN_OFF) EXT_DISPLAY_SCREEN_OFF="$v" ;;
        RES_OVERRIDE_ENABLED) RES_OVERRIDE_ENABLED="$v" ;;
        RES_OVERRIDE_SCOPE) RES_OVERRIDE_SCOPE="$v" ;;
        RES_OVERRIDE_PRESET) RES_OVERRIDE_PRESET="$v" ;;
        RES_OVERRIDE_DENSITY) RES_OVERRIDE_DENSITY="$v" ;;
        FREEZER_ENABLED) FREEZER_ENABLED="$v" ;;
        THERMAL_ALERT_ENABLED) THERMAL_ALERT_ENABLED="$v" ;;
        THERMAL_ALERT_BATT_C) THERMAL_ALERT_BATT_C="$v" ;;
        THERMAL_ALERT_CPU_C) THERMAL_ALERT_CPU_C="$v" ;;
        THERMAL_ALERT_ACTION) THERMAL_ALERT_ACTION="$v" ;;
        BYPASS_CHARGING) BYPASS_CHARGING="$v" ;;
        BYPASS_MIN_PCT) BYPASS_MIN_PCT="$v" ;;
        THERMAL_WARN_BATT) THERMAL_WARN_BATT="$v" ;;
        THERMAL_HOT_BATT) THERMAL_HOT_BATT="$v" ;;
        THERMAL_CRIT_BATT) THERMAL_CRIT_BATT="$v" ;;
        THERMAL_WARN_CPU) THERMAL_WARN_CPU="$v" ;;
        THERMAL_HOT_CPU) THERMAL_HOT_CPU="$v" ;;
        THERMAL_CRIT_CPU) THERMAL_CRIT_CPU="$v" ;;
        NET_OPT_ENABLED) NET_OPT_ENABLED="$v" ;;
        NET_WIFI_LOW_LATENCY) NET_WIFI_LOW_LATENCY="$v" ;;
        NET_PING_HOST) NET_PING_HOST="$v" ;;
        POLL_INTERVAL_ACTIVE) POLL_INTERVAL_ACTIVE="$v" ;;
        POLL_INTERVAL_IDLE) POLL_INTERVAL_IDLE="$v" ;;
        EXIT_DEBOUNCE_SEC) EXIT_DEBOUNCE_SEC="$v" ;;
        LOG_LEVEL) LOG_LEVEL="$v" ;;
        KEEP_BACKUPS_ON_UNINSTALL) KEEP_BACKUPS_ON_UNINSTALL="$v" ;;
    esac
}

kgx_load_config_file() {
    local cfg="$1"
    local line key val
    [ -f "$cfg" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            *"$KGX_CR") line="${line%$KGX_CR}" ;;
        esac
        case "$line" in
            ''|\#*) continue ;;
        esac
        case "$line" in
            *=*)
                key="${line%%=*}"
                val="${line#*=}"
                if kgx_is_valid_config_key "$key"; then
                    kgx_apply_kv "$key" "$val"
                fi
                ;;
        esac
    done < "$cfg"
}

kgx_load_config() {
    # Hardcoded fallback defaults
    AUTO_OPTIMIZE=1
    SAFE_MODE=0
    SPOOF_ENABLED=1
    PLAY_INTEGRITY_SHIELD=1
    SPOOF_EXCLUDE_SETTINGS=1
    GLOBAL_SPOOF_PROFILE=realme_14_5g
    DEFAULT_MODE=high_performance
    FPS_ENGINE_ENABLED=1
    DISPLAY_AUTO_HZ=1
    TOUCH_OPT_ENABLED=1
    RAM_OPT_ENABLED=1
    THERMAL_GUARD_ENABLED=1
    THERMAL_UNLOCK=0
    SUSTAINED_SWEET_SPOT=0
    MAX_CLOCK_LOCK=0
    SOFT_THERMAL_STEP=0
    GOS_NEUTRALIZE=0
    EXT_DISPLAY_SCREEN_OFF=0
    RES_OVERRIDE_ENABLED=0
    RES_OVERRIDE_SCOPE=ext_scrcpy
    RES_OVERRIDE_PRESET=1080x1920
    RES_OVERRIDE_DENSITY=auto
    FREEZER_ENABLED=0
    THERMAL_ALERT_ENABLED=1
    THERMAL_ALERT_BATT_C=44
    THERMAL_ALERT_CPU_C=92
    THERMAL_ALERT_ACTION=notify
    BYPASS_CHARGING=0
    BYPASS_MIN_PCT=80
    THERMAL_WARN_BATT=38
    THERMAL_HOT_BATT=41
    THERMAL_CRIT_BATT=44
    THERMAL_WARN_CPU=68
    THERMAL_HOT_CPU=76
    THERMAL_CRIT_CPU=85
    NET_OPT_ENABLED=1
    NET_WIFI_LOW_LATENCY=1
    NET_PING_HOST=1.1.1.1
    POLL_INTERVAL_ACTIVE=2
    POLL_INTERVAL_IDLE=1
    EXIT_DEBOUNCE_SEC=2
    LOG_LEVEL=INFO
    KEEP_BACKUPS_ON_UNINSTALL=0

    kgx_load_config_file "$KGX_MODDIR/data/default_global.conf"
    kgx_load_config_file "$KGX_DATA_DIR/config/global.conf"
}

kgx_set_config() {
    local key="$1"
    local val="$2"
    local cfg="$KGX_DATA_DIR/config/global.conf"
    local tmp="$cfg.tmp.$$"

    kgx_is_valid_config_key "$key" || return 1

    # Value validation by key type
    case "$key" in
        AUTO_OPTIMIZE|SAFE_MODE|SPOOF_ENABLED|PLAY_INTEGRITY_SHIELD|SPOOF_EXCLUDE_SETTINGS|FPS_ENGINE_ENABLED|\
        DISPLAY_AUTO_HZ|TOUCH_OPT_ENABLED|RAM_OPT_ENABLED|THERMAL_GUARD_ENABLED|\
        THERMAL_UNLOCK|SUSTAINED_SWEET_SPOT|MAX_CLOCK_LOCK|SOFT_THERMAL_STEP|\
        GOS_NEUTRALIZE|EXT_DISPLAY_SCREEN_OFF|RES_OVERRIDE_ENABLED|FREEZER_ENABLED|\
        THERMAL_ALERT_ENABLED|BYPASS_CHARGING|NET_OPT_ENABLED|NET_WIFI_LOW_LATENCY|\
        KEEP_BACKUPS_ON_UNINSTALL)
            [ "$val" = "0" ] || [ "$val" = "1" ] || return 1
            ;;
        BYPASS_MIN_PCT)
            kgx_sanitize_int "$val" || return 1
            [ "$val" -ge 20 ] && [ "$val" -le 95 ] || return 1
            ;;
        THERMAL_ALERT_BATT_C)
            kgx_sanitize_int "$val" || return 1
            [ "$val" -ge 38 ] && [ "$val" -le 50 ] || return 1
            ;;
        THERMAL_ALERT_CPU_C)
            kgx_sanitize_int "$val" || return 1
            [ "$val" -ge 75 ] && [ "$val" -le 100 ] || return 1
            ;;
        RES_OVERRIDE_SCOPE)
            case "$val" in
                ext_scrcpy|always) ;;
                *) return 1 ;;
            esac
            ;;
        RES_OVERRIDE_PRESET)
            case "$val" in
                1080x1920|900x1600|720x1280|1440x2560) ;;
                *) return 1 ;;
            esac
            ;;
        RES_OVERRIDE_DENSITY)
            case "$val" in
                auto|320|360|400|440|480) ;;
                *) return 1 ;;
            esac
            ;;
        THERMAL_ALERT_ACTION)
            case "$val" in
                notify|bypass|step_down|both) ;;
                *) return 1 ;;
            esac
            ;;
        GLOBAL_SPOOF_PROFILE)
            kgx_sanitize_id "$val" || return 1
            ;;
        DEFAULT_MODE)
            kgx_is_valid_mode "$val" || return 1
            ;;
        LOG_LEVEL)
            case "$val" in
                DEBUG|INFO|WARN|ERROR) ;;
                *) return 1 ;;
            esac
            ;;
        NET_PING_HOST)
            kgx_sanitize_id "$val" || return 1
            ;;
        *)
            kgx_sanitize_int "$val" || return 1
            ;;
    esac

    mkdir -p "$KGX_DATA_DIR/config" 2>/dev/null || true
    if [ ! -f "$cfg" ] && [ -f "$KGX_MODDIR/data/default_global.conf" ]; then
        cp "$KGX_MODDIR/data/default_global.conf" "$cfg"
    elif [ ! -f "$cfg" ]; then
        printf '# KSU Ultimate Gaming X - Global Configuration\n' > "$cfg"
    fi

    awk -v k="$key" -v v="$val" '
    BEGIN { found = 0 }
    $0 ~ ("^" k "=") { print k "=" v; found = 1; next }
    { print }
    END { if (!found) print k "=" v }
    ' "$cfg" > "$tmp" && mv "$tmp" "$cfg"

    kgx_apply_kv "$key" "$val"
    return 0
}

kgx_find_resetprop() {
    if [ -n "${KGX_RESETPROP_BIN:-}" ] && [ -x "$KGX_RESETPROP_BIN" ]; then
        printf '%s\n' "$KGX_RESETPROP_BIN"
        return 0
    fi
    for p in /data/adb/ksu/bin/resetprop /data/adb/ap/bin/resetprop /data/adb/magisk/resetprop; do
        if [ -x "$p" ]; then
            printf '%s\n' "$p"
            return 0
        fi
    done
    if command -v resetprop >/dev/null 2>&1; then
        command -v resetprop
        return 0
    fi
    return 1
}

kgx_is_prop_blocked() {
    local prop="$1"
    case "$prop" in
        ro.serialno|ro.boot.serialno|ro.boot.*|ro.debuggable|ro.secure|ro.adb.secure|\
        ro.crypto.*|ro.build.selinux|persist.radio.*|gsm.*|ril.*|ro.ril.*|net.*|\
        *imei*|*meid*|*macaddr*|*widevine*|*drm*|*keystore*|*verifiedboot*|*vbmeta*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

kgx_is_spoof_write_allowed() {
    local prop="$1"
    if kgx_is_prop_blocked "$prop"; then
        return 1
    fi
    case "$prop" in
        ro.product.brand|ro.product.manufacturer|ro.product.model|ro.product.device|ro.product.name|ro.build.product|\
        ro.product.marketname|ro.vendor.oplus.market.name|\
        ro.product.system.brand|ro.product.system.manufacturer|ro.product.system.model|ro.product.system.device|ro.product.system.name|ro.product.system.marketname|\
        ro.product.product.brand|ro.product.product.manufacturer|ro.product.product.model|ro.product.product.device|ro.product.product.name|ro.product.product.marketname)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

kgx_is_prop_allowed() {
    local prop="$1"
    if kgx_is_prop_blocked "$prop"; then
        return 1
    fi
    if kgx_is_spoof_write_allowed "$prop"; then
        return 0
    fi
    case "$prop" in
        ro.product.vendor.brand|ro.product.vendor.manufacturer|ro.product.vendor.model|ro.product.vendor.device|ro.product.vendor.name|ro.product.vendor.marketname|\
        ro.product.odm.brand|ro.product.odm.manufacturer|ro.product.odm.model|ro.product.odm.device|ro.product.odm.name|ro.product.odm.marketname|\
        ro.build.fingerprint|ro.system.build.fingerprint|ro.vendor.build.fingerprint|ro.odm.build.fingerprint|ro.product.build.fingerprint)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

kgx_is_protected_sysfs() {
    case "$1" in
        *thermal*|*trip_point*|*throttling*|*voltage*|*vdd*|*ifpo*) return 0 ;;
        *) return 1 ;;
    esac
}

# Write to a sysfs/cgroup/dev kernel node in a single syscall (Android toybox printf %s\n issues 2 writes -> EINVAL).
kgx_write_node() {
    local path="$1"
    local val="$2"
    [ -n "$path" ] && [ -e "$path" ] || return 1
    case "$val" in
        -n|-e|-E) { printf '%s' "$val" > "$path"; } 2>/dev/null ;;
        *) { echo "$val" > "$path"; } 2>/dev/null ;;
    esac
}

sysfs_safe_write() {
    local path="$1"
    local val="$2"
    local allowed_file="${3:-}"
    local bkp_file="$KGX_DATA_DIR/state/sysfs_backup.tsv"
    local orig_val active_tok cur_val cur_cmp tok found

    [ -n "$path" ] && [ -n "$val" ] || return 1
    if kgx_is_protected_sysfs "$path"; then
        kgx_log "WARN" "safety" "Blocked write to protected thermal/voltage sysfs node: $path"
        return 1
    fi
    [ -e "$path" ] || return 1

    # Validate against kernel's available values list if supplied
    if [ -n "$allowed_file" ] && [ -r "$allowed_file" ]; then
        found=0
        for tok in $(tr -d '[]' < "$allowed_file" 2>/dev/null); do
            if [ "$tok" = "$val" ]; then
                found=1
                break
            fi
        done
        if [ "$found" -eq 0 ]; then
            kgx_log "WARN" "sysfs" "Rejected invalid value '$val' for $path (not in $allowed_file)"
            return 1
        fi
    fi

    cur_val=""
    if [ -r "$path" ]; then
        { IFS= read -r cur_val < "$path"; } 2>/dev/null || true
        case "$cur_val" in
            *"$KGX_CR") cur_val="${cur_val%$KGX_CR}" ;;
        esac
    fi
    cur_cmp="$cur_val"
    case "$path" in
        */queue/scheduler)
            active_tok="$(printf '%s' "$cur_val" | sed -n 's/.*\[\([^]]*\)\].*/\1/p')"
            [ -n "$active_tok" ] && cur_cmp="$active_tok"
            ;;
    esac

    # Record original value once (first-write wins)
    mkdir -p "$KGX_DATA_DIR/state" 2>/dev/null || true
    if [ ! -f "$bkp_file" ] || ! awk -F '\t' -v p="$path" '$1==p{f=1} END{exit !f}' "$bkp_file"; then
        orig_val="$cur_cmp"
        if [ -n "$orig_val" ]; then
            printf '%s\t%s\n' "$path" "$orig_val" >> "$bkp_file"
        fi
    fi

    # Skip redundant write when node already holds target value
    if [ -n "$cur_cmp" ] && [ "$cur_cmp" = "$val" ]; then
        return 0
    fi

    [ -w "$path" ] || chmod 0664 "$path" 2>/dev/null || true
    [ -w "$path" ] || return 1

    if ! kgx_write_node "$path" "$val"; then
        chmod 0664 "$path" 2>/dev/null || true
        if ! kgx_write_node "$path" "$val"; then
            kgx_log "WARN" "sysfs" "Write failed for $path=$val"
            return 1
        fi
    fi
    return 0
}

sysfs_restore_all() {
    local bkp_file="$KGX_DATA_DIR/state/sysfs_backup.tsv"
    local path orig_val
    [ -f "$bkp_file" ] || return 0

    awk '{a[NR]=$0} END{for(i=NR;i>=1;i--) print a[i]}' "$bkp_file" | \
    while IFS='	' read -r path orig_val || [ -n "$path" ]; do
        [ -n "$path" ] && [ -n "$orig_val" ] || continue
        kgx_is_protected_sysfs "$path" && continue
        [ -w "$path" ] || chmod 0664 "$path" 2>/dev/null || true
        if [ -w "$path" ]; then
            kgx_write_node "$path" "$orig_val" || { chmod 0664 "$path" 2>/dev/null || true; kgx_write_node "$path" "$orig_val" || true; }
        fi
    done
    rm -f "$bkp_file"
    return 0
}

kgx_is_zygisk_active() {
    local d
    for d in zygisksu rezygisk zygisk_lsposed neozygisk; do
        if [ -d "$KGX_MODULES_ROOT/$d" ] && [ ! -e "$KGX_MODULES_ROOT/$d/disable" ] && [ ! -e "$KGX_MODULES_ROOT/$d/remove" ]; then
            return 0
        fi
    done
    return 1
}

# Never redirect /proc/<pid>/cmdline directly into Android toybox tr (spins at 98% CPU on ESRCH).
kgx_read_cmdline() {
    [ -r "$1" ] || return 1
    cat "$1" 2>/dev/null | tr '\0' ' '
}

kgx_kill_stale_daemons() {
    local pdir pid cmd killed=0
    for pdir in "$KGX_PROC_ROOT"/[0-9]*; do
        pid="${pdir##*/}"
        [ "$pid" = "$$" ] && continue
        [ -r "$pdir/cmdline" ] || continue
        cmd="$(kgx_read_cmdline "$pdir/cmdline")"
        case "$cmd" in
            *gaming_daemon.sh*|*kgx-core*daemon*)
                kill "$pid" 2>/dev/null || true
                killed=$((killed + 1))
                ;;
        esac
    done
    if [ "$killed" -gt 0 ]; then
        sleep 1
        for pdir in "$KGX_PROC_ROOT"/[0-9]*; do
            pid="${pdir##*/}"
            [ "$pid" = "$$" ] && continue
            [ -r "$pdir/cmdline" ] || continue
            cmd="$(kgx_read_cmdline "$pdir/cmdline")"
            case "$cmd" in
                *gaming_daemon.sh*|*kgx-core*daemon*) kill -9 "$pid" 2>/dev/null || true ;;
            esac
        done
        kgx_log "INFO" "daemon" "Cleaned $killed stale daemon instance(s)."
    fi
}
