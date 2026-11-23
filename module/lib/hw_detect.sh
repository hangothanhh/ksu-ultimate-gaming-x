#!/system/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# KSU Ultimate Gaming X - Hardware & Capability Discovery Engine

hw_detect_display_rates() {
    local rates="" max_hz=0 auth=0
    local sf_rates="" sf_max=0 k_rates="" k_max=0 m
    local disp_tmp="$KGX_DATA_DIR/state/.hw_disp.$$"
    local sf_tmp="$KGX_DATA_DIR/state/.hw_sf.$$"

    mkdir -p "$KGX_DATA_DIR/state" 2>/dev/null || true

    if command -v dumpsys >/dev/null 2>&1; then
        dumpsys display > "$disp_tmp" 2>/dev/null || true
        if [ -s "$disp_tmp" ]; then
            # Pass 1A: Strict primary/internal display only (ignores external HDMI 50/70/75Hz)
            rates="$(awk '
                /DisplayDeviceInfo\{/ && (/type INTERNAL/ || /FLAG_DEFAULT_DISPLAY/) && !/type EXTERNAL/ && !/type VIRTUAL/ {
                    line = $0
                    while (match(line, /fps=[0-9]+(\.[0-9]+)?/)) {
                        val = substr(line, RSTART + 4, RLENGTH - 4) + 0
                        hz = int(val + 0.5)
                        if (hz >= 30 && hz <= 240) seen[hz] = 1
                        line = substr(line, RSTART + RLENGTH)
                    }
                }
                END { for (h in seen) print h }
            ' "$disp_tmp" | sort -n | tr '\n' ' ' | sed 's/ $//')"

            # Pass 1B: Legacy/mock dumpsys display format (no DisplayDeviceInfo header)
            if [ -z "$rates" ] && ! grep -qE 'DisplayDeviceInfo\{.*(type INTERNAL|FLAG_DEFAULT_DISPLAY)' "$disp_tmp" 2>/dev/null; then
                rates="$(awk '
                    (/supportedModes/ || /DisplayModeRecord/ || /fps=/) && !/type EXTERNAL/ && !/type VIRTUAL/ {
                        line = $0
                        while (match(line, /fps=[0-9]+(\.[0-9]+)?/)) {
                            val = substr(line, RSTART + 4, RLENGTH - 4) + 0
                            hz = int(val + 0.5)
                            if (hz >= 30 && hz <= 240) seen[hz] = 1
                            line = substr(line, RSTART + RLENGTH)
                        }
                    }
                    END { for (h in seen) print h }
                ' "$disp_tmp" | sort -n | tr '\n' ' ' | sed 's/ $//')"
            fi
        fi
        rm -f "$disp_tmp" 2>/dev/null || true
    fi

    if [ -n "$rates" ]; then
        auth=1
        max_hz="$(printf '%s\n' "$rates" | awk '{print $NF}')"
        kgx_sanitize_int "$max_hz" || max_hz=0
    fi

    # Fallback 2: dumpsys SurfaceFlinger primary display "Refresh rates:" block
    if { [ -z "$rates" ] || [ "$max_hz" -le 60 ] 2>/dev/null; } && command -v dumpsys >/dev/null 2>&1; then
        dumpsys SurfaceFlinger > "$sf_tmp" 2>/dev/null || true
        if [ -s "$sf_tmp" ]; then
            sf_rates="$(awk '
                BEGIN { in_rr = 0; done_first = 0; has_any = 0 }
                done_first == 0 && /^[ \t]*Refresh rates:/ {
                    in_rr = 1
                    next
                }
                in_rr == 1 {
                    if (match($0, /fps=[0-9]+(\.[0-9]+)?/)) {
                        line = $0
                        while (match(line, /fps=[0-9]+(\.[0-9]+)?/)) {
                            val = substr(line, RSTART + 4, RLENGTH - 4) + 0
                            hz = int(val + 0.5)
                            if (hz >= 30 && hz <= 240) {
                                seen[hz] = 1
                                has_any = 1
                            }
                            line = substr(line, RSTART + RLENGTH)
                        }
                    } else if (has_any == 1 || $0 ~ /^[A-Za-z]/) {
                        in_rr = 0
                        done_first = 1
                    }
                }
                END { for (h in seen) print h }
            ' "$sf_tmp" | sort -n | tr '\n' ' ' | sed 's/ $//')"
            if [ -n "$sf_rates" ]; then
                sf_max="$(printf '%s\n' "$sf_rates" | awk '{print $NF}')"
                kgx_sanitize_int "$sf_max" || sf_max=0
                if [ -z "$rates" ] || [ "$sf_max" -gt "$max_hz" ] 2>/dev/null; then
                    rates="$sf_rates"
                    max_hz="$sf_max"
                    auth=1
                fi
            fi
        fi
        rm -f "$sf_tmp" 2>/dev/null || true
    fi

    # Fallback 3: Kernel DRM DSI/eDP/LVDS modes or Samsung panel vrr sysfs
    if [ -z "$rates" ] || [ "$max_hz" -le 60 ] 2>/dev/null; then
        k_rates="$(
            {
                for m in "$KGX_SYS_ROOT/class/drm"/*DSI*/modes "$KGX_SYS_ROOT/class/drm"/*eDP*/modes "$KGX_SYS_ROOT/class/drm"/*LVDS*/modes; do
                    [ -r "$m" ] || continue
                    awk '
                        {
                            line = $0
                            while (match(line, /@[0-9]+/)) {
                                hz = int(substr(line, RSTART + 1, RLENGTH - 1) + 0)
                                if (hz >= 30 && hz <= 240) print hz
                                line = substr(line, RSTART + RLENGTH)
                            }
                        }' "$m" 2>/dev/null
                done
                if [ -r "$KGX_SYS_ROOT/class/lcd/panel/vrr" ]; then
                    awk '{
                        hz = int($1 + 0)
                        if (hz >= 48 && hz <= 240) print hz
                        exit
                    }' "$KGX_SYS_ROOT/class/lcd/panel/vrr" 2>/dev/null
                fi
            } | sort -nu | tr '\n' ' ' | sed 's/ $//'
        )"
        if [ -n "$k_rates" ]; then
            k_max="$(printf '%s\n' "$k_rates" | awk '{print $NF}')"
            kgx_sanitize_int "$k_max" || k_max=0
            if [ -z "$rates" ] || [ "$k_max" -gt "$max_hz" ] 2>/dev/null; then
                rates="$k_rates"
                max_hz="$k_max"
                auth=1
            fi
        fi
    fi

    if [ -z "$rates" ] || [ "$max_hz" -le 0 ] 2>/dev/null; then
        printf '60|60|0\n'
    else
        printf '%s|%s|%s\n' "$rates" "$max_hz" "$auth"
    fi
}

