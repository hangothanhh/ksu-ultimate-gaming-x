#!/system/bin/sh
# KSU Ultimate Gaming X - Whole-System Persistent Spoof Engine + Play Integrity Shield

SPOOF_SAFE_PROPS="
ro.product.brand
ro.product.manufacturer
ro.product.model
ro.product.device
ro.product.name
ro.build.product
ro.product.marketname
ro.vendor.oplus.market.name
ro.product.system.brand
ro.product.system.manufacturer
ro.product.system.model
ro.product.system.device
ro.product.system.name
ro.product.system.marketname
ro.product.product.brand
ro.product.product.manufacturer
ro.product.product.model
ro.product.product.device
ro.product.product.name
ro.product.product.marketname
"

SPOOF_LEGACY_INTEGRITY_PROPS="
ro.product.vendor.brand
ro.product.vendor.manufacturer
ro.product.vendor.model
ro.product.vendor.device
ro.product.vendor.name
ro.product.vendor.marketname
ro.product.odm.brand
ro.product.odm.manufacturer
ro.product.odm.model
ro.product.odm.device
ro.product.odm.name
ro.product.odm.marketname
ro.build.fingerprint
ro.system.build.fingerprint
ro.vendor.build.fingerprint
ro.odm.build.fingerprint
ro.product.build.fingerprint
"

spoof_resolve_prop_value() {
    local prop="$1" p_brand="$2" p_mfg="$3" p_model="$4" p_device="$5" p_product="$6" p_label="$7"
    case "$prop" in
        *.brand) printf '%s' "$p_brand" ;;
        *.manufacturer) printf '%s' "$p_mfg" ;;
        *.model) printf '%s' "$p_model" ;;
        *.device) printf '%s' "$p_device" ;;
        *.name|ro.build.product)
            case "$prop" in
                ro.vendor.oplus.market.name) printf '%s' "$p_label" ;;
                *) printf '%s' "$p_product" ;;
            esac
            ;;
        *.marketname) printf '%s' "$p_label" ;;
        *) printf '' ;;
    esac
}

spoof_capture_original() {
    local orig_file="$KGX_DATA_DIR/state/orig_props.tsv"
    local tmp="$orig_file.tmp.$$"
    local prop val cur_model orig_model

    mkdir -p "$KGX_DATA_DIR/state" 2>/dev/null || true

    if [ ! -f "$orig_file" ] || [ ! -s "$orig_file" ]; then
        : > "$tmp"
        for prop in $SPOOF_SAFE_PROPS $SPOOF_LEGACY_INTEGRITY_PROPS; do
            kgx_is_prop_allowed "$prop" || continue
            val="$(getprop "$prop" 2>/dev/null | tr -d '\r')"
            printf '%s\t%s\n' "$prop" "$val" >> "$tmp"
        done
        mv "$tmp" "$orig_file"
        kgx_log "INFO" "spoof" "Captured original stock device properties snapshot."
        return 0
    fi

    # Do not pollute orig_props.tsv if system props are already actively spoofed
    if [ -f "$KGX_DATA_DIR/state/active_spoof.env" ]; then
        return 0
    fi
    orig_model="$(awk -F '\t' '$1=="ro.product.model"{print $2; exit}' "$orig_file" 2>/dev/null | tr -d '\r')"
    cur_model="$(getprop ro.product.model 2>/dev/null | tr -d '\r')"
    if [ -n "$orig_model" ] && [ -n "$cur_model" ] && [ "$orig_model" != "$cur_model" ]; then
        return 0
    fi

    for prop in $SPOOF_SAFE_PROPS $SPOOF_LEGACY_INTEGRITY_PROPS; do
        kgx_is_prop_allowed "$prop" || continue
        if ! awk -F '\t' -v k="$prop" '$1==k{f=1} END{exit !f}' "$orig_file" 2>/dev/null; then
            val="$(getprop "$prop" 2>/dev/null | tr -d '\r')"
            printf '%s\t%s\n' "$prop" "$val" >> "$orig_file"
        fi
    done
    return 0
}

