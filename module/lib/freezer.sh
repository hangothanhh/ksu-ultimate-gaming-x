#!/system/bin/sh
# KSU Ultimate Gaming X v1.0.0 - View & DeX-Safe cgroup v2 App Freezer

freezer_is_supported() {
    local d
    [ -d "$KGX_CGROUP_ROOT" ] || return 1
    for d in "$KGX_CGROUP_ROOT"/uid_*; do
        [ -f "$d/cgroup.freeze" ] && return 0
    done
    return 1
}

freezer_is_protected_pkg() {
    local pkg="$1"
    [ -n "$pkg" ] || return 0
    case "$pkg" in
        android|com.android.*|com.kgx.ultimate|\
        com.sec.android.desktopmode*|com.sec.android.app.desktoplauncher*|\
        com.sec.android.app.dexonpc*|com.samsung.android.app.cocktailbarservice*|\
        com.samsung.android.honeyboard*|com.sec.android.app.launcher*|\
        com.google.android.gms*|com.google.android.gsf*|\
        me.weishu.kernelsu|com.rifsxd.ksunext|me.bmax.apatch|com.topjohnwu.magisk|com.termux)
            return 0
            ;;
    esac
    if [ -f "$KGX_MODDIR/data/protected_pkgs.list" ]; then
        if grep -qx "$pkg" "$KGX_MODDIR/data/protected_pkgs.list" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

freezer_pkg_to_uid() {
    local pkg="$1"
    local uid="" plist="${KGX_PKGS_LIST:-/data/system/packages.list}"
    [ -n "$pkg" ] || return 1
    if [ -r "$plist" ]; then
        uid="$(awk -v p="$pkg" '$1==p{print $2; exit}' "$plist" 2>/dev/null | tr -dc '0-9')"
    fi
    if [ -z "$uid" ] && command -v pm >/dev/null 2>&1; then
        uid="$(pm list packages -U "$pkg" 2>/dev/null | awk -v p="$pkg" '
            $1 == ("package:" p) {
                for (i = 2; i <= NF; i++) {
                    if ($i ~ /^uid:/) {
                        sub(/^uid:/, "", $i);
                        print $i;
                        exit;
                    }
                }
            }' | tr -dc '0-9')"
    fi
    [ -n "$uid" ] || return 1
    printf '%s\n' "$uid"
}

freezer_uid_min_oom_adj() {
    local target_uid="$1"
    local pdir uid_line pid_uid adj min_adj=9999

    [ -d "$KGX_PROC_ROOT" ] || { printf '9999\n'; return 0; }
    for pdir in "$KGX_PROC_ROOT"/[0-9]*; do
        [ -r "$pdir/status" ] || continue
        uid_line="$(awk '/^Uid:/{print $2; exit}' "$pdir/status" 2>/dev/null)"
        [ "$uid_line" = "$target_uid" ] || continue
        if [ -r "$pdir/oom_score_adj" ]; then
            adj="$(cat "$pdir/oom_score_adj" 2>/dev/null | head -n 1 | tr -dc '0-9-')"
            case "$adj" in
                ''|-) continue ;;
            esac
            [ "$adj" -lt "$min_adj" ] 2>/dev/null && min_adj="$adj"
        fi
    done
    printf '%s\n' "$min_adj"
}

