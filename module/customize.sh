#!/system/bin/sh
# KSU Ultimate Gaming X - Module Installer Script (v1.0.0)

KGX_DATA_DIR="${KGX_DATA_DIR:-/data/adb/ksu_gaming_x}"

kgx_ui() {
    if command -v ui_print >/dev/null 2>&1; then
        ui_print "$1"
    else
        printf '%s\n' "$1"
    fi
}

kgx_abort() {
    if command -v abort >/dev/null 2>&1; then
        abort "$1"
    else
        printf 'ABORT: %s\n' "$1" >&2
        exit 1
    fi
}

kgx_set_perm() {
    if command -v set_perm >/dev/null 2>&1; then
        set_perm "$4" "$1" "$2" "$3"
    else
        chown "$1:$2" "$4" 2>/dev/null || true
        chmod "$3" "$4"
    fi
}

kgx_ui "==================================================="
kgx_ui " KSU Ultimate Gaming X v1.0.0"
kgx_ui " Zero-Lock Rust Engine + Scene Popup + Ext Off"
kgx_ui "==================================================="

# Architecture check: ARM64 required
if [ -n "$ARCH" ] && [ "$ARCH" != "arm64" ]; then
    kgx_abort "! Unsupported architecture: $ARCH (ARM64 required)"
fi

# Android API check
if [ -n "$API" ]; then
    if [ "$API" -lt 26 ] 2>/dev/null; then
        kgx_abort "! Android API $API is too old (minimum Android 8.0 / API 26)"
    fi
    if [ "$API" -lt 29 ] 2>/dev/null; then
        kgx_ui "- Warning: Android API $API detected; cmd game / dynamic display features may be limited"
    fi
fi

# Root manager detection (KernelSU primary)
if [ "$KSU" = "true" ]; then
    kgx_ui "- Environment: KernelSU (ver=${KSU_VER:-unknown}, code=${KSU_VER_CODE:-unknown})"
elif [ "$APATCH" = "true" ]; then
    kgx_ui "- Environment: APatch (KernelSU-compatible WebUI/resetprop)"
else
    kgx_ui "- Environment: Non-KernelSU / Generic root manager (KernelSU is primary target)"
fi

# Initialize persistent data directories (preserve user configs across upgrades)
mkdir -p \
    "$KGX_DATA_DIR/config" \
    "$KGX_DATA_DIR/state" \
    "$KGX_DATA_DIR/backups" \
    "$KGX_DATA_DIR/logs" \
    "$KGX_DATA_DIR/profiles"

cfg_file="$KGX_DATA_DIR/config/global.conf"
if [ ! -f "$cfg_file" ] && [ -f "$MODPATH/data/default_global.conf" ]; then
    cp "$MODPATH/data/default_global.conf" "$cfg_file"
    kgx_ui "- Installed default global configuration"
else
    # Migrate v1.x/v2.x/v3.x configs cleanly: remove deprecated keys & ensure v3.2 keys
    tmp_cfg="$cfg_file.mig.$$"
    awk '
        !/^SPOOF_MODE=/ && !/^SPOOF_MINIMAL_MODE=/ && !/^NET_RESTRICT_BG=/ { print }
        /^PLAY_INTEGRITY_SHIELD=/ { has_pis = 1 }
        /^SPOOF_EXCLUDE_SETTINGS=/ { has_ses = 1 }
        /^SUSTAINED_SWEET_SPOT=/ { has_sws = 1 }
        /^GOS_NEUTRALIZE=/ { has_gos = 1 }
        /^EXT_DISPLAY_SCREEN_OFF=/ { has_ext = 1 }
        /^BYPASS_CHARGING=/ { has_byp = 1 }
        /^BYPASS_MIN_PCT=/ { has_bmp = 1 }
        END {
            if (!has_pis) print "PLAY_INTEGRITY_SHIELD=1"
            if (!has_ses) print "SPOOF_EXCLUDE_SETTINGS=1"
            if (!has_sws) print "SUSTAINED_SWEET_SPOT=0"
            if (!has_gos) print "GOS_NEUTRALIZE=0"
            if (!has_ext) print "EXT_DISPLAY_SCREEN_OFF=0"
            if (!has_byp) print "BYPASS_CHARGING=0"
            if (!has_bmp) print "BYPASS_MIN_PCT=80"
        }
    ' "$cfg_file" > "$tmp_cfg" && mv "$tmp_cfg" "$cfg_file"
    kgx_ui "- Migrated & preserved user configuration (Play Integrity Shield enabled)"