hw_detect_all() {
    local out="$KGX_DATA_DIR/state/hw_profile.env"
    local tmp="$out.tmp.$$"
    local r_brand r_mfg r_model r_device r_product r_fp r_api r_abi
    local soc_plat soc_hw soc_vendor gpu_vendor gpu_model gpu_devfreq gpu_kgsl
    local policies little_pol mid_pol big_pol cpu_max_khz cpu_cores has_uclamp
    local ram_kb ram_mb has_psi has_zram
    local disp_probe disp_rates disp_max_hz disp_auth=0 prev_rates="" prev_max=0 probe_max=0
    local therm_batt therm_cpu therm_gpu
    local touch_drv touch_game touch_rate touch_ev
    local io_devs rp_bin has_rp has_zygisk has_cmd_game hw_tier
    local bypass_node="" bypass_mode="none" batt_cap_node="" batt_status_node="" backlight_node=""
    local p pol maxf best_max mid_c bn bcand

    mkdir -p "$KGX_DATA_DIR/state" 2>/dev/null || true

    if [ -f "$out" ]; then
        prev_rates="$(awk -F '=' '$1=="DISPLAY_SUPPORTED_HZ"{v=$2; gsub(/\047/, "", v); print v; exit}' "$out" 2>/dev/null)"
        prev_max="$(awk -F '=' '$1=="DISPLAY_MAX_HZ"{v=$2; gsub(/\047/, "", v); print v; exit}' "$out" 2>/dev/null)"
        kgx_sanitize_int "$prev_max" || prev_max=0
    fi

    # 1. Real system properties (use stock snapshot if already captured so spoofing never pollutes HW profile)
    if [ -f "$KGX_DATA_DIR/state/orig_props.tsv" ]; then
        r_brand="$(awk -F '\t' '$1=="ro.product.brand"{print $2; exit}' "$KGX_DATA_DIR/state/orig_props.tsv")"
        r_mfg="$(awk -F '\t' '$1=="ro.product.manufacturer"{print $2; exit}' "$KGX_DATA_DIR/state/orig_props.tsv")"
        r_model="$(awk -F '\t' '$1=="ro.product.model"{print $2; exit}' "$KGX_DATA_DIR/state/orig_props.tsv")"
        r_device="$(awk -F '\t' '$1=="ro.product.device"{print $2; exit}' "$KGX_DATA_DIR/state/orig_props.tsv")"
        r_product="$(awk -F '\t' '$1=="ro.product.name"{print $2; exit}' "$KGX_DATA_DIR/state/orig_props.tsv")"
        r_fp="$(awk -F '\t' '$1=="ro.build.fingerprint"{print $2; exit}' "$KGX_DATA_DIR/state/orig_props.tsv")"
    fi
    [ -n "$r_brand" ] || r_brand="$(getprop ro.product.brand 2>/dev/null)"
    [ -n "$r_mfg" ] || r_mfg="$(getprop ro.product.manufacturer 2>/dev/null)"
    [ -n "$r_model" ] || r_model="$(getprop ro.product.model 2>/dev/null)"
    [ -n "$r_device" ] || r_device="$(getprop ro.product.device 2>/dev/null)"
    [ -n "$r_product" ] || r_product="$(getprop ro.product.name 2>/dev/null)"
    [ -n "$r_fp" ] || r_fp="$(getprop ro.build.fingerprint 2>/dev/null)"
    r_api="$(getprop ro.build.version.sdk 2>/dev/null)"
    r_abi="$(getprop ro.product.cpu.abi 2>/dev/null)"

    # 2. SoC & GPU detection
    soc_plat="$(getprop ro.board.platform 2>/dev/null)"
    soc_hw="$(getprop ro.hardware 2>/dev/null)"
    [ -n "$soc_hw" ] || soc_hw="$(getprop ro.soc.model 2>/dev/null)"
    gpu_model="$(getprop ro.hardware.egl 2>/dev/null)"

    soc_vendor="unknown"
    gpu_vendor="unknown"
    gpu_devfreq=""
    gpu_kgsl=""
    exynos_gpu_dir=""
    exynos_ufcc_dir=""
    exynos_migov_dir=""
    exynos_dsu_dir=""

    if [ -d "$KGX_SYS_ROOT/kernel/gpu" ]; then
        exynos_gpu_dir="$KGX_SYS_ROOT/kernel/gpu"
        if [ -r "$exynos_gpu_dir/gpu_model" ]; then
            gpu_model="$(cat "$exynos_gpu_dir/gpu_model" 2>/dev/null | head -n 1 | tr -d '\r')"
        fi
        case "$(printf '%s' "$gpu_model" | tr '[:upper:]' '[:lower:]')" in
            *xclipse*|*sgpu*) gpu_vendor="xclipse"; soc_vendor="exynos" ;;
            *mali*) gpu_vendor="mali" ;;
        esac
    fi
    [ -d "$KGX_SYS_ROOT/devices/platform/exynos-ufcc/ufc" ] && exynos_ufcc_dir="$KGX_SYS_ROOT/devices/platform/exynos-ufcc/ufc"
    [ -d "$KGX_SYS_ROOT/devices/platform/exynos-migov" ] && exynos_migov_dir="$KGX_SYS_ROOT/devices/platform/exynos-migov"
    [ -d "$KGX_SYS_ROOT/devices/platform/exynos-dsufreq/dsufreq" ] && exynos_dsu_dir="$KGX_SYS_ROOT/devices/platform/exynos-dsufreq/dsufreq"

    if [ -d "$KGX_SYS_ROOT/class/kgsl/kgsl-3d0" ]; then
        gpu_kgsl="$KGX_SYS_ROOT/class/kgsl/kgsl-3d0"
        gpu_vendor="adreno"
        soc_vendor="qualcomm"
        if [ -r "$gpu_kgsl/gpu_model" ]; then
            gpu_model="$(cat "$gpu_kgsl/gpu_model" 2>/dev/null | head -n 1 | tr -d '\r')"
        fi
        if [ -d "$gpu_kgsl/devfreq" ]; then
            gpu_devfreq="$gpu_kgsl/devfreq"
        fi
    fi

    if [ -z "$gpu_devfreq" ] && [ -d "$KGX_SYS_ROOT/class/devfreq" ]; then
        for d in "$KGX_SYS_ROOT/class/devfreq"/*; do
            [ -d "$d" ] || continue
            case "${d##*/}" in
                *kgsl*)
                    gpu_devfreq="$d"
                    gpu_vendor="adreno"
                    soc_vendor="qualcomm"
                    break
                    ;;
                *sgpu*|*xclipse*)
                    gpu_devfreq="$d"
                    gpu_vendor="xclipse"
                    soc_vendor="exynos"
                    break
                    ;;
                *mali*|*gpu*)
                    gpu_devfreq="$d"
                    if [ "$gpu_vendor" = "unknown" ]; then
                        gpu_vendor="mali"
                    fi
                    break
                    ;;
            esac
        done
    fi

    # Heuristic fallback from SoC platform/hardware if sysfs GPU nodes weren't obvious
    if [ "$soc_vendor" = "unknown" ] || [ "$gpu_vendor" = "unknown" ]; then
        case "$(printf '%s %s %s' "$soc_plat" "$soc_hw" "$gpu_model" | tr '[:upper:]' '[:lower:]')" in
            *qcom*|*msm*|*sm8*|*sm7*|*lahaina*|*taro*|*kalama*|*pineapple*|*adreno*)
                [ "$soc_vendor" = "unknown" ] && soc_vendor="qualcomm"
                [ "$gpu_vendor" = "unknown" ] && gpu_vendor="adreno"
                ;;
            *mt6*|*mt8*|*dimensity*|*helio*)
                [ "$soc_vendor" = "unknown" ] && soc_vendor="mediatek"
                [ "$gpu_vendor" = "unknown" ] && gpu_vendor="mali"
                ;;
            *exynos*|*s5e*|*erd*)
                [ "$soc_vendor" = "unknown" ] && soc_vendor="exynos"
                case "$(printf '%s' "$gpu_model" | tr '[:upper:]' '[:lower:]')" in
                    *xclipse*|*samsung*) gpu_vendor="xclipse" ;;
                    *) [ "$gpu_vendor" = "unknown" ] && gpu_vendor="mali" ;;
                esac
                ;;
            *tensor*|*gs1*|*gs2*|*zuma*|*oriole*|*husky*)
                [ "$soc_vendor" = "unknown" ] && soc_vendor="tensor"
                [ "$gpu_vendor" = "unknown" ] && gpu_vendor="mali"
                ;;
        esac
    fi
    [ -n "$gpu_model" ] || gpu_model="$gpu_vendor"

    # 3. CPU policies & uclamp
    policies=""
    little_pol=""
    mid_pol=""
    big_pol=""
    cpu_max_khz=0
    if [ -d "$KGX_SYS_ROOT/devices/system/cpu/cpufreq" ]; then
        for p in "$KGX_SYS_ROOT/devices/system/cpu/cpufreq"/policy*; do
            [ -d "$p" ] || continue
            pol="${p##*/}"
            policies="$policies $pol"
            maxf="$(cat "$p/cpuinfo_max_freq" 2>/dev/null | head -n 1 | tr -dc '0-9')"
            [ -n "$maxf" ] || maxf="$(cat "$p/scaling_max_freq" 2>/dev/null | head -n 1 | tr -dc '0-9')"
            [ -n "$maxf" ] || maxf=0
            if [ "$maxf" -gt "$cpu_max_khz" ] 2>/dev/null; then
                cpu_max_khz="$maxf"
                big_pol="$pol"
            fi
            [ -n "$little_pol" ] || little_pol="$pol"
        done
    fi
    policies="${policies# }"
    # Detect middle cluster if >= 3 policies exist
    mid_c=0
    for pol in $policies; do
        mid_c=$((mid_c + 1))
        if [ "$pol" != "$little_pol" ] && [ "$pol" != "$big_pol" ]; then
            mid_pol="$pol"
        fi
    done

    cpu_cores=0
    if [ -r "$KGX_PROC_ROOT/cpuinfo" ]; then
        cpu_cores="$(grep -c '^processor' "$KGX_PROC_ROOT/cpuinfo" 2>/dev/null || printf '0')"
    fi
    [ "$cpu_cores" -gt 0 ] 2>/dev/null || cpu_cores=8

    has_uclamp=0
    if [ -d "$KGX_DEV_ROOT/cpuctl/top-app" ] && [ -e "$KGX_DEV_ROOT/cpuctl/top-app/cpu.uclamp.min" ]; then
        has_uclamp=1
    elif [ -e "$KGX_SYS_ROOT/fs/cgroup/top-app/cpu.uclamp.min" ]; then
        has_uclamp=1
    fi

    # 4. RAM, PSI, zRAM
    ram_kb=0
    if [ -r "$KGX_PROC_ROOT/meminfo" ]; then
        ram_kb="$(awk '/^MemTotal:/{print $2; exit}' "$KGX_PROC_ROOT/meminfo" 2>/dev/null)"
    fi
    case "$ram_kb" in
        ''|*[!0-9]*) ram_kb=0 ;;
    esac
    ram_mb=$((ram_kb / 1024))
    has_psi=0
    [ -r "$KGX_PROC_ROOT/pressure/memory" ] && has_psi=1
    has_zram=0
    [ -e "$KGX_SYS_ROOT/block/zram0" ] && has_zram=1

    # 5. Display refresh rates (primary display + SurfaceFlinger/DRM fallback + never-downgrade guard)
    disp_probe="$(hw_detect_display_rates)"
    IFS='|' read -r disp_rates disp_max_hz disp_auth <<EOF