spoof_clear_system_prop() {
    if [ -f "$KGX_MODDIR/system.prop" ]; then
        rm -f "$KGX_MODDIR/system.prop" 2>/dev/null || true
        kgx_log "INFO" "spoof" "Removed persistent module system.prop."
    fi
}

spoof_cleanup_legacy_integrity_props() {
    local rp_bin="${1:-}"
    local orig_file="$KGX_DATA_DIR/state/orig_props.tsv"
    local prop orig_val cur_val reverted=0

    [ -n "$rp_bin" ] && [ -f "$orig_file" ] || return 0
    for prop in $SPOOF_LEGACY_INTEGRITY_PROPS; do
        orig_val="$(awk -F '\t' -v k="$prop" '$1==k{print $2; exit}' "$orig_file" 2>/dev/null | tr -d '\r')"
        cur_val="$(getprop "$prop" 2>/dev/null | tr -d '\r')"
        if [ -n "$orig_val" ]; then
            if [ "$cur_val" != "$orig_val" ]; then
                "$rp_bin" -n "$prop" "$orig_val" >/dev/null 2>&1 || true
                reverted=$((reverted + 1))
            fi
        else
            if [ -n "$cur_val" ]; then
                "$rp_bin" --delete "$prop" >/dev/null 2>&1 || true
                reverted=$((reverted + 1))
            fi
        fi
    done
    if [ "$reverted" -gt 0 ]; then
        kgx_log "INFO" "spoof" "Reverted $reverted legacy vendor/odm/fingerprint props to stock for Play Integrity safety."
    fi
    return 0
}

spoof_write_system_prop() {
    local profile_id="$1"
    local drow _s p_label p_brand p_mfg p_model p_device p_product
    local sp_file="$KGX_MODDIR/system.prop"
    local tmp="$sp_file.tmp.$$"
    local prop val

    drow="$(matcher_get_device_row "$profile_id")" || {
        kgx_log "ERROR" "spoof" "Cannot write system.prop: unknown profile '$profile_id'"
        return 1
    }
    IFS='	' read -r _s p_label _s _s _s _s _s _s p_brand p_mfg p_model p_device p_product _s <<EOF
$drow
EOF

    {
        printf '# KSU Ultimate Gaming X v3.0 - Whole-System Safe Spoof (%s)\n' "$p_label"
        printf '# Play Integrity Safe: never writes fingerprint, vendor, or odm identity props globally.\n'
        for prop in $SPOOF_SAFE_PROPS; do
            kgx_is_spoof_write_allowed "$prop" || continue
            val="$(spoof_resolve_prop_value "$prop" "$p_brand" "$p_mfg" "$p_model" "$p_device" "$p_product" "$p_label")"
            if [ -n "$val" ] && kgx_sanitize_prop_val "$val"; then
                printf '%s=%s\n' "$prop" "$val"
            fi
        done
    } > "$tmp" && mv "$tmp" "$sp_file"
    chmod 0644 "$sp_file" 2>/dev/null || true
    kgx_log "INFO" "spoof" "Wrote safe whole-system system.prop for '$p_label' ($p_model)."
    return 0
}

spoof_set_prop_safe() {
    local rp_bin="$1"
    local prop="$2"
    local val="$3"

    if ! kgx_is_spoof_write_allowed "$prop"; then
        kgx_log "ERROR" "spoof" "SECURITY BLOCK: Attempted spoof of protected/non-safe property '$prop'"
        return 1
    fi
    if ! kgx_sanitize_prop_val "$val"; then
        kgx_log "WARN" "spoof" "Rejected invalid spoof value for '$prop'"
        return 1
    fi

    if [ "$(getprop "$prop" 2>/dev/null | tr -d '\r')" = "$val" ]; then
        return 0
    fi
    "$rp_bin" -n "$prop" "$val" >/dev/null 2>&1
}

