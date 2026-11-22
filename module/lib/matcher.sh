#!/system/bin/sh
# KSU Ultimate Gaming X - Hardware-Aware Device Profile & Game Matcher (Low-Fork POSIX)

# Output: 15-field TSV row for profile_id (custom profiles take precedence over built-in)
matcher_get_device_row() {
    local pid="$1"
    local row=""
    if [ -f "$KGX_DATA_DIR/profiles/custom_profiles.tsv" ]; then
        row="$(awk -F '\t' -v id="$pid" '!/^#/ && NF>=14 && $1==id {print; exit}' "$KGX_DATA_DIR/profiles/custom_profiles.tsv")"
    fi
    if [ -z "$row" ] && [ -f "$KGX_MODDIR/data/devices.tsv" ]; then
        row="$(awk -F '\t' -v id="$pid" '!/^#/ && NF>=14 && $1==id {print; exit}' "$KGX_MODDIR/data/devices.tsv")"
    fi
    [ -n "$row" ] || return 1
    printf '%s\n' "$row"
    return 0
}

matcher_get_builtin_game_row() {
    local pkg="$1"
    [ -f "$KGX_MODDIR/data/games.tsv" ] || return 1
    awk -F '\t' -v p="$pkg" '!/^#/ && NF>=11 && $1==p {print; exit}' "$KGX_MODDIR/data/games.tsv"
}

matcher_get_custom_game_row() {
    local pkg="$1"
    [ -f "$KGX_DATA_DIR/config/custom_games.tsv" ] || return 1
    awk -F '\t' -v p="$pkg" '!/^#/ && NF>=7 && $1==p {print; exit}' "$KGX_DATA_DIR/config/custom_games.tsv"
}

# Resolves merged effective game configuration as tab-separated line
matcher_get_effective_game() {
    local pkg="$1"
    local brow crow _skip
    local g_name g_emax g_ltype g_dtfps g_dmode g_padr g_pmal g_nfp g_gload g_tprof g_notes
    local c_en c_prof c_tfps c_mode c_dhz c_tprof c_net c_dscale c_wres is_known

    brow="$(matcher_get_builtin_game_row "$pkg")"
    crow="$(matcher_get_custom_game_row "$pkg")"

    if [ -n "$brow" ]; then
        is_known=1
        IFS='	' read -r _skip g_name g_emax g_ltype g_dtfps g_dmode g_padr g_pmal g_nfp g_gload g_tprof g_notes <<EOF
$brow
EOF
    else
        is_known=0
        g_name="$pkg"
        g_emax=144
        g_ltype="OPEN"
        g_dtfps=60
        g_dmode="${DEFAULT_MODE:-high_performance}"
        g_padr="rog_phone_9_pro"
        g_pmal="redmi_k80_ultra"
        g_nfp=0
        g_gload="medium"
        g_tprof="standard"
        g_notes="Custom user-added package; FPS depends on game engine and display Hz."
    fi

    c_en=1
    c_prof="auto"
    c_tfps="$g_dtfps"
    c_mode="$g_dmode"
    c_dhz="auto"
    c_tprof="$g_tprof"
    c_net=1
    c_dscale="1.0"
    c_wres="default"

    if [ -n "$crow" ]; then
        IFS='	' read -r _skip c_en c_prof c_tfps c_mode c_dhz c_tprof c_net c_dscale c_wres <<EOF
$crow
EOF
    fi

    [ -n "$c_en" ] || c_en=1
    [ -n "$c_prof" ] || c_prof="auto"
    [ -n "$c_tfps" ] || c_tfps="$g_dtfps"
    [ -n "$c_mode" ] || c_mode="$g_dmode"
    [ -n "$c_dhz" ] || c_dhz="auto"
    [ -n "$c_tprof" ] || c_tprof="$g_tprof"
    [ -n "$c_net" ] || c_net=1
    case "$c_dscale" in
        1.0|0.9|0.85|0.8|0.75) ;;
        *) c_dscale="1.0" ;;
    esac
    case "$c_wres" in
        1080x1920|900x1600|720x1280|1440x2560) ;;
        *) c_wres="default" ;;
    esac

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$pkg" "$g_name" "$c_en" "$c_prof" "$c_tfps" "$c_mode" "$c_dhz" "$c_tprof" "$c_net" \
        "$g_emax" "$g_ltype" "$g_nfp" "$g_gload" "$g_padr" "$g_pmal" "$g_notes" "$is_known" "$c_dscale" "$c_wres"
}