$disp_probe
EOF
    kgx_sanitize_int "$disp_max_hz" || disp_max_hz=60
    probe_max="$disp_max_hz"
    if [ "$prev_max" -gt 60 ] 2>/dev/null; then
        if [ "$disp_auth" != "1" ] || [ "$disp_max_hz" -le 60 ] 2>/dev/null; then
            disp_rates="$prev_rates"
            disp_max_hz="$prev_max"
            kgx_log "WARN" "hw" "Display refresh probe returned ${probe_max}Hz (auth=${disp_auth:-0}); preserving existing ${prev_max}Hz profile (${prev_rates})."
        fi
    fi

    # 6. Thermal zones (supports Qualcomm, MediaTek & Exynos BIG/MID/LITTLE/G3D/gpu_tmu)
    therm_batt=""
    therm_cpu=""
    therm_gpu=""
    if [ -r "$KGX_SYS_ROOT/class/power_supply/battery/temp" ]; then
        therm_batt="$KGX_SYS_ROOT/class/power_supply/battery/temp"
    fi
    if [ -d "$KGX_SYS_ROOT/class/thermal" ]; then
        for tz in "$KGX_SYS_ROOT/class/thermal"/thermal_zone*; do
            [ -d "$tz" ] && [ -r "$tz/type" ] && [ -r "$tz/temp" ] || continue
            ttype="$(cat "$tz/type" 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d '\r')"
            case "$ttype" in
                *batt*) [ -n "$therm_batt" ] || therm_batt="$tz/temp" ;;
                g3d|*gpuss*|*sgpu*|*mali*|*gpu*) [ -n "$therm_gpu" ] || therm_gpu="$tz/temp" ;;
                big|cpuss*|cpu-0*|cpu_0*) therm_cpu="$tz/temp" ;;
                mid|little|cpucl*|*cluster*|*exynos*cpu*|*soc*|*ap*|*tsens_tz0*)
                    [ -n "$therm_cpu" ] || therm_cpu="$tz/temp"
                    ;;
            esac
        done
    fi
    if [ -z "$therm_gpu" ] && [ -n "$exynos_gpu_dir" ] && [ -r "$exynos_gpu_dir/gpu_tmu" ]; then
        therm_gpu="$exynos_gpu_dir/gpu_tmu"
    fi

    # 7. Touch nodes
    touch_drv="unknown"
    touch_game=""
    touch_rate=""
    touch_ev=""
    if [ -r "$KGX_PROC_ROOT/bus/input/devices" ]; then
        touch_drv="$(awk '
            /^N: Name=/ { name=$0; sub(/^N: Name="/,"",name); sub(/"$/,"",name) }
            /^H: Handlers=.*event/ {
                if (tolower(name) ~ /touch|fts|goodix|synaptics|novatek|himax|sec_touchscreen|focaltech|ilitek/) {
                    print name; exit
                }
            }' "$KGX_PROC_ROOT/bus/input/devices" 2>/dev/null)"
        touch_ev="$(awk '
            /^N: Name=/ { name=$0 }
            /^H: Handlers=/ {
                if (tolower(name) ~ /touch|fts|goodix|synaptics|novatek|himax|sec_touchscreen|focaltech|ilitek/) {
                    if (match($0, /event[0-9]+/)) { print substr($0, RSTART, RLENGTH); exit }
                }
            }' "$KGX_PROC_ROOT/bus/input/devices" 2>/dev/null)"
    fi
    [ -n "$touch_drv" ] || touch_drv="generic"
    for tn in \
        "$KGX_PROC_ROOT/touchpanel/game_switch_enable" \
        "$KGX_SYS_ROOT/class/touch/touch_dev/bump_sample_rate"; do
        if [ -e "$tn" ]; then
            touch_game="$tn"
            break
        fi
    done
    if [ -z "$touch_game" ]; then
        for tn in "$KGX_SYS_ROOT/devices/platform"/*goodix*/game_mode "$KGX_SYS_ROOT/class/sec/tsp/cmd"; do
            if [ -e "$tn" ]; then
                touch_game="$tn"
                break
            fi
        done
    fi
    for trn in "$KGX_PROC_ROOT/touchpanel/report_rate" "$KGX_SYS_ROOT/class/touch/touch_dev/report_rate"; do
        if [ -e "$trn" ]; then
            touch_rate="$trn"
            break
        fi
    done

    # 8. Real backing block devices
    io_devs=""
    for b in "$KGX_SYS_ROOT/block"/sd* "$KGX_SYS_ROOT/block"/mmcblk0 "$KGX_SYS_ROOT/block"/nvme*; do
        [ -d "$b/queue" ] || continue
        case "${b##*/}" in
            loop*|ram*|dm-*|zram*) continue ;;
        esac
        io_devs="$io_devs ${b##*/}"
    done
    io_devs="${io_devs# }"

    # 8B. Battery Bypass Charging & Backlight sysfs nodes
    if [ -r "$KGX_SYS_ROOT/class/power_supply/battery/capacity" ]; then
        batt_cap_node="$KGX_SYS_ROOT/class/power_supply/battery/capacity"
    fi
    if [ -r "$KGX_SYS_ROOT/class/power_supply/battery/status" ]; then
        batt_status_node="$KGX_SYS_ROOT/class/power_supply/battery/status"
    fi
    for bn in batt_slate_mode input_suspend charging_enabled store_mode; do
        bcand="$KGX_SYS_ROOT/class/power_supply/battery/$bn"
        if [ -e "$bcand" ]; then
            bypass_node="$bcand"
            case "$bn" in
                input_suspend) bypass_mode="invert1" ;;
                charging_enabled) bypass_mode="zero_off" ;;
                *) bypass_mode="slate" ;;
            esac
            break
        fi
    done

    for bcand in "$KGX_SYS_ROOT/class/backlight"/*/brightness "$KGX_SYS_ROOT/class/leds"/*backlight*/brightness; do
        if [ -r "$bcand" ]; then
            backlight_node="$bcand"
            break
        fi
    done

    # 9. Environment tools
    rp_bin="$(kgx_find_resetprop 2>/dev/null || true)"
    has_rp=0
    [ -n "$rp_bin" ] && has_rp=1
    has_zygisk=0
    if kgx_is_zygisk_active; then
        has_zygisk=1
    fi
    has_cmd_game=0
    if command -v cmd >/dev/null 2>&1 && [ "${r_api:-0}" -ge 31 ] 2>/dev/null; then
        has_cmd_game=1
    fi

    # 10. Hardware Tier (1=Entry/Mid, 2=Upper-Mid, 3=Flagship)
    hw_tier=1
    if [ "$ram_mb" -ge 10240 ] && [ "$cpu_max_khz" -ge 2800000 ]; then
        hw_tier=3
    elif [ "$ram_mb" -ge 7168 ] && [ "$cpu_max_khz" -ge 2300000 ]; then
        hw_tier=2
    elif [ "$disp_max_hz" -ge 120 ] && [ "$ram_mb" -ge 7168 ]; then
        hw_tier=2
    fi

    cat > "$tmp" <<EOF