spoof_apply_props_resetprop() {
    local rp_bin="$1" p_brand="$2" p_mfg="$3" p_model="$4" p_device="$5" p_product="$6" p_label="$7"
    local prop val

    [ -n "$rp_bin" ] || return 0
    for prop in $SPOOF_SAFE_PROPS; do
        val="$(spoof_resolve_prop_value "$prop" "$p_brand" "$p_mfg" "$p_model" "$p_device" "$p_product" "$p_label")"
        [ -n "$val" ] && spoof_set_prop_safe "$rp_bin" "$prop" "$val"
    done
}

spoof_write_active_state() {
    local profile_id="$1" p_label="$2" p_brand="$3" p_mfg="$4" p_model="$5" p_device="$6" p_product="$7"
    cat > "$KGX_DATA_DIR/state/active_spoof.env" <<EOF
SPOOF_ACTIVE=1
SPOOF_SCOPE='global_persistent'
SPOOF_PKG='*'
SPOOF_PROFILE_ID='$profile_id'
SPOOF_LABEL='$p_label'
SPOOF_BRAND='$p_brand'
SPOOF_MANUFACTURER='$p_mfg'
SPOOF_MODEL='$p_model'
SPOOF_DEVICE='$p_device'
SPOOF_PRODUCT='$p_product'
EOF
}

spoof_apply_global_persistent() {
    local profile_id="${1:-}"
    local rp_bin drow _s p_label p_brand p_mfg p_model p_device p_product

    kgx_load_config
    [ -n "$profile_id" ] || profile_id="${GLOBAL_SPOOF_PROFILE:-realme_14_5g}"

    if [ "${SAFE_MODE:-0}" = "1" ] || [ "${SPOOF_ENABLED:-1}" != "1" ]; then
        spoof_clear_system_prop
        return 0
    fi

    spoof_capture_original
    rm -f "$KGX_DATA_DIR/state/zygisk_rules.conf" 2>/dev/null || true

    drow="$(matcher_get_device_row "$profile_id")" || {
        kgx_log "ERROR" "spoof" "Unknown global spoof profile '$profile_id'"
        return 1
    }
    IFS='	' read -r _s p_label _s _s _s _s _s _s p_brand p_mfg p_model p_device p_product _s <<EOF
$drow
EOF

    rp_bin="$(kgx_find_resetprop 2>/dev/null || true)"
    if [ -n "$rp_bin" ]; then
        spoof_cleanup_legacy_integrity_props "$rp_bin"
        spoof_apply_props_resetprop "$rp_bin" "$p_brand" "$p_mfg" "$p_model" "$p_device" "$p_product" "$p_label"
    fi

    spoof_write_system_prop "$profile_id"
    spoof_write_active_state "$profile_id" "$p_label" "$p_brand" "$p_mfg" "$p_model" "$p_device" "$p_product"
    kgx_log "INFO" "spoof" "Applied whole-system persistent spoof '$p_label' ($p_model) with Play Integrity Shield=${PLAY_INTEGRITY_SHIELD:-1}"
    return 0
}

spoof_apply() {
    local _pkg="${1:-}"
    local target_prof SPOOF_PROFILE_ID=""
    kgx_load_config
    if [ "${SAFE_MODE:-0}" = "1" ] || [ "${SPOOF_ENABLED:-1}" != "1" ]; then
        return 0
    fi
    target_prof="${GLOBAL_SPOOF_PROFILE:-realme_14_5g}"
    if [ -f "$KGX_DATA_DIR/state/active_spoof.env" ] && [ -f "$KGX_MODDIR/system.prop" ]; then
        . "$KGX_DATA_DIR/state/active_spoof.env"
        if [ "${SPOOF_PROFILE_ID:-}" = "$target_prof" ]; then
            return 0
        fi
    fi
    spoof_apply_global_persistent "$target_prof"
}

