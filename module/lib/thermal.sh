#!/system/bin/sh
# KSU Ultimate Gaming X v3.0 - Smart Adaptive Thermal Engine + Sustained Anti-Lag Relief

thermal_normalize_c() {
    local raw="$1"
    raw="${raw%%.*}"
    raw="$(printf '%s' "$raw" | tr -dc '0-9-')"
    [ -n "$raw" ] || { printf '0\n'; return 0; }
    if [ "$raw" -ge 10000 ] 2>/dev/null || [ "$raw" -le -10000 ] 2>/dev/null; then
        printf '%s\n' $((raw / 1000))
    elif [ "$raw" -ge 150 ] 2>/dev/null; then
        printf '%s\n' $((raw / 10))
    else
        printf '%s\n' "$raw"
    fi
}

thermal_read_temps() {
    local batt_c=0 cpu_c=0 gpu_c=0 raw
    hw_load

    if [ -n "$THERMAL_BATT_NODE" ] && [ -r "$THERMAL_BATT_NODE" ]; then
        raw="$(cat "$THERMAL_BATT_NODE" 2>/dev/null | head -n 1)"
        batt_c="$(thermal_normalize_c "$raw")"
    fi
    if [ -n "$THERMAL_CPU_NODE" ] && [ -r "$THERMAL_CPU_NODE" ]; then
        raw="$(cat "$THERMAL_CPU_NODE" 2>/dev/null | head -n 1)"
        cpu_c="$(thermal_normalize_c "$raw")"
    fi
    if [ -n "$THERMAL_GPU_NODE" ] && [ -r "$THERMAL_GPU_NODE" ]; then
        raw="$(cat "$THERMAL_GPU_NODE" 2>/dev/null | head -n 1)"
        gpu_c="$(thermal_normalize_c "$raw")"
    fi
    [ "$gpu_c" -eq 0 ] 2>/dev/null && gpu_c="$cpu_c"

    printf '%s|%s|%s\n' "$batt_c" "$cpu_c" "$gpu_c"
}

thermal_ceiling_nodes_list() {
    local p
    hw_load
    if [ -n "$EXYNOS_UFCC_DIR" ]; then
        printf '%s\n' \
            "$EXYNOS_UFCC_DIR/cpufreq_max_limit" \
            "$EXYNOS_UFCC_DIR/little_max_limit" \
            "$EXYNOS_UFCC_DIR/over_limit"
    fi
    if [ -n "$EXYNOS_GPU_DIR" ]; then
        printf '%s\n' \
            "$EXYNOS_GPU_DIR/gpu_max_clock" \
            "$EXYNOS_GPU_DIR/gpu_siop_max_clock" \
            "$EXYNOS_GPU_DIR/gpu_governor"
    fi
    if [ -n "$GPU_DEVFREQ_DIR" ]; then
        printf '%s\n' "$GPU_DEVFREQ_DIR/max_freq"
    fi
    if [ -n "$EXYNOS_MIGOV_DIR" ]; then
        printf '%s\n' \
            "$EXYNOS_MIGOV_DIR/migov/disable" \
            "$EXYNOS_MIGOV_DIR/cl0/cl0_pm_qos_max_freq" \
            "$EXYNOS_MIGOV_DIR/cl1/cl1_pm_qos_max_freq" \
            "$EXYNOS_MIGOV_DIR/cl2/cl2_pm_qos_max_freq" \
            "$EXYNOS_MIGOV_DIR/gpu/gpu_pm_qos_max_freq" \
            "$EXYNOS_MIGOV_DIR/mif/mif_pm_qos_max_freq"
    fi
    if [ -n "$EXYNOS_DSU_DIR" ]; then
        printf '%s\n' "$EXYNOS_DSU_DIR/scaling_max_freq"
    fi
    if [ -d "$KGX_SYS_ROOT/devices/system/cpu/cpufreq" ]; then
        for p in "$KGX_SYS_ROOT/devices/system/cpu/cpufreq"/policy*; do
            [ -d "$p" ] && printf '%s\n' "$p/scaling_max_freq"
        done
    fi
}

thermal_unlock_sysfs_ceilings() {
    local perm_bkp="$KGX_DATA_DIR/state/sysfs_perm_backup.tsv"
    local path orig_mode
    if [ -f "$perm_bkp" ]; then
        while IFS='	' read -r path orig_mode || [ -n "$path" ]; do
            [ -n "$path" ] || continue
            kgx_is_protected_sysfs "$path" && continue
            [ -e "$path" ] || continue
            case "$orig_mode" in
                ''|*[!0-9]*|444|0444) orig_mode="0664" ;;
            esac
            chmod "$orig_mode" "$path" 2>/dev/null || chmod 0664 "$path" 2>/dev/null || true
        done < "$perm_bkp"
        rm -f "$perm_bkp" 2>/dev/null || true
    fi
    for path in $(thermal_ceiling_nodes_list); do
        [ -e "$path" ] || continue
        kgx_is_protected_sysfs "$path" && continue
        [ -w "$path" ] || chmod 0664 "$path" 2>/dev/null || true
    done
    return 0
}

thermal_reassert_node() {
    local p="$1" target="$2" cur=""
    [ -n "$p" ] && [ -n "$target" ] && [ -e "$p" ] || return 0
    if [ -r "$p" ]; then
        { IFS= read -r cur < "$p"; } 2>/dev/null || true
        case "$cur" in *"$KGX_CR") cur="${cur%$KGX_CR}" ;; esac
    fi
    [ "$cur" = "$target" ] && return 0
    if ! kgx_write_node "$p" "$target"; then
        chmod 0664 "$p" 2>/dev/null || true
        kgx_write_node "$p" "$target" || true
    fi
}

