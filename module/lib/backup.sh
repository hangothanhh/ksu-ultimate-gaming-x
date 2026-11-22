#!/system/bin/sh
# KSU Ultimate Gaming X - Configuration & Baseline Backup/Restore

backup_create() {
    local label="${1:-manual}"
    local ts fname bpath

    kgx_sanitize_id "$label" || label="manual"
    mkdir -p "$KGX_DATA_DIR/backups" 2>/dev/null || true
    ts="$(date '+%Y%m%d_%H%M%S' 2>/dev/null || printf '00000000_000000')"
    fname="kgx_backup_${ts}_${label}.tar.gz"
    bpath="$KGX_DATA_DIR/backups/$fname"

    # Build clean archive of config/, profiles/, and stock baseline snapshots
    (
        cd "$KGX_DATA_DIR" || exit 1
        items=""
        [ -d config ] && items="$items config"
        [ -d profiles ] && items="$items profiles"
        for snap in state/orig_props.tsv state/orig_display.env state/orig_net.env; do
            [ -f "$snap" ] && items="$items $snap"
        done
        [ -n "$items" ] || exit 1
        tar -czf "$bpath" $items 2>/dev/null
    ) || {
        printf '{"ok":false,"error":"Failed to create backup archive"}\n'
        return 1
    }

    kgx_log "INFO" "backup" "Created backup $fname"
    printf '{"ok":true,"name":"%s","size_bytes":%s}\n' \
        "$(json_escape "$fname")" "$(wc -c < "$bpath" 2>/dev/null | tr -dc '0-9')"
}

backup_list() {
    local bdir="$KGX_DATA_DIR/backups"
    local items="" f bname sz first=1
    mkdir -p "$bdir" 2>/dev/null || true

    for f in $(ls -1t "$bdir"/kgx_backup_*.tar.gz 2>/dev/null); do
        [ -f "$f" ] || continue
        bname="${f##*/}"
        sz="$(wc -c < "$f" 2>/dev/null | tr -dc '0-9')"
        [ -n "$sz" ] || sz=0
        if [ "$first" -eq 0 ]; then
            items="${items},"
        fi
        first=0
        items="${items}{\"name\":\"$(json_escape "$bname")\",\"size_bytes\":$sz}"
    done
    printf '{"backups":[%s]}\n' "$items"
}

backup_restore() {
    local name="$1"
    local bpath

    case "$name" in
        ''|*/*|*..*|*\\*)
            printf '{"ok":false,"error":"Invalid backup name"}\n'
            return 1
            ;;
    esac
    kgx_sanitize_id "$name" || {
        printf '{"ok":false,"error":"Invalid characters in backup name"}\n'
        return 1
    }

    bpath="$KGX_DATA_DIR/backups/$name"
    [ -f "$bpath" ] || {
        printf '{"ok":false,"error":"Backup file not found"}\n'
        return 1
    }

    tar -xzf "$bpath" -C "$KGX_DATA_DIR" 2>/dev/null || {
        printf '{"ok":false,"error":"Failed to extract backup archive"}\n'
        return 1
    }

    kgx_load_config
    kgx_log "INFO" "backup" "Restored configuration & profiles from $name"
    printf '{"ok":true,"restored":"%s"}\n' "$(json_escape "$name")"
    return 0
}
