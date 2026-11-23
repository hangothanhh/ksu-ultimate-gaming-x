#!/system/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# KSU Ultimate Gaming X - Safe RAM & Background Optimizer

ram_get_metrics() {
    local mi="$KGX_PROC_ROOT/meminfo"
    local psi="$KGX_PROC_ROOT/pressure/memory"
    local total_kb=0 avail_kb=0 swap_tot_kb=0 swap_free_kb=0
    local total_mb=0 avail_mb=0 used_mb=0 used_pct=0 avail_pct=100
    local psi_some="0.00" psi_full="0.00" level="LOW"

    if [ -r "$mi" ]; then
        total_kb="$(awk '/^MemTotal:/{print $2; exit}' "$mi" 2>/dev/null)"
        avail_kb="$(awk '/^MemAvailable:/{print $2; exit}' "$mi" 2>/dev/null)"
        [ -n "$avail_kb" ] || avail_kb="$(awk '/^MemFree:/{print $2; exit}' "$mi" 2>/dev/null)"
        swap_tot_kb="$(awk '/^SwapTotal:/{print $2; exit}' "$mi" 2>/dev/null)"
        swap_free_kb="$(awk '/^SwapFree:/{print $2; exit}' "$mi" 2>/dev/null)"
    fi

    total_kb="${total_kb:-0}"; avail_kb="${avail_kb:-0}"
    swap_tot_kb="${swap_tot_kb:-0}"; swap_free_kb="${swap_free_kb:-0}"

    if [ "$total_kb" -gt 0 ] 2>/dev/null; then
        total_mb=$((total_kb / 1024))
        avail_mb=$((avail_kb / 1024))
        used_mb=$((total_mb - avail_mb))
        used_pct=$(((used_mb * 100) / total_mb))
        avail_pct=$(((avail_kb * 100) / total_kb))
    fi

    if [ -r "$psi" ]; then
        psi_some="$(awk '/^some /{for(i=1;i<=NF;i++) if($i~/^avg10=/){sub(/^avg10=/,"",$i); print $i; exit}}' "$psi" 2>/dev/null)"
        psi_full="$(awk '/^full /{for(i=1;i<=NF;i++) if($i~/^avg10=/){sub(/^avg10=/,"",$i); print $i; exit}}' "$psi" 2>/dev/null)"
    fi
    [ -n "$psi_some" ] || psi_some="0.00"
    [ -n "$psi_full" ] || psi_full="0.00"

    if [ "$avail_pct" -lt 15 ] || awk -v f="$psi_full" 'BEGIN{exit !(f+0 >= 15)}'; then
        level="CRITICAL"
    elif [ "$avail_pct" -lt 25 ] || awk -v s="$psi_some" 'BEGIN{exit !(s+0 >= 25)}'; then
        level="HIGH"
    elif [ "$avail_pct" -lt 40 ] || awk -v s="$psi_some" 'BEGIN{exit !(s+0 >= 10)}'; then
        level="MODERATE"
    else
        level="LOW"
    fi

    printf '%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
        "$total_mb" "$avail_mb" "$used_mb" "$used_pct" \
        $((swap_tot_kb / 1024)) $((swap_free_kb / 1024)) \
        "$psi_some" "$psi_full" "$level"
}

ram_is_protected_pkg() {
    local pkg="$1"
    local active_pkg="$2"
    local plist="$KGX_MODDIR/data/protected_pkgs.list"

    [ "$pkg" = "$active_pkg" ] && return 0
    case "$pkg" in
        com.android.*|com.google.android.gms*|com.google.android.gsf*|android|\
        me.weishu.kernelsu*|com.rifsxd.ksunext*|me.bmax.apatch*|com.topjohnwu.magisk*|\
        *inputmethod*|*launcher*|*telecom*|*systemui*)
            return 0
            ;;
    esac
    if [ -f "$plist" ] && grep -qx "$pkg" "$plist" 2>/dev/null; then
        return 0
    fi
    return 1
}

ram_apply() {
    local mode="${1:-high_performance}"
    local active_pkg="${2:-}"
    local metrics level total_mb avail_mb vm_dir swap_val vfs_val
    local trimmed=0 cdir cmd_pkg

    [ "${RAM_OPT_ENABLED:-1}" = "1" ] || return 0
    hw_load

    metrics="$(ram_get_metrics)"
    total_mb="$(printf '%s\n' "$metrics" | cut -d'|' -f1)"
    avail_mb="$(printf '%s\n' "$metrics" | cut -d'|' -f2)"
    level="$(printf '%s\n' "$metrics" | cut -d'|' -f9)"

    # 1. Safe bounded VM reclaim settings (never swappiness=0 if zRAM active)
    vm_dir="$KGX_PROC_ROOT/sys/vm"
    if [ -d "$vm_dir" ]; then
        if [ "${HAS_ZRAM:-0}" = "1" ]; then
            swap_val=60
        else
            swap_val=40
        fi
        case "$mode" in
            extreme_gaming) vfs_val=85 ;;
            high_performance) vfs_val=95 ;;
            *) vfs_val=100 ;;
        esac
        [ -w "$vm_dir/swappiness" ] && sysfs_safe_write "$vm_dir/swappiness" "$swap_val" || true
        [ -w "$vm_dir/vfs_cache_pressure" ] && sysfs_safe_write "$vm_dir/vfs_cache_pressure" "$vfs_val" || true
    fi

    # 2. Safe background trim under Moderate/High/Critical pressure or gaming modes
    if [ "$level" != "LOW" ] || [ "$mode" = "high_performance" ] || [ "$mode" = "extreme_gaming" ]; then
        if command -v am >/dev/null 2>&1; then
            if [ "$KGX_PROC_ROOT" = "/proc" ] && [ -x "$KGX_MODDIR/bin/kgx-core" ]; then
                for cmd_pkg in $("$KGX_MODDIR/bin/kgx-core" trim-list "$active_pkg" 15 2>/dev/null); do
                    [ -n "$cmd_pkg" ] || continue
                    am send-trim-memory "$cmd_pkg" RUNNING_LOW >/dev/null 2>&1 || true
                    trimmed=$((trimmed + 1))
                    [ "$trimmed" -ge 15 ] && break
                done
            else
                for cdir in "$KGX_PROC_ROOT"/[0-9]*; do
                    [ -r "$cdir/cmdline" ] || continue
                    cmd_pkg="$(kgx_read_cmdline "$cdir/cmdline" | awk '{print $1}')"
                    case "$cmd_pkg" in
                        *.* ) ;;
                        * ) continue ;;
                    esac
                    # Strip process suffix (e.g. pkg:service -> pkg)
                    cmd_pkg="${cmd_pkg%%:*}"
                    kgx_sanitize_pkg "$cmd_pkg" || continue
                    ram_is_protected_pkg "$cmd_pkg" "$active_pkg" && continue
                    am send-trim-memory "$cmd_pkg" RUNNING_LOW >/dev/null 2>&1 || true
                    trimmed=$((trimmed + 1))
                    [ "$trimmed" -ge 15 ] && break
                done
            fi
        fi
    fi

    kgx_log "INFO" "ram" "RAM pressure=$level (${avail_mb}/${total_mb} MB free), trimmed=$trimmed non-protected bg procs."
    return 0
}

ram_restore() {
    # Handled via sysfs_restore_all cleanly; log explicitly if called standalone
    kgx_log "INFO" "ram" "RAM VM tuning restored on session exit."
    return 0
}