freezer_collect_open_pkgs() {
    command -v dumpsys >/dev/null 2>&1 || return 0
    dumpsys SurfaceFlinger --list 2>/dev/null | awk '
    {
        if (match($0, /[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+\//)) {
            p = substr($0, RSTART, RLENGTH - 1)
            if (p !~ /^android\./ && !seen[p]++) {
                print p
            }
        }
    }'
}

freezer_is_pkg_in_list() {
    local pkg="$1" list_nl="$2"
    [ -n "$list_nl" ] || return 1
    printf '%s\n' "$list_nl" | grep -qx "$pkg" 2>/dev/null
}

freezer_set_uid_freeze() {
    local uid="$1" val="$2"
    local fnode="$KGX_CGROUP_ROOT/uid_$uid/cgroup.freeze"
    [ -f "$fnode" ] || return 1
    [ -w "$fnode" ] || chmod 0644 "$fnode" 2>/dev/null || true
    echo "$val" > "$fnode" 2>/dev/null
}

freezer_unfreeze_all() {
    local state_file="$KGX_DATA_DIR/state/frozen_uids.tsv"
    local uid pkg cnt=0
    if [ -f "$state_file" ]; then
        while IFS='	' read -r uid pkg || [ -n "$uid" ]; do
            [ -n "$uid" ] || continue
            if freezer_set_uid_freeze "$uid" "0"; then
                cnt=$((cnt + 1))
            fi
        done < "$state_file"
        rm -f "$state_file" 2>/dev/null || true
        if [ "$cnt" -gt 0 ]; then
            kgx_log "INFO" "freezer" "Unfroze $cnt previously frozen app UID(s)."
        fi
    fi
    return 0
}

freezer_sync() {
    local active_pkg="${1:-}"
    local cfg_list="$KGX_DATA_DIR/config/freezer_apps.list"
    local state_file="$KGX_DATA_DIR/state/frozen_uids.tsv"
    local tmp_state="$state_file.tmp.$$"
    local open_pkgs="" line pkg uid adj keep_list="" frozen_now=0 unfroze_now=0

    kgx_load_config
    if [ "${SAFE_MODE:-0}" = "1" ] || [ "${FREEZER_ENABLED:-0}" != "1" ] || ! freezer_is_supported; then
        freezer_unfreeze_all
        return 0
    fi

    if [ -z "$active_pkg" ] && [ -f "$KGX_DATA_DIR/state/active_session.env" ]; then
        . "$KGX_DATA_DIR/state/active_session.env"
        active_pkg="${ACTIVE_PKG:-}"
    fi

    open_pkgs="$(freezer_collect_open_pkgs)"
    mkdir -p "$KGX_DATA_DIR/state" 2>/dev/null || true
    : > "$tmp_state"

    # Step A: Auto-unfreeze any UID that is now active, in Pop-up/Split/DeX View, low oom_adj, or unlisted
    if [ -f "$state_file" ]; then
        while IFS='	' read -r uid pkg || [ -n "$uid" ]; do
            [ -n "$uid" ] && [ -n "$pkg" ] || continue
            if [ "$pkg" = "$active_pkg" ] || freezer_is_protected_pkg "$pkg" \
               || ! grep -qx "$pkg" "$cfg_list" 2>/dev/null \
               || freezer_is_pkg_in_list "$pkg" "$open_pkgs"; then
                freezer_set_uid_freeze "$uid" "0" || true
                unfroze_now=$((unfroze_now + 1))
                continue
            fi
            adj="$(freezer_uid_min_oom_adj "$uid")"
            if [ "$adj" -le 300 ] 2>/dev/null; then
                freezer_set_uid_freeze "$uid" "0" || true
                unfroze_now=$((unfroze_now + 1))
                continue
            fi
            printf '%s\t%s\n' "$uid" "$pkg" >> "$tmp_state"
        done < "$state_file"
    fi

    # Step B: Freeze eligible background target UIDs during active game session (strictly skipping View/DeX/low-adj)
    if [ -n "$active_pkg" ] && [ -f "$cfg_list" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            line="$(printf '%s' "$line" | tr -d '\r' | awk '{$1=$1;print}')"
            case "$line" in ''|\#*) continue ;; esac
            pkg="$line"
            kgx_sanitize_pkg "$pkg" || continue
            [ "$pkg" = "$active_pkg" ] && continue
            freezer_is_protected_pkg "$pkg" && continue
            freezer_is_pkg_in_list "$pkg" "$open_pkgs" && continue

            uid="$(freezer_pkg_to_uid "$pkg" 2>/dev/null || true)"
            [ -n "$uid" ] && [ "$uid" -ge 10000 ] 2>/dev/null || continue
            [ -f "$KGX_CGROUP_ROOT/uid_$uid/cgroup.freeze" ] || continue

            if grep -q "^${uid}	" "$tmp_state" 2>/dev/null; then
                continue
            fi

            adj="$(freezer_uid_min_oom_adj "$uid")"
            # Require running background process with oom_score_adj >= 500 (never freeze foreground/View/DeX/dead)
            [ "$adj" -lt 9999 ] 2>/dev/null && [ "$adj" -ge 500 ] 2>/dev/null || continue

            if freezer_set_uid_freeze "$uid" "1"; then
                printf '%s\t%s\n' "$uid" "$pkg" >> "$tmp_state"
                frozen_now=$((frozen_now + 1))
            fi
        done < "$cfg_list"
    fi

    if [ -s "$tmp_state" ]; then
        mv "$tmp_state" "$state_file"
    else
        rm -f "$tmp_state" "$state_file" 2>/dev/null || true
    fi

    if [ "$frozen_now" -gt 0 ] || [ "$unfroze_now" -gt 0 ]; then
        kgx_log "INFO" "freezer" "Synced View/DeX-safe freezer (frozen=+$frozen_now, unfrozen=$unfroze_now, game=$active_pkg)."
    fi
    return 0
}

freezer_set_list_b64() {
    local b64="$1"
    local cfg_list="$KGX_DATA_DIR/config/freezer_apps.list"
    local tmp="$cfg_list.tmp.$$"
    local decoded line

    mkdir -p "$KGX_DATA_DIR/config" 2>/dev/null || true
    decoded="$(printf '%s' "$b64" | tr -d '\r\n' | base64 -d 2>/dev/null)" || return 1

    printf '# One package per line\n' > "$tmp"
    printf '%s\n' "$decoded" | while IFS= read -r line || [ -n "$line" ]; do
        line="$(printf '%s' "$line" | tr -d '\r' | awk '{$1=$1;print}')"
        [ -n "$line" ] || continue
        kgx_sanitize_pkg "$line" || continue
        freezer_is_protected_pkg "$line" && continue
        printf '%s\n' "$line" >> "$tmp"
    done
    mv "$tmp" "$cfg_list"
    freezer_sync
    return 0
}

freezer_status_json() {
    local cfg_list="$KGX_DATA_DIR/config/freezer_apps.list"
    local state_file="$KGX_DATA_DIR/state/frozen_uids.tsv"
    local en="false" sup="false" targets="" frozen="" t_cnt=0 f_cnt=0 line uid pkg

    kgx_load_config
    [ "${FREEZER_ENABLED:-0}" = "1" ] && en="true"
    freezer_is_supported && sup="true"

    if [ -f "$cfg_list" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            line="$(printf '%s' "$line" | tr -d '\r' | awk '{$1=$1;print}')"
            case "$line" in ''|\#*) continue ;; esac
            [ "$t_cnt" -gt 0 ] && targets="${targets},"
            targets="${targets}\"$(json_escape "$line")\""
            t_cnt=$((t_cnt + 1))
        done < "$cfg_list"
    fi

    if [ -f "$state_file" ]; then
        while IFS='	' read -r uid pkg || [ -n "$uid" ]; do
            [ -n "$uid" ] && [ -n "$pkg" ] || continue
            [ "$f_cnt" -gt 0 ] && frozen="${frozen},"
            frozen="${frozen}{\"uid\":$uid,\"package\":\"$(json_escape "$pkg")\"}"
            f_cnt=$((f_cnt + 1))
        done < "$state_file"
    fi

    printf '{"ok":true,"enabled":%s,"supported":%s,"target_count":%s,"frozen_count":%s,"targets":[%s],"frozen":[%s]}\n' \
        "$en" "$sup" "$t_cnt" "$f_cnt" "$targets" "$frozen"
}