thermal_lock_sysfs_ceilings() {
    local perm_bkp="$KGX_DATA_DIR/state/sysfs_perm_backup.tsv"
    local ceil_file="$KGX_DATA_DIR/state/unlocked_ceilings.env"
    local p orig_mode locked=0
    local UNLOCK_GMAX="" UNLOCK_C0MAX="" UNLOCK_C1MAX="" UNLOCK_C2MAX="" UNLOCK_MIFMAX="" UNLOCK_DSUMAX=""

    [ "${THERMAL_UNLOCK:-0}" = "1" ] || [ "${SUSTAINED_SWEET_SPOT:-0}" = "1" ] || return 0
    mkdir -p "$KGX_DATA_DIR/state" 2>/dev/null || true

    # Zero-fork re-assert immediately before chmod 0444 so SIOP cannot race a lower cap under the lock
    if [ -f "$ceil_file" ]; then
        . "$ceil_file"
        [ -n "$EXYNOS_UFCC_DIR" ] && thermal_reassert_node "$EXYNOS_UFCC_DIR/cpufreq_max_limit" "-1"
        if [ -n "$EXYNOS_GPU_DIR" ] && [ -n "$UNLOCK_GMAX" ]; then
            thermal_reassert_node "$EXYNOS_GPU_DIR/gpu_siop_max_clock" "$UNLOCK_GMAX"
            thermal_reassert_node "$EXYNOS_GPU_DIR/gpu_max_clock" "$UNLOCK_GMAX"
        fi
        [ -n "$GPU_DEVFREQ_DIR" ] && [ -n "$UNLOCK_GMAX" ] && thermal_reassert_node "$GPU_DEVFREQ_DIR/max_freq" "$UNLOCK_GMAX"
        [ -n "$CPU_LITTLE_POLICY" ] && [ -n "$UNLOCK_C0MAX" ] && thermal_reassert_node "$KGX_SYS_ROOT/devices/system/cpu/cpufreq/$CPU_LITTLE_POLICY/scaling_max_freq" "$UNLOCK_C0MAX"
        [ -n "$CPU_MID_POLICY" ] && [ -n "$UNLOCK_C1MAX" ] && thermal_reassert_node "$KGX_SYS_ROOT/devices/system/cpu/cpufreq/$CPU_MID_POLICY/scaling_max_freq" "$UNLOCK_C1MAX"
        [ -n "$CPU_BIG_POLICY" ] && [ -n "$UNLOCK_C2MAX" ] && thermal_reassert_node "$KGX_SYS_ROOT/devices/system/cpu/cpufreq/$CPU_BIG_POLICY/scaling_max_freq" "$UNLOCK_C2MAX"
    fi

    for p in $(thermal_ceiling_nodes_list); do
        [ -e "$p" ] || continue
        kgx_is_protected_sysfs "$p" && continue
        if [ ! -f "$perm_bkp" ] || ! awk -F '\t' -v k="$p" '$1==k{f=1} END{exit !f}' "$perm_bkp" 2>/dev/null; then
            orig_mode="$(stat -c '%a' "$p" 2>/dev/null | tr -dc '0-9')"
            case "$orig_mode" in
                ''|*[!0-9]*|444|0444) orig_mode="0664" ;;
            esac
            printf '%s\t%s\n' "$p" "$orig_mode" >> "$perm_bkp"
        fi
        chmod 0444 "$p" 2>/dev/null && locked=$((locked + 1)) || true
    done
    return 0
}

thermal_pick_step_pct() {
    local freq_file="$1" pct="${2:-100}"
    [ -r "$freq_file" ] || return 1
    tr ' ' '\n' < "$freq_file" 2>/dev/null | grep -E '^[0-9]+$' | sort -n -u | awk -v p="$pct" '
    { a[n++] = $1 }
    END {
        if (n == 0) exit 1
        idx = int(((n - 1) * p) / 100 + 0.5)
        if (idx < 0) idx = 0
        if (idx >= n) idx = n - 1
        print a[idx]
    }'
}

thermal_pol_max_freq() {
    local pol="$1" pct="${2:-100}" pdir val=""
    [ -n "$pol" ] || return 1
    pdir="$KGX_SYS_ROOT/devices/system/cpu/cpufreq/$pol"
    [ -d "$pdir" ] || return 1
    if [ "$pct" -lt 100 ] 2>/dev/null && [ -r "$pdir/scaling_available_frequencies" ]; then
        val="$(thermal_pick_step_pct "$pdir/scaling_available_frequencies" "$pct" 2>/dev/null || true)"
    fi
    if [ -z "$val" ] && [ -r "$pdir/cpuinfo_max_freq" ]; then
        val="$(cat "$pdir/cpuinfo_max_freq" 2>/dev/null | head -n 1 | tr -dc '0-9')"
    fi
    if [ -z "$val" ] && [ -r "$pdir/scaling_available_frequencies" ]; then
        val="$(thermal_pick_step_pct "$pdir/scaling_available_frequencies" "$pct" 2>/dev/null || true)"
    fi
    [ -n "$val" ] && printf '%s\n' "$val"
}

