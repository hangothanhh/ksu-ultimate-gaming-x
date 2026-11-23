#!/system/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# KSU Ultimate Gaming X - Sustained Anti-Lag CPU, GPU (Adreno/Mali/Exynos Xclipse), Bus & I/O Optimizer

# Picks the nearest real frequency in <avail_file> at <pct>% of the available steps
cpu_pick_freq_pct() {
    local avail_file="$1"
    local pct="$2"
    [ -r "$avail_file" ] || return 1
    tr ' ' '\n' < "$avail_file" 2>/dev/null | grep -E '^[0-9]+$' | sort -n -u | awk -v p="$pct" '
    { a[n++] = $1 }
    END {
        if (n == 0) exit 1
        idx = int(((n - 1) * p) / 100 + 0.5)
        if (idx < 0) idx = 0
        if (idx >= n) idx = n - 1
        print a[idx]
    }'
}

cpu_pick_gov() {
    local avail_file="$1"
    local prefs="$2"
    local g tok
    [ -r "$avail_file" ] || return 1
    for g in $prefs; do
        for tok in $(cat "$avail_file" 2>/dev/null); do
            if [ "$tok" = "$g" ]; then
                printf '%s\n' "$g"
                return 0
            fi
        done
    done
    return 1
}

cpu_gpu_find_top_app_cgroup() {
    if [ -d "$KGX_DEV_ROOT/cpuctl/top-app" ]; then
        printf '%s\n' "$KGX_DEV_ROOT/cpuctl/top-app"
    elif [ -d "$KGX_SYS_ROOT/fs/cgroup/top-app" ]; then
        printf '%s\n' "$KGX_SYS_ROOT/fs/cgroup/top-app"
    fi
}

cpu_gpu_apply_uclamp() {
    local umin="$1" umax="$2" lsens="$3" game_pid="${4:-}"
    local cdir=""
    cdir="$(cpu_gpu_find_top_app_cgroup)"
    [ -n "$cdir" ] || return 0

    [ -w "$cdir/cpu.uclamp.min" ] && sysfs_safe_write "$cdir/cpu.uclamp.min" "$umin" || true
    [ -w "$cdir/cpu.uclamp.max" ] && sysfs_safe_write "$cdir/cpu.uclamp.max" "$umax" || true
    [ -w "$cdir/cpu.uclamp.latency_sensitive" ] && sysfs_safe_write "$cdir/cpu.uclamp.latency_sensitive" "$lsens" || true

    if [ -n "$game_pid" ] && kgx_sanitize_int "$game_pid" && [ "$game_pid" -gt 1 ]; then
        if [ -w "$cdir/cgroup.procs" ]; then
            echo "$game_pid" > "$cdir/cgroup.procs" 2>/dev/null || true
        elif [ -w "$cdir/tasks" ]; then
            echo "$game_pid" > "$cdir/tasks" 2>/dev/null || true
        fi
    fi
}