REAL_BRAND='$r_brand'
REAL_MANUFACTURER='$r_mfg'
REAL_MODEL='$r_model'
REAL_DEVICE='$r_device'
REAL_PRODUCT='$r_product'
REAL_FINGERPRINT='$r_fp'
REAL_ANDROID_API='${r_api:-0}'
REAL_ABI='${r_abi:-arm64-v8a}'
SOC_PLATFORM='$soc_plat'
SOC_HARDWARE='$soc_hw'
SOC_VENDOR='$soc_vendor'
GPU_VENDOR='$gpu_vendor'
GPU_MODEL='$gpu_model'
GPU_DEVFREQ_DIR='$gpu_devfreq'
GPU_KGSL_DIR='$gpu_kgsl'
EXYNOS_GPU_DIR='$exynos_gpu_dir'
EXYNOS_UFCC_DIR='$exynos_ufcc_dir'
EXYNOS_MIGOV_DIR='$exynos_migov_dir'
EXYNOS_DSU_DIR='$exynos_dsu_dir'
CPU_POLICIES='$policies'
CPU_LITTLE_POLICY='$little_pol'
CPU_MID_POLICY='$mid_pol'
CPU_BIG_POLICY='$big_pol'
CPU_MAX_KHZ='$cpu_max_khz'
CPU_CORES='$cpu_cores'
HAS_UCLAMP='$has_uclamp'
RAM_TOTAL_MB='$ram_mb'
HAS_PSI='$has_psi'
HAS_ZRAM='$has_zram'
DISPLAY_SUPPORTED_HZ='$disp_rates'
DISPLAY_MAX_HZ='$disp_max_hz'
THERMAL_BATT_NODE='$therm_batt'
THERMAL_CPU_NODE='$therm_cpu'
THERMAL_GPU_NODE='$therm_gpu'
TOUCH_DRIVER='$touch_drv'
TOUCH_GAME_NODE='$touch_game'
TOUCH_RATE_NODE='$touch_rate'
TOUCH_EVENT_DEV='$touch_ev'
IO_BLOCK_DEVS='$io_devs'
HAS_RESETPROP='$has_rp'
RESETPROP_BIN='$rp_bin'
HAS_ZYGISK='$has_zygisk'
HAS_CMD_GAME='$has_cmd_game'
HW_TIER='$hw_tier'
BYPASS_NODE='$bypass_node'
BYPASS_MODE='$bypass_mode'
BATT_CAPACITY_NODE='$batt_cap_node'
BATT_STATUS_NODE='$batt_status_node'
BACKLIGHT_NODE='$backlight_node'
EOF
    mv "$tmp" "$out"
    . "$out"
    return 0
}