spoof_restore() {
    local preserve_global="${1:-0}"
    local orig_file="$KGX_DATA_DIR/state/orig_props.tsv"
    local active_file="$KGX_DATA_DIR/state/active_spoof.env"
    local rp_bin prop orig_val cur_val restored=0

    kgx_load_config
    if [ "$preserve_global" = "1" ] && [ "${SAFE_MODE:-0}" != "1" ] && [ "${SPOOF_ENABLED:-1}" = "1" ]; then
        kgx_log "INFO" "spoof" "Preserved active whole-system spoof on session exit."
        return 0
    fi

    spoof_clear_system_prop

    rp_bin="$(kgx_find_resetprop 2>/dev/null || true)"
    if [ -n "$rp_bin" ] && [ -f "$orig_file" ]; then
        while IFS='	' read -r prop orig_val || [ -n "$prop" ]; do
            [ -n "$prop" ] || continue
            kgx_is_prop_allowed "$prop" || continue
            cur_val="$(getprop "$prop" 2>/dev/null | tr -d '\r')"
            if [ -n "$orig_val" ]; then
                if [ "$cur_val" != "$orig_val" ]; then
                    "$rp_bin" -n "$prop" "$orig_val" >/dev/null 2>&1 || true
                    restored=$((restored + 1))
                fi
            else
                if [ -n "$cur_val" ]; then
                    "$rp_bin" --delete "$prop" >/dev/null 2>&1 || true
                    restored=$((restored + 1))
                fi
            fi
        done < "$orig_file"
    fi

    rm -f "$active_file" "$KGX_DATA_DIR/state/zygisk_rules.conf" 2>/dev/null || true
    kgx_log "INFO" "spoof" "Restored stock device properties ($restored properties reverted)."
    return 0
}

spoof_create_custom_profile() {
    local id="$1" label="$2" soc="$3" gpu="$4" tier="$5" max_hz="$6" ram_gb="$7"
    local brand="$8" mfg="$9" model="${10}" device="${11}" product="${12}" fp="${13}" notes="${14:-Custom user profile}"
    local prof_file="$KGX_DATA_DIR/profiles/custom_profiles.tsv"
    local tmp="$prof_file.tmp.$$"

    kgx_sanitize_id "$id" || return 1
    kgx_sanitize_prop_val "$label" || return 1
    kgx_sanitize_int "$tier" || return 1
    kgx_sanitize_int "$max_hz" || return 1
    kgx_sanitize_int "$ram_gb" || return 1
    kgx_sanitize_prop_val "$brand" || return 1
    kgx_sanitize_prop_val "$mfg" || return 1
    kgx_sanitize_prop_val "$model" || return 1
    kgx_sanitize_prop_val "$device" || return 1
    kgx_sanitize_prop_val "$product" || return 1
    if [ -n "$fp" ]; then
        kgx_sanitize_prop_val "$fp" || return 1
    fi

    mkdir -p "$KGX_DATA_DIR/profiles" 2>/dev/null || true
    [ -f "$prof_file" ] || printf '# id\tlabel\tcategory\tsoc_family\tgpu_family\ttier\tmax_hz\tram_gb\tbrand\tmanufacturer\tmodel\tdevice\tproduct\tfingerprint\tnotes\n' > "$prof_file"

    local out_fp="$fp"
    [ -n "$out_fp" ] || out_fp="-"
    awk -F '\t' -v pid="$id" '$1!=pid' "$prof_file" > "$tmp"
    printf '%s\t%s\tcustom\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$id" "$label" "$soc" "$gpu" "$tier" "$max_hz" "$ram_gb" \
        "$brand" "$mfg" "$model" "$device" "$product" "$out_fp" "$notes" >> "$tmp"
    mv "$tmp" "$prof_file"
    kgx_log "INFO" "spoof" "Saved custom device profile '$id' ($model)."
    return 0
}

spoof_delete_custom_profile() {
    local id="$1"
    local prof_file="$KGX_DATA_DIR/profiles/custom_profiles.tsv"
    local tmp="$prof_file.tmp.$$"
    kgx_sanitize_id "$id" || return 1
    [ -f "$prof_file" ] || return 0
    awk -F '\t' -v pid="$id" '$1!=pid' "$prof_file" > "$tmp" && mv "$tmp" "$prof_file"
    kgx_log "INFO" "spoof" "Deleted custom device profile '$id'."
}