cpu_gpu_pin_render_threads() {
    local game_pid="${1:-}"
    local nice_val="${2:--4}"
    local task_dir cdir tid tcomm tname rnice pinned=0

    [ -n "$game_pid" ] && kgx_sanitize_int "$game_pid" && [ "$game_pid" -gt 1 ] || return 0
    task_dir="$KGX_PROC_ROOT/$game_pid/task"
    [ -d "$task_dir" ] || return 0

    rnice="$nice_val"
    [ "${nice_val:-0}" -le -4 ] 2>/dev/null && rnice="-6"

    if [ "$KGX_PROC_ROOT" = "/proc" ] && [ -x "$KGX_MODDIR/bin/kgx-core" ]; then
        pinned="$("$KGX_MODDIR/bin/kgx-core" pin-threads "$game_pid" "$rnice" 2>/dev/null | tr -dc '0-9')"
        [ -n "$pinned" ] || pinned=0
        if [ "$pinned" -gt 0 ] 2>/dev/null; then
            kgx_log "INFO" "cpu_gpu" "Prioritized & pinned $pinned game render thread(s) for pid=$game_pid (nice=$rnice)."
        fi
        return 0
    fi

    cdir="$(cpu_gpu_find_top_app_cgroup)"

    for tid_path in "$task_dir"/[0-9]*; do
        [ -d "$tid_path" ] && [ -r "$tid_path/comm" ] || continue
        tid="${tid_path##*/}"
        kgx_sanitize_int "$tid" || continue
        tcomm="$(cat "$tid_path/comm" 2>/dev/null | head -n 1 | tr -d '\r\n')"
        tname="$(printf '%s' "$tcomm" | tr '[:upper:]' '[:lower:]')"
        case "$tname" in
            *renderthread*|*unitymain*|*unitygfx*|*gamethread*|*rhithread*|*renderworker*|*asyncrender*|*glthread*|*vulkan*)
                if [ -n "$cdir" ]; then
                    if [ -w "$cdir/cgroup.threads" ]; then
                        echo "$tid" > "$cdir/cgroup.threads" 2>/dev/null || true
                    elif [ -w "$cdir/tasks" ]; then
                        echo "$tid" > "$cdir/tasks" 2>/dev/null || true
                    fi
                fi
                if command -v renice >/dev/null 2>&1 && [ "$rnice" -ne 0 ] 2>/dev/null; then
                    renice -n "$rnice" -p "$tid" >/dev/null 2>&1 || renice "$rnice" "$tid" >/dev/null 2>&1 || true
                fi
                pinned=$((pinned + 1))
                ;;
        esac
    done

    if [ "$pinned" -gt 0 ]; then
        kgx_log "INFO" "cpu_gpu" "Prioritized & pinned $pinned game render thread(s) for pid=$game_pid (nice=$rnice)."
    fi
    return 0
}