# Zero-fork scoring helper: populates MATCH_SCORE, MATCH_COMPAT, MATCH_REASON
matcher_score_fields() {
    local pid="$1" p_gpu="$2" p_tier="$3" p_hz="$4" pref_adreno="${5:-}" pref_mali="${6:-}"
    local score=0 reason="" tier_diff

    # 1. GPU family alignment (weight: 50; Exynos xclipse permits flagship whitelist profiles cleanly)
    if [ "${GPU_VENDOR:-unknown}" = "unknown" ]; then
        score=$((score + 30))
        reason="GPU unknown (neutral)"
    elif [ "$p_gpu" = "$GPU_VENDOR" ]; then
        score=$((score + 50))
        reason="Exact GPU match ($p_gpu)"
    elif [ "$GPU_VENDOR" = "xclipse" ]; then
        if [ "$p_gpu" = "adreno" ] && [ -n "$pref_adreno" ] && [ "$pid" = "$pref_adreno" ]; then
            score=$((score + 30))
            reason="Exynos Xclipse + game-preferred whitelist profile"
        elif [ "$p_gpu" = "adreno" ] && [ "${p_tier:-2}" -ge 3 ] 2>/dev/null; then
            score=$((score + 20))
            reason="Exynos Xclipse + flagship whitelist profile"
        else
            score=$((score + 10))
            reason="Exynos Xclipse compatible profile"
        fi
    else
        score=$((score - 40))
        reason="GPU_MISMATCH (real=$GPU_VENDOR vs profile=$p_gpu)"
    fi

    # 2. Game preferred profile bonus (weight: 35)
    if [ -n "$pref_adreno" ] || [ -n "$pref_mali" ]; then
        if [ "$GPU_VENDOR" = "adreno" ] && [ "$pid" = "$pref_adreno" ]; then
            score=$((score + 35))
            reason="$reason; Game primary Adreno match"
        elif [ "$GPU_VENDOR" = "xclipse" ] && [ "$pid" = "$pref_adreno" ]; then
            score=$((score + 35))
            reason="$reason; Game primary whitelist match for Exynos"
        elif [ "$GPU_VENDOR" = "mali" ] && [ "$pid" = "$pref_mali" ]; then
            score=$((score + 35))
            reason="$reason; Game primary Mali match"
        elif [ "$pid" = "$pref_adreno" ] || [ "$pid" = "$pref_mali" ]; then
            score=$((score + 10))
            reason="$reason; Game secondary match"
        fi
    fi

    # 3. Hardware tier alignment (weight: 15)
    tier_diff=$((p_tier - ${HW_TIER:-2}))
    [ "$tier_diff" -lt 0 ] && tier_diff=$((-tier_diff))
    if [ "$tier_diff" -eq 0 ]; then
        score=$((score + 15))
        reason="$reason; Tier $p_tier match"
    elif [ "$tier_diff" -eq 1 ]; then
        score=$((score + 8))
        reason="$reason; Tier within 1"
    fi

    # 4. Display Hz alignment (weight: 10)
    if [ "$p_hz" -ge "${DISPLAY_MAX_HZ:-60}" ] 2>/dev/null; then
        score=$((score + 10))
    elif [ "$p_hz" -ge 90 ] 2>/dev/null; then
        score=$((score + 5))
    fi

    [ "$score" -lt 0 ] && score=0
    [ "$score" -gt 100 ] && score=100

    if [ "$p_gpu" != "${GPU_VENDOR:-unknown}" ] && [ "${GPU_VENDOR:-unknown}" != "unknown" ] && [ "${GPU_VENDOR:-unknown}" != "xclipse" ]; then
        MATCH_COMPAT="GPU_MISMATCH"
    elif [ "$score" -ge 70 ]; then
        MATCH_COMPAT="OPTIMAL"
    elif [ "$score" -ge 45 ]; then
        MATCH_COMPAT="COMPATIBLE"
    else
        MATCH_COMPAT="LOW"
    fi

    MATCH_SCORE="$score"
    MATCH_REASON="$reason"
}

matcher_score_profile() {
    local pid="$1"
    local pkg="${2:-}"
    local drow grow pref_adreno="" pref_mali="" _s
    local p_gpu p_tier p_hz

    hw_load
    drow="$(matcher_get_device_row "$pid")" || {
        printf '0|INVALID|Profile not found\n'
        return 1
    }
    IFS='	' read -r _s _s _s _s p_gpu p_tier p_hz _s <<EOF
$drow
EOF

    if [ -n "$pkg" ]; then
        grow="$(matcher_get_builtin_game_row "$pkg")"
        if [ -n "$grow" ]; then
            IFS='	' read -r _s _s _s _s _s _s pref_adreno pref_mali _s <<EOF
$grow
EOF
        fi
    fi

    matcher_score_fields "$pid" "$p_gpu" "$p_tier" "$p_hz" "$pref_adreno" "$pref_mali"
    printf '%s|%s|%s\n' "$MATCH_SCORE" "$MATCH_COMPAT" "$MATCH_REASON"
}

# Picks the highest-scoring safe profile for <pkg> given actual hardware (zero forks inside loop)
matcher_select_auto_profile() {
    local pkg="${1:-}"
    local best_id="" best_score=-1 best_compat="" best_reason=""
    local grow="" pref_adreno="" pref_mali="" _s
    local src pid p_gpu p_tier p_hz

    hw_load

    if [ -n "$pkg" ]; then
        grow="$(matcher_get_builtin_game_row "$pkg")"
        if [ -n "$grow" ]; then
            IFS='	' read -r _s _s _s _s _s _s pref_adreno pref_mali _s <<EOF
$grow
EOF
        fi
    fi

    for src in "$KGX_DATA_DIR/profiles/custom_profiles.tsv" "$KGX_MODDIR/data/devices.tsv"; do
        [ -f "$src" ] || continue
        while IFS='	' read -r pid _s _s _s p_gpu p_tier p_hz _s || [ -n "$pid" ]; do
            case "$pid" in
                ''|\#*) continue ;;
            esac
            matcher_score_fields "$pid" "$p_gpu" "$p_tier" "$p_hz" "$pref_adreno" "$pref_mali"
            if [ "$MATCH_SCORE" -gt "$best_score" ] 2>/dev/null; then
                best_score="$MATCH_SCORE"
                best_id="$pid"
                best_compat="$MATCH_COMPAT"
                best_reason="$MATCH_REASON"
            fi
        done < "$src"
    done

    if [ -z "$best_id" ]; then
        best_id="rog_phone_9_pro"
        best_score=50
        best_compat="FALLBACK"
        best_reason="Default fallback profile"
    fi
    printf '%s|%s|%s|%s\n' "$best_id" "$best_score" "$best_compat" "$best_reason"
}