hw_load() {
    local hw_file="$KGX_DATA_DIR/state/hw_profile.env"
    local heal_res="" new_rates="" new_max=0 new_auth=0 tmp_hw=""

    if [ ! -f "$hw_file" ]; then
        hw_detect_all
        return $?
    fi
    . "$hw_file"

    if [ "${DISPLAY_MAX_HZ:-60}" -le 60 ] 2>/dev/null && [ "${KGX_HW_HEAL_TRIED:-0}" != "1" ]; then
        if [ "$KGX_SYS_ROOT" != "/sys" ] || [ "$(getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; then
            KGX_HW_HEAL_TRIED=1
            heal_res="$(hw_detect_display_rates)"
            IFS='|' read -r new_rates new_max new_auth <<EOF
$heal_res
EOF
            kgx_sanitize_int "$new_max" || new_max=0
            if [ "$new_auth" = "1" ] && [ "$new_max" -gt 60 ] 2>/dev/null; then
                tmp_hw="${hw_file}.tmp.$$"
                awk -v r="$new_rates" -v m="$new_max" '
                    /^DISPLAY_SUPPORTED_HZ=/ { printf "DISPLAY_SUPPORTED_HZ=\047%s\047\n", r; sr = 1; next }
                    /^DISPLAY_MAX_HZ=/ { printf "DISPLAY_MAX_HZ=\047%s\047\n", m; sm = 1; next }
                    { print }
                    END {
                        if (!sr) printf "DISPLAY_SUPPORTED_HZ=\047%s\047\n", r
                        if (!sm) printf "DISPLAY_MAX_HZ=\047%s\047\n", m
                    }
                ' "$hw_file" > "$tmp_hw" 2>/dev/null && mv "$tmp_hw" "$hw_file" || rm -f "$tmp_hw" 2>/dev/null
                DISPLAY_SUPPORTED_HZ="$new_rates"
                DISPLAY_MAX_HZ="$new_max"
                kgx_log "INFO" "hw" "Self-healed hw_profile.env display rates to ${new_rates} (max=${new_max}Hz)."
            fi
        fi
    fi
}

hw_to_json() {
    hw_load
    printf '{'
    printf '"real_brand":"%s",' "$(json_escape "$REAL_BRAND")"
    printf '"real_manufacturer":"%s",' "$(json_escape "$REAL_MANUFACTURER")"
    printf '"real_model":"%s",' "$(json_escape "$REAL_MODEL")"
    printf '"real_device":"%s",' "$(json_escape "$REAL_DEVICE")"
    printf '"real_product":"%s",' "$(json_escape "$REAL_PRODUCT")"
    printf '"real_fingerprint":"%s",' "$(json_escape "$REAL_FINGERPRINT")"
    printf '"android_api":%s,' "${REAL_ANDROID_API:-0}"
    printf '"abi":"%s",' "$(json_escape "$REAL_ABI")"
    printf '"soc_platform":"%s",' "$(json_escape "$SOC_PLATFORM")"
    printf '"soc_hardware":"%s",' "$(json_escape "$SOC_HARDWARE")"
    printf '"soc_vendor":"%s",' "$(json_escape "$SOC_VENDOR")"
    printf '"gpu_vendor":"%s",' "$(json_escape "$GPU_VENDOR")"
    printf '"gpu_model":"%s",' "$(json_escape "$GPU_MODEL")"
    printf '"gpu_devfreq_dir":"%s",' "$(json_escape "$GPU_DEVFREQ_DIR")"
    printf '"exynos_gpu_dir":"%s",' "$(json_escape "$EXYNOS_GPU_DIR")"
    printf '"cpu_policies":"%s",' "$(json_escape "$CPU_POLICIES")"
    printf '"cpu_max_khz":%s,' "${CPU_MAX_KHZ:-0}"
    printf '"cpu_cores":%s,' "${CPU_CORES:-0}"
    printf '"has_uclamp":%s,' "${HAS_UCLAMP:-0}"
    printf '"ram_total_mb":%s,' "${RAM_TOTAL_MB:-0}"
    printf '"has_psi":%s,' "${HAS_PSI:-0}"
    printf '"has_zram":%s,' "${HAS_ZRAM:-0}"
    printf '"display_supported_hz":"%s",' "$(json_escape "$DISPLAY_SUPPORTED_HZ")"
    printf '"display_max_hz":%s,' "${DISPLAY_MAX_HZ:-60}"
    printf '"touch_driver":"%s",' "$(json_escape "$TOUCH_DRIVER")"
    printf '"touch_game_node":"%s",' "$(json_escape "$TOUCH_GAME_NODE")"
    printf '"touch_rate_node":"%s",' "$(json_escape "$TOUCH_RATE_NODE")"
    printf '"io_block_devs":"%s",' "$(json_escape "$IO_BLOCK_DEVS")"
    printf '"has_resetprop":%s,' "${HAS_RESETPROP:-0}"
    printf '"has_zygisk":%s,' "${HAS_ZYGISK:-0}"
    printf '"has_cmd_game":%s,' "${HAS_CMD_GAME:-0}"
    printf '"bypass_node":"%s",' "$(json_escape "$BYPASS_NODE")"
    printf '"bypass_mode":"%s",' "$(json_escape "${BYPASS_MODE:-none}")"
    printf '"backlight_node":"%s",' "$(json_escape "$BACKLIGHT_NODE")"
    printf '"hw_tier":%s' "${HW_TIER:-1}"
    printf '}\n'
}