cpu_gpu_apply() {
    local mode="${1:-high_performance}"
    local game_pid="${2:-}"
    local thermal_relief="${3:-0}"
    local min_pct_little min_pct_big max_pct_mid max_pct_big
    local uclamp_min uclamp_max lsens up_rate down_rate
    local gpu_min_pct gpu_max_pct bus_min_pct bus_max_pct io_prefs read_ahead nice_val
    local cpu_gov_prefs gpu_gov_prefs ex_gpu_gov_prefs
    local p pol gov fmin fmax avail_f avail_g d b chosen_io dsu_max

    kgx_is_valid_mode "$mode" || mode="high_performance"
    hw_load
    command -v thermal_unlock_sysfs_ceilings >/dev/null 2>&1 && thermal_unlock_sysfs_ceilings || true

    case "$mode" in
        balanced)
            min_pct_little=0; min_pct_big=0; max_pct_mid=100; max_pct_big=100
            uclamp_min=10; uclamp_max=100; lsens=1
            up_rate=1000; down_rate=5000
            gpu_min_pct=0; gpu_max_pct=100; bus_min_pct=0; bus_max_pct=100
            io_prefs="mq-deadline kyber bfq none"; read_ahead=128; nice_val=-2
            ;;
        high_performance)
            min_pct_little=25; min_pct_big=30; max_pct_mid=100; max_pct_big=100
            uclamp_min=25; uclamp_max=100; lsens=1
            up_rate=500; down_rate=4000
            gpu_min_pct=30; gpu_max_pct=100; bus_min_pct=30; bus_max_pct=100
            io_prefs="mq-deadline kyber none bfq"; read_ahead=256; nice_val=-4
            ;;
        extreme_gaming)
            min_pct_little=35; min_pct_big=45; max_pct_mid=100; max_pct_big=100
            uclamp_min=45; uclamp_max=100; lsens=1
            up_rate=500; down_rate=4000
            gpu_min_pct=45; gpu_max_pct=100; bus_min_pct=45; bus_max_pct=100
            io_prefs="mq-deadline kyber none bfq"; read_ahead=256; nice_val=-5
            ;;
        battery_gaming)
            min_pct_little=0; min_pct_big=0; max_pct_mid=80; max_pct_big=75
            uclamp_min=0; uclamp_max=80; lsens=0
            up_rate=2000; down_rate=2000
            gpu_min_pct=0; gpu_max_pct=80; bus_min_pct=0; bus_max_pct=80
            io_prefs="bfq mq-deadline kyber none"; read_ahead=128; nice_val=0
            ;;
    esac

    # Responsive schedutil/interactive prefs prevent Exynos 4nm 100%-floor thermal stall (never force static)
    cpu_gov_prefs="schedutil walt interactive conservative ondemand"
    gpu_gov_prefs="msm-adreno-tz simple_ondemand mali_ondemand coarse_demand sgpu_governor userspace"
    ex_gpu_gov_prefs="interactive amigo conservative dynamic"

    # MAX_CLOCK_LOCK=1: Unlock 100% MAX ceilings + responsive high floors (NO permanent 100% stove)
    if [ "${MAX_CLOCK_LOCK:-0}" = "1" ]; then
        min_pct_little=55; min_pct_big=65; max_pct_mid=100; max_pct_big=100
        gpu_min_pct=65; gpu_max_pct=100
        bus_min_pct=60; bus_max_pct=100
        uclamp_min=65; uclamp_max=100; lsens=1
        up_rate=500; down_rate=4000
        cpu_gov_prefs="schedutil walt interactive performance"
        gpu_gov_prefs="msm-adreno-tz simple_ondemand sgpu_governor performance userspace"
        ex_gpu_gov_prefs="interactive amigo conservative dynamic"
    fi

    # Exynos / 4nm Sustained Sweet-Spot: optimal efficiency/thermal knee (~82% peak) sustains 120 FPS cooler
    if [ "${SUSTAINED_SWEET_SPOT:-0}" = "1" ]; then
        min_pct_little=15; min_pct_big=25
        max_pct_mid=88; max_pct_big=82
        gpu_min_pct=25; gpu_max_pct=82
        bus_min_pct=25; bus_max_pct=90
        uclamp_min=35; uclamp_max=90; lsens=1
        up_rate=500; down_rate=3000
    fi

    # Anti-TMU Sustained Thermal Relief: keep active ceilings unlocked, relax idle floors when hot
    if [ "$thermal_relief" = "1" ]; then
        min_pct_little=15; min_pct_big=20
        gpu_min_pct=25
        bus_min_pct=25
        if [ "${SUSTAINED_SWEET_SPOT:-0}" = "1" ]; then
            max_pct_mid=88; max_pct_big=82; gpu_max_pct=82; bus_max_pct=90
            uclamp_min=30; uclamp_max=90; lsens=1
        else
            max_pct_mid=100; max_pct_big=100; gpu_max_pct=100; bus_max_pct=100
            uclamp_min=30; uclamp_max=100; lsens=1
        fi
        up_rate=500; down_rate=2500
    fi

    # 0. Exynos UFCC & DSU software ceiling lift (never pin cpufreq_min_limit to 100% stove)
    if [ -n "$EXYNOS_UFCC_DIR" ]; then
        if [ "${MAX_CLOCK_LOCK:-0}" = "1" ] || [ "${THERMAL_UNLOCK:-0}" = "1" ] || [ "${SUSTAINED_SWEET_SPOT:-0}" = "1" ] || [ "$mode" = "high_performance" ] || [ "$mode" = "extreme_gaming" ]; then
            [ -w "$EXYNOS_UFCC_DIR/cpufreq_max_limit" ] && sysfs_safe_write "$EXYNOS_UFCC_DIR/cpufreq_max_limit" "-1" || true
            [ -w "$EXYNOS_UFCC_DIR/cpufreq_min_limit" ] && sysfs_safe_write "$EXYNOS_UFCC_DIR/cpufreq_min_limit" "-1" || true
        fi
    fi
    if [ -n "$EXYNOS_DSU_DIR" ] && [ -r "$EXYNOS_DSU_DIR/available_frequencies" ] && [ -w "$EXYNOS_DSU_DIR/scaling_max_freq" ]; then
        dsu_max="$(cpu_pick_freq_pct "$EXYNOS_DSU_DIR/available_frequencies" 100 2>/dev/null || true)"
        [ -n "$dsu_max" ] && sysfs_safe_write "$EXYNOS_DSU_DIR/scaling_max_freq" "$dsu_max" "$EXYNOS_DSU_DIR/available_frequencies" || true
    fi

    # 1. CPU Policies
    for pol in $CPU_POLICIES; do
        p="$KGX_SYS_ROOT/devices/system/cpu/cpufreq/$pol"
        [ -d "$p" ] || continue
        avail_f="$p/scaling_available_frequencies"
        avail_g="$p/scaling_available_governors"

        if [ -r "$avail_g" ]; then
            gov="$(cpu_pick_gov "$avail_g" "$cpu_gov_prefs" 2>/dev/null || true)"
            [ -n "$gov" ] && sysfs_safe_write "$p/scaling_governor" "$gov" "$avail_g" || true
            if [ -n "$gov" ] && [ -d "$p/$gov" ]; then
                [ -w "$p/$gov/up_rate_limit_us" ] && sysfs_safe_write "$p/$gov/up_rate_limit_us" "$up_rate" || true
                [ -w "$p/$gov/down_rate_limit_us" ] && sysfs_safe_write "$p/$gov/down_rate_limit_us" "$down_rate" || true
            fi
        fi

        if [ -r "$avail_f" ]; then
            if [ "$pol" = "$CPU_LITTLE_POLICY" ]; then
                fmin="$(cpu_pick_freq_pct "$avail_f" "$min_pct_little" 2>/dev/null || true)"
                fmax="$(cpu_pick_freq_pct "$avail_f" 100 2>/dev/null || true)"
            elif [ -n "$CPU_MID_POLICY" ] && [ "$pol" = "$CPU_MID_POLICY" ]; then
                fmin="$(cpu_pick_freq_pct "$avail_f" "$min_pct_big" 2>/dev/null || true)"
                fmax="$(cpu_pick_freq_pct "$avail_f" "$max_pct_mid" 2>/dev/null || true)"
            else
                fmin="$(cpu_pick_freq_pct "$avail_f" "$min_pct_big" 2>/dev/null || true)"
                fmax="$(cpu_pick_freq_pct "$avail_f" "$max_pct_big" 2>/dev/null || true)"
            fi
            [ -n "$fmax" ] && sysfs_safe_write "$p/scaling_max_freq" "$fmax" "$avail_f" || true
            [ -n "$fmin" ] && sysfs_safe_write "$p/scaling_min_freq" "$fmin" "$avail_f" || true
        fi
    done

    # 2. Top-App Uclamp, process & render-thread cgroup pinning
    cpu_gpu_apply_uclamp "$uclamp_min" "$uclamp_max" "$lsens" "$game_pid"
    cpu_gpu_pin_render_threads "$game_pid" "$nice_val"

    # 3A. Exynos /sys/kernel/gpu (Xclipse / Mali on Samsung)
    if [ -n "$EXYNOS_GPU_DIR" ] && [ -d "$EXYNOS_GPU_DIR" ]; then
        avail_f="$EXYNOS_GPU_DIR/gpu_freq_table"
        avail_g="$EXYNOS_GPU_DIR/gpu_available_governor"
        if [ -r "$avail_f" ]; then
            fmin="$(cpu_pick_freq_pct "$avail_f" "$gpu_min_pct" 2>/dev/null || true)"
            fmax="$(cpu_pick_freq_pct "$avail_f" "$gpu_max_pct" 2>/dev/null || true)"
            if [ -n "$fmax" ]; then
                if [ -n "$EXYNOS_MIGOV_DIR" ] && [ -w "$EXYNOS_MIGOV_DIR/gpu/gpu_pm_qos_max_freq" ]; then
                    sysfs_safe_write "$EXYNOS_MIGOV_DIR/gpu/gpu_pm_qos_max_freq" "$fmax" || true
                fi
                [ -w "$EXYNOS_GPU_DIR/gpu_siop_max_clock" ] && sysfs_safe_write "$EXYNOS_GPU_DIR/gpu_siop_max_clock" "$fmax" "$avail_f" || true
                [ -w "$EXYNOS_GPU_DIR/gpu_max_clock" ] && sysfs_safe_write "$EXYNOS_GPU_DIR/gpu_max_clock" "$fmax" "$avail_f" || true
            fi
        fi
        if [ -r "$avail_g" ]; then
            gov="$(cpu_pick_gov "$avail_g" "$ex_gpu_gov_prefs" 2>/dev/null || true)"
            [ -n "$gov" ] && sysfs_safe_write "$EXYNOS_GPU_DIR/gpu_governor" "$gov" "$avail_g" || true
        fi
        # Never toggle gpu_ifpo_control live: on Exynos 2200 (s5e9925/sgpu), disabling IFPO during
        # active rendering triggers an ALIVE_D APM NOCL0_DP write timeout & SError 0xbe000011 panic.
        [ -w "$EXYNOS_GPU_DIR/gpu_cl_boost_disable" ] && sysfs_safe_write "$EXYNOS_GPU_DIR/gpu_cl_boost_disable" "0" || true
        if [ -r "$avail_f" ] && [ -n "$fmin" ] && [ -w "$EXYNOS_GPU_DIR/gpu_min_clock" ]; then
            if ! sysfs_safe_write "$EXYNOS_GPU_DIR/gpu_min_clock" "$fmin" "$avail_f" 2>/dev/null; then
                local cand_f
                for cand_f in $(tr ' ' '\n' < "$avail_f" 2>/dev/null | grep -E '^[0-9]+$' | sort -rn -u); do
                    [ "$cand_f" -lt "$fmin" ] 2>/dev/null || continue
                    if sysfs_safe_write "$EXYNOS_GPU_DIR/gpu_min_clock" "$cand_f" "$avail_f" 2>/dev/null; then
                        break
                    fi
                done
            fi
        fi
    fi

    # 3B. GPU Devfreq (Adreno KGSL / Mali / SGPU devfreq)
    if [ -n "$GPU_DEVFREQ_DIR" ] && [ -d "$GPU_DEVFREQ_DIR" ]; then
        avail_f="$GPU_DEVFREQ_DIR/available_frequencies"
        avail_g="$GPU_DEVFREQ_DIR/available_governors"
        if [ -r "$avail_g" ]; then
            gov="$(cpu_pick_gov "$avail_g" "$gpu_gov_prefs" 2>/dev/null || true)"
            [ -n "$gov" ] && sysfs_safe_write "$GPU_DEVFREQ_DIR/governor" "$gov" "$avail_g" || true
        fi
        if [ -r "$avail_f" ]; then
            fmin="$(cpu_pick_freq_pct "$avail_f" "$gpu_min_pct" 2>/dev/null || true)"
            fmax="$(cpu_pick_freq_pct "$avail_f" "$gpu_max_pct" 2>/dev/null || true)"
            [ -n "$fmax" ] && sysfs_safe_write "$GPU_DEVFREQ_DIR/max_freq" "$fmax" "$avail_f" || true
            [ -n "$fmin" ] && sysfs_safe_write "$GPU_DEVFREQ_DIR/min_freq" "$fmin" "$avail_f" || true
        fi
    fi

    # 4. Memory / Bus / MIF / INT Devfreq
    if [ -d "$KGX_SYS_ROOT/class/devfreq" ]; then
        for d in "$KGX_SYS_ROOT/class/devfreq"/*; do
            [ -d "$d" ] || continue
            case "${d##*/}" in
                *ddr*|*llcc*|*l3*|*memlat*|*bus*|*bwmon*|*devfreq_mif*|*devfreq_int*)
                    avail_f="$d/available_frequencies"
                    if [ -r "$avail_f" ]; then
                        fmax="$(cpu_pick_freq_pct "$avail_f" "$bus_max_pct" 2>/dev/null || true)"
                        fmin="$(cpu_pick_freq_pct "$avail_f" "$bus_min_pct" 2>/dev/null || true)"
                        [ -n "$fmax" ] && [ -w "$d/max_freq" ] && sysfs_safe_write "$d/max_freq" "$fmax" "$avail_f" || true
                        [ -n "$fmin" ] && [ -w "$d/min_freq" ] && sysfs_safe_write "$d/min_freq" "$fmin" "$avail_f" || true
                    fi
                    ;;
            esac
        done
    fi

    # 5. Block I/O Scheduler & Read-Ahead
    for b in $IO_BLOCK_DEVS; do
        p="$KGX_SYS_ROOT/block/$b/queue"
        [ -d "$p" ] || continue
        if [ -r "$p/scheduler" ] && [ -w "$p/scheduler" ]; then
            chosen_io=""
            for tok in $io_prefs; do
                if tr -d '[]' < "$p/scheduler" 2>/dev/null | grep -qw "$tok"; then
                    chosen_io="$tok"
                    break
                fi
            done
            [ -n "$chosen_io" ] && sysfs_safe_write "$p/scheduler" "$chosen_io" "$p/scheduler" || true
        fi
        [ -w "$p/read_ahead_kb" ] && sysfs_safe_write "$p/read_ahead_kb" "$read_ahead" || true
    done

    # 6. Game workload nice prioritization
    if [ -n "$game_pid" ] && kgx_sanitize_int "$game_pid" && [ "$game_pid" -gt 1 ] && [ "$nice_val" -ne 0 ]; then
        if command -v renice >/dev/null 2>&1; then
            renice -n "$nice_val" -p "$game_pid" >/dev/null 2>&1 || renice "$nice_val" "$game_pid" >/dev/null 2>&1 || true
        fi
    fi

    if [ "${THERMAL_UNLOCK:-0}" = "1" ] || [ "${SUSTAINED_SWEET_SPOT:-0}" = "1" ]; then
        command -v thermal_lock_sysfs_ceilings >/dev/null 2>&1 && thermal_lock_sysfs_ceilings || true
    fi

    kgx_log "INFO" "cpu_gpu" "Applied mode=$mode max_lock=${MAX_CLOCK_LOCK:-0} sweet=${SUSTAINED_SWEET_SPOT:-0} relief=${thermal_relief} (uclamp=${uclamp_min}-${uclamp_max}, mid_max=${max_pct_mid}%, big=${min_pct_big}-${max_pct_big}%, gpu=${gpu_min_pct}-${gpu_max_pct}%)"
    return 0
}