spoof_is_critical_no_stop() {
    case "$1" in
        android|com.android.systemui|com.kgx.ultimate|*launcher*|*inputmethod*|\
        me.weishu.kernelsu*|com.rifsxd.ksunext*|me.bmax.apatch*|com.topjohnwu.magisk*)
            return 0
            ;;
        *) return 1 ;;
    esac
}

spoof_denylist_count() {
    local dlist="$KGX_DATA_DIR/config/spoof_denylist.list"
    [ -f "$dlist" ] || { printf '0\n'; return 0; }
    awk '!/^[ \t]*#/ && NF>0{c++} END{print c+0}' "$dlist" 2>/dev/null
}

spoof_denylist_status_json() {
    local dlist="$KGX_DATA_DIR/config/spoof_denylist.list"
    local ex_set="false" cnt=0 pkgs_json="" line first=1
    kgx_load_config
    [ "${SPOOF_EXCLUDE_SETTINGS:-1}" = "1" ] && ex_set="true"

    if [ -f "$dlist" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            line="$(printf '%s' "$line" | tr -d '\r' | awk '{$1=$1;print}')"
            case "$line" in ''|\#*) continue ;; esac
            kgx_sanitize_pkg "$line" || continue
            [ "$first" -eq 0 ] && pkgs_json="${pkgs_json},"
            first=0
            pkgs_json="${pkgs_json}\"$(json_escape "$line")\""
            cnt=$((cnt + 1))
        done < "$dlist"
    fi

    printf '{"ok":true,"exclude_settings":%s,"builtin_settings":["com.android.settings","com.android.settings.intelligence","com.samsung.android.app.settings.bixby"],"count":%s,"packages":[%s]}\n' \
        "$ex_set" "$cnt" "$pkgs_json"
}

spoof_denylist_stop_changed() {
    local old_file="$1" new_file="$2" pkg
    command -v am >/dev/null 2>&1 || return 0
    if [ -f "$old_file" ]; then
        while IFS= read -r pkg || [ -n "$pkg" ]; do
            case "$pkg" in ''|\#*) continue ;; esac
            if ! grep -qx "$pkg" "$new_file" 2>/dev/null; then
                spoof_is_critical_no_stop "$pkg" || am force-stop "$pkg" >/dev/null 2>&1 || true
            fi
        done < "$old_file"
    fi
    if [ -f "$new_file" ]; then
        while IFS= read -r pkg || [ -n "$pkg" ]; do
            case "$pkg" in ''|\#*) continue ;; esac
            if [ ! -f "$old_file" ] || ! grep -qx "$pkg" "$old_file" 2>/dev/null; then
                spoof_is_critical_no_stop "$pkg" || am force-stop "$pkg" >/dev/null 2>&1 || true
            fi
        done < "$new_file"
    fi
    return 0
}

spoof_denylist_set_b64() {
    local b64="${1:-}"
    local dlist="$KGX_DATA_DIR/config/spoof_denylist.list"
    local tmp="$dlist.tmp.$$"
    local dec_file="$dlist.dec.$$"
    local decoded=""

    mkdir -p "$KGX_DATA_DIR/config" 2>/dev/null || true
    if [ -n "$b64" ]; then
        decoded="$(printf '%s' "$b64" | tr -d '\r\n' | base64 -d 2>/dev/null)" || return 1
    fi

    printf '# One package per line\n' > "$tmp"
    printf '%s\n' "$decoded" > "$dec_file"
    awk '
        {
            gsub(/\r/, "")
            gsub(/^[ \t]+|[ \t]+$/, "")
            if ($0 == "" || substr($0, 1, 1) == "#") next
            if ($0 ~ /^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$/ && !seen[$0]++) {
                print $0
            }
        }' "$dec_file" >> "$tmp" 2>/dev/null
    rm -f "$dec_file" 2>/dev/null || true

    spoof_denylist_stop_changed "$dlist" "$tmp"
    mv "$tmp" "$dlist"
    chmod 0644 "$dlist" 2>/dev/null || true
    kgx_log "INFO" "spoof" "Updated Spoof Denylist ($(spoof_denylist_count) app(s))."
    return 0
}

spoof_denylist_add() {
    local pkg="$1"
    local dlist="$KGX_DATA_DIR/config/spoof_denylist.list"
    local tmp="$dlist.tmp.$$"
    kgx_sanitize_pkg "$pkg" || return 1
    mkdir -p "$KGX_DATA_DIR/config" 2>/dev/null || true
    [ -f "$dlist" ] || printf '# One package per line\n' > "$dlist"
    awk -v p="$pkg" '!/^[ \t]*$/ { gsub(/\r/,""); if ($0 == p) seen=1; print } END { if (!seen) print p }' "$dlist" > "$tmp"
    mv "$tmp" "$dlist"
    chmod 0644 "$dlist" 2>/dev/null || true
    if ! spoof_is_critical_no_stop "$pkg" && command -v am >/dev/null 2>&1; then
        am force-stop "$pkg" >/dev/null 2>&1 || true
    fi
    kgx_log "INFO" "spoof" "Added '$pkg' to Spoof Denylist."
    return 0
}

spoof_denylist_remove() {
    local pkg="$1"
    local dlist="$KGX_DATA_DIR/config/spoof_denylist.list"
    local tmp="$dlist.tmp.$$"
    kgx_sanitize_pkg "$pkg" || return 1
    [ -f "$dlist" ] || return 0
    awk -v p="$pkg" '{ gsub(/\r/,""); if ($0 != p) print }' "$dlist" > "$tmp"
    mv "$tmp" "$dlist"
    chmod 0644 "$dlist" 2>/dev/null || true
    if ! spoof_is_critical_no_stop "$pkg" && command -v am >/dev/null 2>&1; then
        am force-stop "$pkg" >/dev/null 2>&1 || true
    fi
    kgx_log "INFO" "spoof" "Removed '$pkg' from Spoof Denylist."
    return 0
}

spoof_list_installed_apps_json() {
    {
        printf '===USER===\n'
        if command -v pm >/dev/null 2>&1; then
            pm list packages -3 2>/dev/null | sed 's/^package://; s/[ \t].*//' | tr -d '\r' | sort -u
        fi
        printf '===SYS===\n'
        if command -v pm >/dev/null 2>&1; then
            pm list packages -s 2>/dev/null | sed 's/^package://; s/[ \t].*//' | tr -d '\r' | sort -u
        fi
    } | awk '
    function jesc(s) {
        gsub(/\\/, "\\\\", s)
        gsub(/"/, "\\\"", s)
        return s
    }
    BEGIN { sec = ""; u_out = ""; s_out = ""; nu = 0; ns = 0 }
    {
        gsub(/\r/, "")
        if ($0 == "===USER===") { sec = "USER"; next }
        if ($0 == "===SYS===")  { sec = "SYS";  next }
        if ($0 == "" || $0 == "com.kgx.ultimate") next
        if ($0 !~ /^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$/) next
        if (sec == "USER") {
            if (!seen_u[$0]++) {
                u_out = u_out (nu ? "," : "") "\"" jesc($0) "\""
                nu++
            }
        } else if (sec == "SYS") {
            if (!seen_u[$0] && !seen_s[$0]++) {
                s_out = s_out (ns ? "," : "") "\"" jesc($0) "\""
                ns++
            }
        }
    }
    END {
        printf "{\"ok\":true,\"user_packages\":[%s],\"system_packages\":[%s]}\n", u_out, s_out
    }'
}

spoof_refresh_gms() {
    local stopped=0 pkg
    if command -v am >/dev/null 2>&1; then
        for pkg in com.android.vending com.google.android.gms; do
            am force-stop "$pkg" >/dev/null 2>&1 && stopped=$((stopped + 1)) || true
        done
    fi
    for croot in /data/data /data/user/0; do
        if [ -d "$croot/com.android.vending" ]; then
            rm -rf "$croot/com.android.vending/cache/"* "$croot/com.android.vending/code_cache/"* 2>/dev/null || true
        fi
    done
    kgx_log "INFO" "spoof" "Refreshed Play Store & GMS processes ($stopped stopped) for Play Integrity Shield reload."
    return 0
}

spoof_check_conflicts() {
    local mod_dir mid mname conflict_list="" conflict_count=0
    local rp_bin="" has_rp="false" has_zygisk="false" zygisk_daemon_ok="false" pi_shield="false" orig_captured="false"
    local shield_note

    kgx_load_config
    hw_load
    rp_bin="$(kgx_find_resetprop 2>/dev/null || true)"
    [ -n "$rp_bin" ] && has_rp="true"
    if kgx_is_zygisk_active; then
        has_zygisk="true"
        if [ -S /data/adb/rezygisk/zygiskd.sock ] || pidof zygiskd64 >/dev/null 2>&1 || pidof rezygiskd >/dev/null 2>&1; then
            zygisk_daemon_ok="true"
        fi
    fi
    [ -s "$KGX_DATA_DIR/state/orig_props.tsv" ] && orig_captured="true"
    if [ "${PLAY_INTEGRITY_SHIELD:-1}" = "1" ] && [ "$has_zygisk" = "true" ]; then
        pi_shield="true"
    fi

    if [ -d "$KGX_MODULES_ROOT" ]; then
        for mod_dir in "$KGX_MODULES_ROOT"/*; do
            [ -d "$mod_dir" ] || continue
            mid="${mod_dir##*/}"
            [ "$mid" = "ksu_ultimate_gaming_x" ] && continue
            [ -e "$mod_dir/disable" ] && continue
            [ -e "$mod_dir/remove" ] && continue

            case "$(printf '%s' "$mid" | tr '[:upper:]' '[:lower:]')" in
                *props*|*spoof*|*ih8sn*|*pixelify*|*unlocker*|*fps*)
                    mname="$mid"
                    if [ -f "$mod_dir/module.prop" ]; then
                        mname="$(awk -F '=' '/^name=/{print $2; exit}' "$mod_dir/module.prop" | tr -d '\r')"
                        [ -n "$mname" ] || mname="$mid"
                    fi
                    conflict_count=$((conflict_count + 1))
                    if [ -n "$conflict_list" ]; then
                        conflict_list="${conflict_list},"
                    fi
                    conflict_list="${conflict_list}{\"id\":\"$(json_escape "$mid")\",\"name\":\"$(json_escape "$mname")\",\"risk\":\"May overwrite ro.product.* props concurrently\"}"
                    ;;
            esac
        done
    fi

    if [ "$pi_shield" = "true" ] && [ "$zygisk_daemon_ok" = "true" ]; then
        shield_note="Stock-Identity Shield (Zygisk arm64-v8a.so) active & injected: GMS/Play Store, Settings & Denylist apps receive stock device identity while games see spoofed flagship."
    elif [ "$pi_shield" = "true" ]; then
        shield_note="Zygisk module enabled, waiting for Zygisk daemon socket (soft-reboot to initialize ReZygisk cleanly)."
    elif [ "${PLAY_INTEGRITY_SHIELD:-1}" = "1" ]; then
        shield_note="ReZygisk/ZygiskNext disabled or missing! Enable ReZygisk and Soft-Reboot so GMS/Play Store isolate back to stock model."
    else
        shield_note="Play Integrity Shield disabled in settings; GMS sees whole-system safe props."
    fi

    printf '{'
    printf '"has_resetprop":%s,' "$has_rp"
    printf '"resetprop_bin":"%s",' "$(json_escape "$rp_bin")"
    printf '"has_zygisk":%s,' "$has_zygisk"
    printf '"zygisk_active":%s,' "$zygisk_daemon_ok"
    printf '"play_integrity_shield":%s,' "$pi_shield"
    printf '"orig_captured":%s,' "$orig_captured"
    printf '"gpu_vendor":"%s",' "$(json_escape "$GPU_VENDOR")"
    printf '"conflict_count":%s,' "$conflict_count"
    printf '"conflicts":[%s],' "$conflict_list"
    printf '"shield_note":"%s"' "$(json_escape "$shield_note")"
    printf '}\n'
}