thermal_mif_max_freq() {
    local d val=""
    [ -d "$KGX_SYS_ROOT/class/devfreq" ] || return 1
    for d in "$KGX_SYS_ROOT/class/devfreq"/*devfreq_mif*; do
        [ -d "$d" ] && [ -r "$d/available_frequencies" ] || continue
        val="$(tr ' ' '\n' < "$d/available_frequencies" 2>/dev/null | grep -E '^[0-9]+$' | sort -n | tail -n 1)"
        if [ -n "$val" ]; then
            printf '%s\n' "$val"
            return 0
        fi
    done
    return 1
}

thermal_dsu_max_freq() {
    local val=""
    [ -n "$EXYNOS_DSU_DIR" ] && [ -r "$EXYNOS_DSU_DIR/available_frequencies" ] || return 1
    val="$(tr ' ' '\n' < "$EXYNOS_DSU_DIR/available_frequencies" 2>/dev/null | grep -E '^[0-9]+$' | sort -n | tail -n 1)"
    [ -n "$val" ] && printf '%s\n' "$val"
}

thermal_apply_unlock() {
    local orig_file="$KGX_DATA_DIR/state/orig_thermal_unlock.env"
    local ceil_file="$KGX_DATA_DIR/state/unlocked_ceilings.env"
    local orig_gatc="null" orig_secr="null" orig_glpm="null" orig_rdp="null"
    local gmax="" c0max="" c1max="" c2max="" mifmax="" dsumax=""
    local mid_pct=100 big_pct=100 gpu_pct=100

    [ "${THERMAL_UNLOCK:-0}" = "1" ] || [ "${SUSTAINED_SWEET_SPOT:-0}" = "1" ] || return 0
    hw_load

    if [ "${SUSTAINED_SWEET_SPOT:-0}" = "1" ]; then
        mid_pct=88
        big_pct=82
        gpu_pct=82
    fi

    thermal_unlock_sysfs_ceilings

    if [ ! -f "$orig_file" ]; then
        mkdir -p "$KGX_DATA_DIR/state" 2>/dev/null || true
        if command -v settings >/dev/null 2>&1; then
            orig_gatc="$(settings get secure game_auto_temperature_control 2>/dev/null | tr -d '\r')"
            orig_secr="$(settings get system sem_enhanced_cpu_responsiveness 2>/dev/null | tr -d '\r')"
            orig_glpm="$(settings get secure game_low_power_mode 2>/dev/null | tr -d '\r')"
            orig_rdp="$(settings get global restricted_device_performance 2>/dev/null | tr -d '\r')"
        fi
        cat > "$orig_file" <<EOF
ORIG_GATC='${orig_gatc:-null}'
ORIG_SECR='${orig_secr:-null}'
ORIG_GLPM='${orig_glpm:-null}'
ORIG_RDP='${orig_rdp:-null}'
EOF
    fi

    if command -v cmd >/dev/null 2>&1; then
        cmd thermalservice override-status 0 >/dev/null 2>&1 || true
        cmd power set-fixed-performance-mode-enabled true >/dev/null 2>&1 || true
    fi
    if command -v settings >/dev/null 2>&1; then
        settings put secure game_auto_temperature_control 0 >/dev/null 2>&1 || true
        settings put system sem_enhanced_cpu_responsiveness 1 >/dev/null 2>&1 || true
        settings put secure game_low_power_mode 0 >/dev/null 2>&1 || true
        settings put global restricted_device_performance 0,0 >/dev/null 2>&1 || true
    fi

    # Lift Exynos UFCC software thermal ceilings & clear stove min lock
    if [ -n "$EXYNOS_UFCC_DIR" ]; then
        [ -w "$EXYNOS_UFCC_DIR/cpufreq_max_limit" ] && sysfs_safe_write "$EXYNOS_UFCC_DIR/cpufreq_max_limit" "-1" || true
        [ -w "$EXYNOS_UFCC_DIR/cpufreq_min_limit" ] && sysfs_safe_write "$EXYNOS_UFCC_DIR/cpufreq_min_limit" "-1" || true
        [ -w "$EXYNOS_UFCC_DIR/little_max_limit" ] && sysfs_safe_write "$EXYNOS_UFCC_DIR/little_max_limit" "-1" || true
        [ -w "$EXYNOS_UFCC_DIR/over_limit" ] && sysfs_safe_write "$EXYNOS_UFCC_DIR/over_limit" "-1" || true
    fi

    if [ -n "$EXYNOS_GPU_DIR" ] && [ -r "$EXYNOS_GPU_DIR/gpu_freq_table" ]; then
        gmax="$(thermal_pick_step_pct "$EXYNOS_GPU_DIR/gpu_freq_table" "$gpu_pct" 2>/dev/null || true)"
        if [ -n "$gmax" ]; then
            [ -w "$EXYNOS_GPU_DIR/gpu_siop_max_clock" ] && sysfs_safe_write "$EXYNOS_GPU_DIR/gpu_siop_max_clock" "$gmax" "$EXYNOS_GPU_DIR/gpu_freq_table" || true
            [ -w "$EXYNOS_GPU_DIR/gpu_max_clock" ] && sysfs_safe_write "$EXYNOS_GPU_DIR/gpu_max_clock" "$gmax" "$EXYNOS_GPU_DIR/gpu_freq_table" || true
        fi
    elif [ -n "$GPU_DEVFREQ_DIR" ] && [ -r "$GPU_DEVFREQ_DIR/available_frequencies" ]; then
        gmax="$(thermal_pick_step_pct "$GPU_DEVFREQ_DIR/available_frequencies" "$gpu_pct" 2>/dev/null || true)"
    fi
    if [ -n "$gmax" ] && [ -n "$GPU_DEVFREQ_DIR" ] && [ -w "$GPU_DEVFREQ_DIR/max_freq" ]; then
        sysfs_safe_write "$GPU_DEVFREQ_DIR/max_freq" "$gmax" "$GPU_DEVFREQ_DIR/available_frequencies" || true
    fi

    c0max="$(thermal_pol_max_freq "$CPU_LITTLE_POLICY" 100 2>/dev/null || true)"
    c1max="$(thermal_pol_max_freq "$CPU_MID_POLICY" "$mid_pct" 2>/dev/null || true)"
    c2max="$(thermal_pol_max_freq "$CPU_BIG_POLICY" "$big_pct" 2>/dev/null || true)"
    mifmax="$(thermal_mif_max_freq 2>/dev/null || true)"
    dsumax="$(thermal_dsu_max_freq 2>/dev/null || true)"

    if [ -n "$dsumax" ] && [ -n "$EXYNOS_DSU_DIR" ] && [ -w "$EXYNOS_DSU_DIR/scaling_max_freq" ]; then
        sysfs_safe_write "$EXYNOS_DSU_DIR/scaling_max_freq" "$dsumax" "$EXYNOS_DSU_DIR/available_frequencies" || true
    fi

    # Lift Exynos MIGOV PM QoS ceilings
    if [ -n "$EXYNOS_MIGOV_DIR" ]; then
        [ -w "$EXYNOS_MIGOV_DIR/migov/disable" ] && sysfs_safe_write "$EXYNOS_MIGOV_DIR/migov/disable" "1" || true
        [ -n "$c0max" ] && [ -w "$EXYNOS_MIGOV_DIR/cl0/cl0_pm_qos_max_freq" ] && sysfs_safe_write "$EXYNOS_MIGOV_DIR/cl0/cl0_pm_qos_max_freq" "$c0max" || true
        [ -n "$c1max" ] && [ -w "$EXYNOS_MIGOV_DIR/cl1/cl1_pm_qos_max_freq" ] && sysfs_safe_write "$EXYNOS_MIGOV_DIR/cl1/cl1_pm_qos_max_freq" "$c1max" || true
        [ -n "$c2max" ] && [ -w "$EXYNOS_MIGOV_DIR/cl2/cl2_pm_qos_max_freq" ] && sysfs_safe_write "$EXYNOS_MIGOV_DIR/cl2/cl2_pm_qos_max_freq" "$c2max" || true
        [ -n "$gmax" ] && [ -w "$EXYNOS_MIGOV_DIR/gpu/gpu_pm_qos_max_freq" ] && sysfs_safe_write "$EXYNOS_MIGOV_DIR/gpu/gpu_pm_qos_max_freq" "$gmax" || true
        [ -n "$mifmax" ] && [ -w "$EXYNOS_MIGOV_DIR/mif/mif_pm_qos_max_freq" ] && sysfs_safe_write "$EXYNOS_MIGOV_DIR/mif/mif_pm_qos_max_freq" "$mifmax" || true
    fi

    cat > "$ceil_file" <<EOF
UNLOCK_GMAX='${gmax}'
UNLOCK_C0MAX='${c0max}'
UNLOCK_C1MAX='${c1max}'
UNLOCK_C2MAX='${c2max}'
UNLOCK_MIFMAX='${mifmax}'
UNLOCK_DSUMAX='${dsumax}'
EOF

    kgx_log "WARN" "thermal" "Thermal ceiling control active (unlock=${THERMAL_UNLOCK:-0}, sweet=${SUSTAINED_SWEET_SPOT:-0}): c1=$c1max c2=$c2max gmax=$gmax (silicon trip_points intact)."
    return 0
}

thermal_defend_unlock_fast() {
    local ceil_file="$KGX_DATA_DIR/state/unlocked_ceilings.env"
    local UNLOCK_GMAX="" UNLOCK_C0MAX="" UNLOCK_C1MAX="" UNLOCK_C2MAX="" UNLOCK_MIFMAX="" UNLOCK_DSUMAX=""
    local cur_val max_chk p breached=0

    hw_load
    [ -f "$ceil_file" ] && . "$ceil_file"

    if [ -n "$EXYNOS_UFCC_DIR" ] && [ -r "$EXYNOS_UFCC_DIR/cpufreq_max_limit" ]; then
        cur_val="$(cat "$EXYNOS_UFCC_DIR/cpufreq_max_limit" 2>/dev/null | head -n 1 | tr -d '\r')"
        [ "$cur_val" != "-1" ] && breached=1
    fi
    if [ -n "$EXYNOS_GPU_DIR" ] && [ -n "$UNLOCK_GMAX" ] && [ -r "$EXYNOS_GPU_DIR/gpu_max_clock" ]; then
        cur_val="$(cat "$EXYNOS_GPU_DIR/gpu_max_clock" 2>/dev/null | head -n 1 | tr -d '\r')"
        [ "$cur_val" != "$UNLOCK_GMAX" ] && breached=1
    fi
    if [ -n "$GPU_DEVFREQ_DIR" ] && [ -n "$UNLOCK_GMAX" ] && [ -r "$GPU_DEVFREQ_DIR/max_freq" ]; then
        cur_val="$(cat "$GPU_DEVFREQ_DIR/max_freq" 2>/dev/null | head -n 1 | tr -d '\r')"
        [ "$cur_val" != "$UNLOCK_GMAX" ] && breached=1
    fi
    if [ "$breached" -eq 0 ] && [ -n "$CPU_BIG_POLICY" ]; then
        p="$KGX_SYS_ROOT/devices/system/cpu/cpufreq/$CPU_BIG_POLICY"
        if [ -r "$p/scaling_max_freq" ] && [ -n "$UNLOCK_C2MAX" ]; then
            cur_val="$(cat "$p/scaling_max_freq" 2>/dev/null | head -n 1 | tr -dc '0-9')"
            max_chk="$UNLOCK_C2MAX"
            [ -n "$cur_val" ] && [ "$cur_val" -lt "$max_chk" ] 2>/dev/null && breached=1
        fi
    fi

    [ "$breached" -eq 0 ] && return 0

    thermal_unlock_sysfs_ceilings
    [ -n "$EXYNOS_UFCC_DIR" ] && [ -w "$EXYNOS_UFCC_DIR/cpufreq_max_limit" ] && sysfs_safe_write "$EXYNOS_UFCC_DIR/cpufreq_max_limit" "-1" || true
    if [ -n "$EXYNOS_GPU_DIR" ] && [ -n "$UNLOCK_GMAX" ]; then
        [ -w "$EXYNOS_GPU_DIR/gpu_siop_max_clock" ] && sysfs_safe_write "$EXYNOS_GPU_DIR/gpu_siop_max_clock" "$UNLOCK_GMAX" "$EXYNOS_GPU_DIR/gpu_freq_table" || true
        [ -w "$EXYNOS_GPU_DIR/gpu_max_clock" ] && sysfs_safe_write "$EXYNOS_GPU_DIR/gpu_max_clock" "$UNLOCK_GMAX" "$EXYNOS_GPU_DIR/gpu_freq_table" || true
    fi
    if [ -n "$GPU_DEVFREQ_DIR" ] && [ -n "$UNLOCK_GMAX" ] && [ -w "$GPU_DEVFREQ_DIR/max_freq" ]; then
        sysfs_safe_write "$GPU_DEVFREQ_DIR/max_freq" "$UNLOCK_GMAX" "$GPU_DEVFREQ_DIR/available_frequencies" || true
    fi
    if [ -n "$CPU_LITTLE_POLICY" ] && [ -n "$UNLOCK_C0MAX" ]; then
        sysfs_safe_write "$KGX_SYS_ROOT/devices/system/cpu/cpufreq/$CPU_LITTLE_POLICY/scaling_max_freq" "$UNLOCK_C0MAX" || true
    fi
    if [ -n "$CPU_MID_POLICY" ] && [ -n "$UNLOCK_C1MAX" ]; then
        sysfs_safe_write "$KGX_SYS_ROOT/devices/system/cpu/cpufreq/$CPU_MID_POLICY/scaling_max_freq" "$UNLOCK_C1MAX" || true
    fi
    if [ -n "$CPU_BIG_POLICY" ] && [ -n "$UNLOCK_C2MAX" ]; then
        sysfs_safe_write "$KGX_SYS_ROOT/devices/system/cpu/cpufreq/$CPU_BIG_POLICY/scaling_max_freq" "$UNLOCK_C2MAX" || true
    fi
    thermal_lock_sysfs_ceilings
    kgx_log "WARN" "thermal" "Re-locked SDHMS/SIOP sysfs ceilings after external modification."
    return 0
}

thermal_restore_unlock() {
    local orig_file="$KGX_DATA_DIR/state/orig_thermal_unlock.env"

    thermal_unlock_sysfs_ceilings
    rm -f "$KGX_DATA_DIR/state/unlocked_ceilings.env" "$KGX_DATA_DIR/state/soft_step.tier" 2>/dev/null || true

    if command -v cmd >/dev/null 2>&1; then
        cmd thermalservice reset >/dev/null 2>&1 || true
        cmd power set-fixed-performance-mode-enabled false >/dev/null 2>&1 || true
    fi

    if [ -f "$orig_file" ]; then
        . "$orig_file"
        if command -v settings >/dev/null 2>&1; then
            if [ -z "${ORIG_GATC:-}" ] || [ "$ORIG_GATC" = "null" ]; then
                settings delete secure game_auto_temperature_control >/dev/null 2>&1 || true
            else
                settings put secure game_auto_temperature_control "$ORIG_GATC" >/dev/null 2>&1 || true
            fi
            if [ -z "${ORIG_SECR:-}" ] || [ "$ORIG_SECR" = "null" ]; then
                settings delete system sem_enhanced_cpu_responsiveness >/dev/null 2>&1 || true
            else
                settings put system sem_enhanced_cpu_responsiveness "$ORIG_SECR" >/dev/null 2>&1 || true
            fi
            if [ -z "${ORIG_GLPM:-}" ] || [ "$ORIG_GLPM" = "null" ]; then
                settings delete secure game_low_power_mode >/dev/null 2>&1 || true
            else
                settings put secure game_low_power_mode "$ORIG_GLPM" >/dev/null 2>&1 || true
            fi
            if [ -z "${ORIG_RDP:-}" ] || [ "$ORIG_RDP" = "null" ]; then
                settings delete global restricted_device_performance >/dev/null 2>&1 || true
            else
                settings put global restricted_device_performance "$ORIG_RDP" >/dev/null 2>&1 || true
            fi
        fi
        rm -f "$orig_file" 2>/dev/null || true
    fi
    return 0
}

# Evaluates thermal stage with hysteresis (supports both Guard ladder and Unlocked Anti-TMU Relief)
# Output: stage|max_fps|mode_cap
thermal_evaluate_stage() {
    local batt_c="${1:-0}"
    local cpu_c="${2:-0}"
    local prev_stage="${3:-NORMAL}"
    local gpu_c="${4:-0}"
    local wb="${THERMAL_WARN_BATT:-38}"
    local hb="${THERMAL_HOT_BATT:-41}"
    local cb="${THERMAL_CRIT_BATT:-44}"
    local wc="${THERMAL_WARN_CPU:-68}"
    local hc="${THERMAL_HOT_CPU:-76}"
    local cc="${THERMAL_CRIT_CPU:-85}"
    local stage="NORMAL" max_fps=144 mode_cap="extreme_gaming"

    if [ "${SUSTAINED_SWEET_SPOT:-0}" = "1" ]; then
        if [ "$cpu_c" -ge 78 ] || [ "$gpu_c" -ge 76 ] || [ "$batt_c" -ge 43 ]; then
            printf 'SWEET_SPOT_COOL|144|high_performance\n'
        elif [ "$prev_stage" = "SWEET_SPOT_COOL" ] && { [ "$cpu_c" -gt 72 ] || [ "$gpu_c" -gt 70 ] || [ "$batt_c" -gt 41 ]; }; then
            printf 'SWEET_SPOT_COOL|144|high_performance\n'
        else
            printf 'SWEET_SPOT|144|high_performance\n'
        fi
        return 0
    fi

    if [ "${THERMAL_UNLOCK:-0}" = "1" ]; then
        if [ "$cpu_c" -ge 78 ] || [ "$gpu_c" -ge 76 ] || [ "$batt_c" -ge 43 ]; then
            printf 'UNLOCKED_COOL|144|extreme_gaming\n'
        elif [ "$prev_stage" = "UNLOCKED_COOL" ] && { [ "$cpu_c" -gt 72 ] || [ "$gpu_c" -gt 70 ] || [ "$batt_c" -gt 41 ]; }; then
            printf 'UNLOCKED_COOL|144|extreme_gaming\n'
        else
            printf 'UNLOCKED|144|extreme_gaming\n'
        fi
        return 0
    fi

    if [ "$batt_c" -ge "$cb" ] || [ "$cpu_c" -ge "$cc" ]; then
        stage="CRITICAL"
    elif [ "$batt_c" -ge "$hb" ] || [ "$cpu_c" -ge "$hc" ]; then
        stage="HOT"
    elif [ "$batt_c" -ge "$wb" ] || [ "$cpu_c" -ge "$wc" ]; then
        stage="WARM"
    else
        stage="NORMAL"
    fi

    case "$prev_stage:$stage" in
        CRITICAL:HOT|CRITICAL:WARM|CRITICAL:NORMAL)
            if [ "$batt_c" -gt $((cb - 2)) ] || [ "$cpu_c" -gt $((cc - 4)) ]; then
                stage="CRITICAL"
            fi
            ;;
        HOT:WARM|HOT:NORMAL)
            if [ "$batt_c" -gt $((hb - 2)) ] || [ "$cpu_c" -gt $((hc - 4)) ]; then
                stage="HOT"
            fi
            ;;
        WARM:NORMAL)
            if [ "$batt_c" -gt $((wb - 2)) ] || [ "$cpu_c" -gt $((wc - 4)) ]; then
                stage="WARM"
            fi
            ;;
    esac

    case "$stage" in
        CRITICAL)
            max_fps=60
            mode_cap="battery_gaming"
            ;;
        HOT)
            max_fps=90
            mode_cap="balanced"
            ;;
        WARM)
            max_fps=144
            mode_cap="high_performance"
            ;;
        *)
            max_fps=144
            mode_cap="extreme_gaming"
            ;;
    esac

    printf '%s|%s|%s\n' "$stage" "$max_fps" "$mode_cap"
}

thermal_cap_mode() {
    local requested="$1"
    local cap="$2"
    case "$cap" in
        battery_gaming) printf 'battery_gaming\n' ;;
        balanced)
            case "$requested" in
                battery_gaming) printf 'battery_gaming\n' ;;
                *) printf 'balanced\n' ;;
            esac
            ;;
        high_performance)
            case "$requested" in
                extreme_gaming) printf 'high_performance\n' ;;
                *) printf '%s\n' "$requested" ;;
            esac
            ;;
        *) printf '%s\n' "$requested" ;;
    esac
}

thermal_eval_soft_step() {
    local batt_c="${1:-0}" cpu_c="${2:-0}" prev_tier="${3:-0}" force_t2="${4:-0}"
    if [ "$force_t2" = "1" ]; then
        printf '2\n'
        return 0
    fi
    if [ "${SOFT_THERMAL_STEP:-0}" != "1" ]; then
        printf '0\n'
        return 0
    fi
    case "$prev_tier" in
        ''|*[!0-9]*) prev_tier=0 ;;
    esac
    if [ "$batt_c" -ge 43 ] 2>/dev/null || [ "$cpu_c" -ge 87 ] 2>/dev/null; then
        printf '2\n'
    elif [ "$prev_tier" -ge 2 ] && { [ "$batt_c" -gt 41 ] 2>/dev/null || [ "$cpu_c" -gt 82 ] 2>/dev/null; }; then
        printf '2\n'
    elif [ "$batt_c" -ge 41 ] 2>/dev/null || [ "$cpu_c" -ge 82 ] 2>/dev/null; then
        printf '1\n'
    elif [ "$prev_tier" -ge 1 ] && { [ "$batt_c" -gt 39 ] 2>/dev/null || [ "$cpu_c" -gt 77 ] 2>/dev/null; }; then
        printf '1\n'
    else
        printf '0\n'
    fi
}

thermal_apply_soft_step() {
    local tier="${1:-0}"
    local tier_file="$KGX_DATA_DIR/state/soft_step.tier"
    local ceil_file="$KGX_DATA_DIR/state/unlocked_ceilings.env"
    local base_mid=100 base_big=100 base_gpu=100 scale=100
    local mid_pct big_pct gpu_pct c0max="" c1max="" c2max="" gmax="" mifmax="" dsumax=""
    local UNLOCK_GMAX="" UNLOCK_C0MAX="" UNLOCK_C1MAX="" UNLOCK_C2MAX="" UNLOCK_MIFMAX="" UNLOCK_DSUMAX=""

    hw_load
    mkdir -p "$KGX_DATA_DIR/state" 2>/dev/null || true
    case "$tier" in
        1) scale=90 ;;
        2) scale=80 ;;
        *) tier=0; scale=100 ;;
    esac
    printf '%s\n' "$tier" > "$tier_file"

    if [ "${SUSTAINED_SWEET_SPOT:-0}" = "1" ]; then
        base_mid=88; base_big=82; base_gpu=82
    fi
    mid_pct=$(( (base_mid * scale) / 100 ))
    big_pct=$(( (base_big * scale) / 100 ))
    gpu_pct=$(( (base_gpu * scale) / 100 ))

    [ -f "$ceil_file" ] && . "$ceil_file"
    c0max="${UNLOCK_C0MAX:-$(thermal_pol_max_freq "$CPU_LITTLE_POLICY" 100 2>/dev/null || true)}"
    c1max="$(thermal_pol_max_freq "$CPU_MID_POLICY" "$mid_pct" 2>/dev/null || true)"
    c2max="$(thermal_pol_max_freq "$CPU_BIG_POLICY" "$big_pct" 2>/dev/null || true)"
    mifmax="${UNLOCK_MIFMAX:-$(thermal_mif_max_freq 2>/dev/null || true)}"
    dsumax="${UNLOCK_DSUMAX:-$(thermal_dsu_max_freq 2>/dev/null || true)}"

    if [ -n "$EXYNOS_GPU_DIR" ] && [ -r "$EXYNOS_GPU_DIR/gpu_freq_table" ]; then
        gmax="$(thermal_pick_step_pct "$EXYNOS_GPU_DIR/gpu_freq_table" "$gpu_pct" 2>/dev/null || true)"
    elif [ -n "$GPU_DEVFREQ_DIR" ] && [ -r "$GPU_DEVFREQ_DIR/available_frequencies" ]; then
        gmax="$(thermal_pick_step_pct "$GPU_DEVFREQ_DIR/available_frequencies" "$gpu_pct" 2>/dev/null || true)"
    fi

    thermal_unlock_sysfs_ceilings

    [ -n "$EXYNOS_UFCC_DIR" ] && [ -e "$EXYNOS_UFCC_DIR/cpufreq_max_limit" ] && sysfs_safe_write "$EXYNOS_UFCC_DIR/cpufreq_max_limit" "-1" || true

    if [ -n "$c1max" ] && [ -n "$CPU_MID_POLICY" ]; then
        sysfs_safe_write "$KGX_SYS_ROOT/devices/system/cpu/cpufreq/$CPU_MID_POLICY/scaling_max_freq" "$c1max" || true
        [ -n "$EXYNOS_MIGOV_DIR" ] && [ -e "$EXYNOS_MIGOV_DIR/cl1/cl1_pm_qos_max_freq" ] && sysfs_safe_write "$EXYNOS_MIGOV_DIR/cl1/cl1_pm_qos_max_freq" "$c1max" || true
    fi
    if [ -n "$c2max" ] && [ -n "$CPU_BIG_POLICY" ]; then
        sysfs_safe_write "$KGX_SYS_ROOT/devices/system/cpu/cpufreq/$CPU_BIG_POLICY/scaling_max_freq" "$c2max" || true
        [ -n "$EXYNOS_MIGOV_DIR" ] && [ -e "$EXYNOS_MIGOV_DIR/cl2/cl2_pm_qos_max_freq" ] && sysfs_safe_write "$EXYNOS_MIGOV_DIR/cl2/cl2_pm_qos_max_freq" "$c2max" || true
    fi
    if [ -n "$gmax" ]; then
        if [ -n "$EXYNOS_GPU_DIR" ]; then
            sysfs_safe_write "$EXYNOS_GPU_DIR/gpu_siop_max_clock" "$gmax" "$EXYNOS_GPU_DIR/gpu_freq_table" || true
            sysfs_safe_write "$EXYNOS_GPU_DIR/gpu_max_clock" "$gmax" "$EXYNOS_GPU_DIR/gpu_freq_table" || true
        fi
        if [ -n "$GPU_DEVFREQ_DIR" ] && [ -e "$GPU_DEVFREQ_DIR/max_freq" ]; then
            sysfs_safe_write "$GPU_DEVFREQ_DIR/max_freq" "$gmax" "$GPU_DEVFREQ_DIR/available_frequencies" || true
        fi
        [ -n "$EXYNOS_MIGOV_DIR" ] && [ -e "$EXYNOS_MIGOV_DIR/gpu/gpu_pm_qos_max_freq" ] && sysfs_safe_write "$EXYNOS_MIGOV_DIR/gpu/gpu_pm_qos_max_freq" "$gmax" || true
    fi

    if [ "${THERMAL_UNLOCK:-0}" = "1" ] || [ "${SUSTAINED_SWEET_SPOT:-0}" = "1" ] || [ -f "$ceil_file" ]; then
        cat > "$ceil_file" <<EOF
UNLOCK_GMAX='${gmax}'
UNLOCK_C0MAX='${c0max}'
UNLOCK_C1MAX='${c1max}'
UNLOCK_C2MAX='${c2max}'
UNLOCK_MIFMAX='${mifmax}'
UNLOCK_DSUMAX='${dsumax}'
EOF
        thermal_lock_sysfs_ceilings
    fi
    kgx_log "INFO" "thermal" "Soft thermal step tier=$tier (scale=${scale}%): c1=$c1max c2=$c2max gmax=$gmax"
    return 0
}

thermal_monitor_step() {
    local pkg="$1"
    local base_mode="$2"
    local base_fps="$3"
    local game_pid="${4:-}"
    local state_file="$KGX_DATA_DIR/state/thermal_stage.state"
    local tier_file="$KGX_DATA_DIR/state/soft_step.tier"
    local prev_stage="" prev_tier=0 temps batt_c cpu_c gpu_c eval_out new_stage therm_fps mode_cap eff_mode eff_fps relief
    local alert_hit=0 force_t2=0 new_tier=0

    [ -f "$state_file" ] && prev_stage="$(cat "$state_file" 2>/dev/null | head -n 1)"
    [ -f "$tier_file" ] && prev_tier="$(cat "$tier_file" 2>/dev/null | head -n 1 | tr -dc '0-9')"
    [ -n "$prev_tier" ] || prev_tier=0

    temps="$(thermal_read_temps)"
    IFS='|' read -r batt_c cpu_c gpu_c <<EOF
$temps
EOF

    if [ "${THERMAL_ALERT_ENABLED:-1}" = "1" ]; then
        if [ "$batt_c" -ge "${THERMAL_ALERT_BATT_C:-44}" ] 2>/dev/null || [ "$cpu_c" -ge "${THERMAL_ALERT_CPU_C:-92}" ] 2>/dev/null; then
            alert_hit=1
            case "${THERMAL_ALERT_ACTION:-notify}" in
                bypass)
                    command -v power_bypass_force_emergency >/dev/null 2>&1 && power_bypass_force_emergency || true
                    ;;
                step_down)
                    force_t2=1
                    ;;
                both)
                    command -v power_bypass_force_emergency >/dev/null 2>&1 && power_bypass_force_emergency || true
                    force_t2=1
                    ;;
            esac
        fi
    fi

    new_tier="$prev_tier"
    if [ "${SOFT_THERMAL_STEP:-0}" = "1" ] || [ "$prev_tier" -gt 0 ] || [ "$force_t2" = "1" ]; then
        new_tier="$(thermal_eval_soft_step "$batt_c" "$cpu_c" "$prev_tier" "$force_t2")"
    fi

    if [ "${THERMAL_UNLOCK:-0}" = "1" ] || [ "${SUSTAINED_SWEET_SPOT:-0}" = "1" ]; then
        if [ -z "$prev_stage" ]; then
            prev_stage="UNLOCKED"
            [ "${SUSTAINED_SWEET_SPOT:-0}" = "1" ] && prev_stage="SWEET_SPOT"
        fi
        eval_out="$(thermal_evaluate_stage "$batt_c" "$cpu_c" "$prev_stage" "$gpu_c")"
        IFS='|' read -r new_stage _s _s <<EOF
$eval_out
EOF
        if [ "$new_stage" != "$prev_stage" ]; then
            printf '%s\n' "$new_stage" > "$state_file"
            relief=0
            if [ "$new_stage" = "UNLOCKED_COOL" ] || [ "$new_stage" = "SWEET_SPOT_COOL" ]; then
                relief=1
            fi
            kgx_log "INFO" "thermal" "Sustained Anti-TMU transition $prev_stage -> $new_stage (batt=${batt_c}C, cpu=${cpu_c}C, gpu=${gpu_c}C, relief=$relief)"
            cpu_gpu_apply "$base_mode" "$game_pid" "$relief"
            if [ "$new_tier" != "$prev_tier" ] || [ "${new_tier:-0}" -gt 0 ]; then
                thermal_apply_soft_step "$new_tier" || true
            fi
        elif [ "$new_tier" != "$prev_tier" ]; then
            thermal_apply_soft_step "$new_tier" || true
        fi
        thermal_defend_unlock_fast >/dev/null 2>&1 || true
        command -v display_defend_hz >/dev/null 2>&1 && display_defend_hz >/dev/null 2>&1 || true
        if [ "$alert_hit" -eq 0 ] || [ "${THERMAL_ALERT_ACTION:-notify}" = "notify" ] || [ "${THERMAL_ALERT_ACTION:-notify}" = "step_down" ]; then
            command -v power_bypass_update >/dev/null 2>&1 && power_bypass_update >/dev/null 2>&1 || true
        fi
        return 0
    fi

    if [ "$alert_hit" -eq 0 ] || [ "${THERMAL_ALERT_ACTION:-notify}" = "notify" ] || [ "${THERMAL_ALERT_ACTION:-notify}" = "step_down" ]; then
        command -v power_bypass_update >/dev/null 2>&1 && power_bypass_update >/dev/null 2>&1 || true
    fi
    if [ "${THERMAL_GUARD_ENABLED:-1}" = "1" ]; then
        [ -n "$prev_stage" ] || prev_stage="NORMAL"
        eval_out="$(thermal_evaluate_stage "$batt_c" "$cpu_c" "$prev_stage" "$gpu_c")"
        IFS='|' read -r new_stage therm_fps mode_cap <<EOF
$eval_out
EOF
        if [ "$new_stage" != "$prev_stage" ]; then
            printf '%s\n' "$new_stage" > "$state_file"
            eff_mode="$(thermal_cap_mode "$base_mode" "$mode_cap")"
            eff_fps="$(fps_get_effective "$pkg" "$base_fps" "$new_stage")"

            kgx_log "WARN" "thermal" "Stage transition $prev_stage -> $new_stage (batt=${batt_c}C, cpu=${cpu_c}C, gpu=${gpu_c}C) => mode=$eff_mode, fps=$eff_fps"
            cpu_gpu_apply "$eff_mode" "$game_pid" 0
            fps_apply "$pkg" "$eff_fps" "$eff_mode"
            [ "${DISPLAY_AUTO_HZ:-1}" = "1" ] && display_apply "$eff_fps"
        fi
    fi
    if [ "$new_tier" != "$prev_tier" ]; then
        thermal_apply_soft_step "$new_tier" || true
    fi
}