cpu_gpu_restore() {
    local cur_gov="" dyn_gov=""
    command -v thermal_unlock_sysfs_ceilings >/dev/null 2>&1 && thermal_unlock_sysfs_ceilings || true
    sysfs_restore_all
    hw_load
    if [ -n "$EXYNOS_GPU_DIR" ] && [ -r "$EXYNOS_GPU_DIR/gpu_governor" ] && [ -w "$EXYNOS_GPU_DIR/gpu_governor" ]; then
        cur_gov="$(cat "$EXYNOS_GPU_DIR/gpu_governor" 2>/dev/null | head -n 1 | tr -d '\r\n ')"
        if [ "$cur_gov" = "static" ] && [ -r "$EXYNOS_GPU_DIR/gpu_available_governor" ]; then
            dyn_gov="$(cpu_pick_gov "$EXYNOS_GPU_DIR/gpu_available_governor" "interactive amigo conservative dynamic" 2>/dev/null || true)"
            if [ -n "$dyn_gov" ]; then
                echo "$dyn_gov" > "$EXYNOS_GPU_DIR/gpu_governor" 2>/dev/null || true
                kgx_log "INFO" "cpu_gpu" "Recovered Exynos GPU governor from stuck 'static' -> '$dyn_gov'."
            fi
        fi
    fi
    kgx_log "INFO" "cpu_gpu" "Restored all backed-up CPU/GPU/bus/IO sysfs nodes."
    return 0
}