fi

if [ ! -f "$KGX_DATA_DIR/config/custom_games.tsv" ]; then
    printf '# package\tenabled\tspoof_profile\ttarget_fps\tmode\tdisplay_hz\ttouch_profile\tnet_opt\tdownscale\n' > "$KGX_DATA_DIR/config/custom_games.tsv"
fi

if [ ! -f "$KGX_DATA_DIR/profiles/custom_profiles.tsv" ]; then
    printf '# id\tlabel\tcategory\tsoc_family\tgpu_family\ttier\tmax_hz\tram_gb\tbrand\tmanufacturer\tmodel\tdevice\tproduct\tfingerprint\tnotes\n' > "$KGX_DATA_DIR/profiles/custom_profiles.tsv"
fi

# Remove legacy WebUI directories if upgrading from v1.x/v2.x/v3.0
rm -rf "$MODPATH/webroot" "/data/adb/modules/ksu_ultimate_gaming_x/webroot" 2>/dev/null || true

# Set executable permissions on scripts & binaries
for f in \
    "$MODPATH/post-fs-data.sh" \
    "$MODPATH/service.sh" \
    "$MODPATH/uninstall.sh" \
    "$MODPATH/action.sh" \
    "$MODPATH/bin/kgxctl" \
    "$MODPATH/bin/kgx-core" \
    "$MODPATH/bin/gaming_daemon.sh"; do
    if [ -f "$f" ]; then
        kgx_set_perm 0 0 0755 "$f"
    fi
done

if [ -d "$MODPATH/lib" ]; then
    for libf in "$MODPATH/lib"/*.sh; do
        if [ -f "$libf" ]; then
            kgx_set_perm 0 0 0755 "$libf"
        fi
    done
fi

if [ -d "$MODPATH/data" ]; then
    for dataf in "$MODPATH/data"/*; do
        if [ -f "$dataf" ]; then
            kgx_set_perm 0 0 0644 "$dataf"
        fi
    done
fi

if [ -f "$MODPATH/zygisk/arm64-v8a.so" ]; then
    kgx_set_perm 0 0 0644 "$MODPATH/zygisk/arm64-v8a.so"
    kgx_ui "- Bundled Play Integrity Shield Zygisk arm64-v8a library installed"
fi

# Refresh hardware capability cache, migrate baselines & prepare safe whole-system spoof on install/upgrade
rm -f "$KGX_DATA_DIR/state/zygisk_rules.conf" 2>/dev/null || true

if [ -f "$MODPATH/lib/common.sh" ] && [ -f "$MODPATH/lib/spoof.sh" ]; then
    export KGX_MODDIR="$MODPATH"
    export KGX_DATA_DIR
    . "$MODPATH/lib/common.sh"
    . "$MODPATH/lib/matcher.sh"
    . "$MODPATH/lib/hw_detect.sh"
    . "$MODPATH/lib/display.sh"
    . "$MODPATH/lib/spoof.sh"

    kgx_load_config
    hw_detect_all >/dev/null 2>&1 || true
    display_migrate_original >/dev/null 2>&1 || true
    spoof_capture_original
    if [ "${SAFE_MODE:-0}" != "1" ] && [ "${SPOOF_ENABLED:-1}" = "1" ]; then
        spoof_write_system_prop "${GLOBAL_SPOOF_PROFILE:-realme_14_5g}"
        [ -f "$MODPATH/system.prop" ] && kgx_set_perm 0 0 0644 "$MODPATH/system.prop"
        kgx_ui "- Prepared safe whole-system spoof: ${GLOBAL_SPOOF_PROFILE:-realme_14_5g}"
    else
        spoof_clear_system_prop
    fi
fi

if [ ! -f "$KGX_DATA_DIR/config/spoof_denylist.list" ]; then
    printf '# One package per line\n' > "$KGX_DATA_DIR/config/spoof_denylist.list"
fi
kgx_set_perm 0 0 0644 "$KGX_DATA_DIR/config/spoof_denylist.list" 2>/dev/null || true

kgx_set_perm 0 0 0644 "$KGX_DATA_DIR/config/global.conf" 2>/dev/null || true
kgx_set_perm 0 0 0644 "$KGX_DATA_DIR/config/custom_games.tsv" 2>/dev/null || true
kgx_set_perm 0 0 0644 "$KGX_DATA_DIR/profiles/custom_profiles.tsv" 2>/dev/null || true

kgx_ui "- Installation complete! Open KSU Gaming X App to configure."