cpu_gpu_freq_to_mhz() {
    local v="${1:-0}"
    [ -n "$v" ] || { printf '0\n'; return 0; }
    if [ "$v" -ge 10000000 ] 2>/dev/null; then
        printf '%s\n' $((v / 1000000))
    elif [ "$v" -ge 10000 ] 2>/dev/null; then
        printf '%s\n' $((v / 1000))
    else
        printf '%s\n' "$v"
    fi
}

cpu_gpu_read_cpu_pct() {
    local stat_file="$KGX_PROC_ROOT/stat"
    local prev_file="$KGX_DATA_DIR/state/cpu_stat.prev"
    local prev_tot=0 prev_idle=0 cur_line cur_tot=0 cur_idle=0 dt di pct=0

    [ -r "$stat_file" ] || { printf '0\n'; return 0; }
    cur_line="$(awk '/^cpu /{
        tot=0; for(i=2;i<=NF;i++) tot+=$i;
        idle=$5+$6;
        printf "%s %s\n", tot, idle; exit
    }' "$stat_file" 2>/dev/null)"
    cur_tot="${cur_line%% *}"
    cur_idle="${cur_line##* }"
    [ -n "$cur_tot" ] && [ -n "$cur_idle" ] || { printf '0\n'; return 0; }

    if [ -r "$prev_file" ]; then
        read -r prev_tot prev_idle < "$prev_file" 2>/dev/null || true
    fi
    mkdir -p "$KGX_DATA_DIR/state" 2>/dev/null || true
    printf '%s %s\n' "$cur_tot" "$cur_idle" > "$prev_file" 2>/dev/null || true

    if [ "${prev_tot:-0}" -gt 0 ] 2>/dev/null && [ "$cur_tot" -gt "$prev_tot" ] 2>/dev/null; then
        dt=$((cur_tot - prev_tot))
        di=$((cur_idle - prev_idle))
        [ "$di" -lt 0 ] && di=0
        pct=$(((dt - di) * 100 / dt))
        [ "$pct" -lt 0 ] && pct=0
        [ "$pct" -gt 100 ] && pct=100
    fi
    printf '%s\n' "$pct"
}

cpu_gpu_read_telemetry() {
    local pol p cur gov minf maxf clusters=""
    local gpu_cur=0 gpu_max=0 gpu_gov="unknown" gpu_mhz=0 gpu_max_mhz=0 gpu_pct=0 cpu_pct=0

    hw_load
    cpu_pct="$(cpu_gpu_read_cpu_pct)"
    for pol in $CPU_POLICIES; do
        p="$KGX_SYS_ROOT/devices/system/cpu/cpufreq/$pol"
        [ -d "$p" ] || continue
        cur="$(cat "$p/scaling_cur_freq" 2>/dev/null | tr -dc '0-9')"
        minf="$(cat "$p/scaling_min_freq" 2>/dev/null | tr -dc '0-9')"
        maxf="$(cat "$p/scaling_max_freq" 2>/dev/null | tr -dc '0-9')"
        gov="$(cat "$p/scaling_governor" 2>/dev/null | tr -d '\r\n')"
        [ -n "$clusters" ] && clusters="${clusters},"
        clusters="${clusters}{\"policy\":\"$pol\",\"gov\":\"$(json_escape "${gov:-unknown}")\",\"cur_mhz\":$(( ${cur:-0} / 1000 )),\"min_mhz\":$(( ${minf:-0} / 1000 )),\"max_mhz\":$(( ${maxf:-0} / 1000 ))}"
    done

    if [ -n "$EXYNOS_GPU_DIR" ] && [ -r "$EXYNOS_GPU_DIR/gpu_clock" ]; then
        gpu_cur="$(cat "$EXYNOS_GPU_DIR/gpu_clock" 2>/dev/null | tr -dc '0-9')"
        gpu_max="$(cat "$EXYNOS_GPU_DIR/gpu_max_clock" 2>/dev/null | tr -dc '0-9')"
        gpu_gov="$(cat "$EXYNOS_GPU_DIR/gpu_governor" 2>/dev/null | tr -d '\r\n')"
        if [ "${gpu_cur:-0}" = "0" ] && [ -n "$GPU_DEVFREQ_DIR" ] && [ -r "$GPU_DEVFREQ_DIR/cur_freq" ]; then
            gpu_cur="$(cat "$GPU_DEVFREQ_DIR/cur_freq" 2>/dev/null | tr -dc '0-9')"
        fi
        [ -r "$EXYNOS_GPU_DIR/gpu_busy" ] && gpu_pct="$(cat "$EXYNOS_GPU_DIR/gpu_busy" 2>/dev/null | tr -dc '0-9')"
    elif [ -n "$GPU_DEVFREQ_DIR" ] && [ -d "$GPU_DEVFREQ_DIR" ]; then
        gpu_cur="$(cat "$GPU_DEVFREQ_DIR/cur_freq" 2>/dev/null | tr -dc '0-9')"
        gpu_max="$(cat "$GPU_DEVFREQ_DIR/max_freq" 2>/dev/null | tr -dc '0-9')"
        gpu_gov="$(cat "$GPU_DEVFREQ_DIR/governor" 2>/dev/null | tr -d '\r\n')"
        if [ -n "$GPU_KGSL_DIR" ] && [ -r "$GPU_KGSL_DIR/gpu_busy_percentage" ]; then
            gpu_pct="$(cat "$GPU_KGSL_DIR/gpu_busy_percentage" 2>/dev/null | tr -dc '0-9')"
        elif [ -r "$GPU_DEVFREQ_DIR/load" ]; then
            gpu_pct="$(awk '{for(i=1;i<=NF;i++) if($i~/^[0-9]+/){sub(/[^0-9].*/,"",$i); print $i; exit}}' "$GPU_DEVFREQ_DIR/load" 2>/dev/null)"
        fi
    fi
    gpu_mhz="$(cpu_gpu_freq_to_mhz "${gpu_cur:-0}")"
    gpu_max_mhz="$(cpu_gpu_freq_to_mhz "${gpu_max:-0}")"
    case "$gpu_pct" in ''|*[!0-9]*) gpu_pct=0 ;; esac
    if [ "$gpu_pct" -eq 0 ] && [ "${gpu_max_mhz:-0}" -gt 0 ] && [ "${gpu_mhz:-0}" -gt 0 ]; then
        gpu_pct=$(((gpu_mhz * 100) / gpu_max_mhz))
    fi
    [ "$gpu_pct" -gt 100 ] 2>/dev/null && gpu_pct=100

    printf '{"clusters":[%s],"cpu_pct":%s,"gpu_pct":%s,"gpu_cur_mhz":%s,"gpu_max_mhz":%s,"gpu_gov":"%s"}\n' \
        "$clusters" "$cpu_pct" "$gpu_pct" "$gpu_mhz" "$gpu_max_mhz" "$(json_escape "${gpu_gov:-unknown}")"
}
