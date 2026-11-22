#!/system/bin/sh
# KSU Ultimate Gaming X - Touch & Input Latency Optimizer (Kernel-Dependent)

touch_apply() {
    local profile="${1:-standard}"
    local val="1"

    [ "${TOUCH_OPT_ENABLED:-1}" = "1" ] || return 0
    hw_load

    if [ "$profile" = "standard" ] && [ -z "$TOUCH_GAME_NODE" ]; then
        kgx_log "INFO" "touch" "Touch profile=$profile; no vendor game-mode kernel node exposed."
        return 0
    fi

    if [ -z "$TOUCH_GAME_NODE" ] || [ ! -e "$TOUCH_GAME_NODE" ]; then
        kgx_log "INFO" "touch" "KERNEL_NODE_UNAVAILABLE: device '$TOUCH_DRIVER' does not expose a writable game-mode sysfs node."
        return 0
    fi

    case "$TOUCH_GAME_NODE" in
        */sec/tsp/cmd)
            if [ "$profile" = "esports" ] || [ "$profile" = "precision" ]; then
                sysfs_safe_write "$TOUCH_GAME_NODE" "set_game_mode,1" || true
            fi
            ;;
        *)
            case "$profile" in
                esports|precision) val="1" ;;
                *) val="0" ;;
            esac
            sysfs_safe_write "$TOUCH_GAME_NODE" "$val" || true
            ;;
    esac

    kgx_log "INFO" "touch" "Applied touch profile '$profile' on node $TOUCH_GAME_NODE"
    return 0
}

touch_restore() {
    hw_load
    if [ -n "$TOUCH_GAME_NODE" ] && [ -w "$TOUCH_GAME_NODE" ]; then
        case "$TOUCH_GAME_NODE" in
            */sec/tsp/cmd)
                echo 'set_game_mode,0' > "$TOUCH_GAME_NODE" 2>/dev/null || true
                ;;
        esac
    fi
    kgx_log "INFO" "touch" "Touch kernel node state restored (via sysfs_restore_all)."
    return 0
}

# Measures actual touch report rate using getevent -t over 2 seconds (no synthetic values)
touch_measure_rate() {
    local dur="${1:-2}"
    local ev_path raw_out hz samples status msg

    hw_load
    if [ -z "$TOUCH_EVENT_DEV" ]; then
        printf '{"supported":false,"driver":"%s","hz":0,"samples":0,"status":"NO_EVENT_NODE","note":"No touchscreen input event device detected."}\n' \
            "$(json_escape "$TOUCH_DRIVER")"
        return 0
    fi

    ev_path="$KGX_DEV_ROOT/input/$TOUCH_EVENT_DEV"
    if [ ! -r "$ev_path" ] || ! command -v getevent >/dev/null 2>&1; then
        printf '{"supported":false,"driver":"%s","event_dev":"%s","hz":0,"samples":0,"status":"UNAVAILABLE","note":"getevent or %s not readable."}\n' \
            "$(json_escape "$TOUCH_DRIVER")" "$TOUCH_EVENT_DEV" "$(json_escape "$ev_path")"
        return 0
    fi

    if command -v timeout >/dev/null 2>&1; then
        raw_out="$(timeout "$dur" getevent -t "$ev_path" 2>/dev/null || true)"
    else
        raw_out="$(getevent -c 120 -t "$ev_path" 2>/dev/null || true)"
    fi

    # SYN_REPORT lines (0000 0000) mark touch frame boundaries
    set -- $(printf '%s\n' "$raw_out" | awk '
        /0000 0000/ {
            if (match($0, /[0-9]+\.[0-9]+/)) {
                t = substr($0, RSTART, RLENGTH) + 0
                if (prev > 0 && t > prev) {
                    dt = t - prev
                    if (dt > 0.001 && dt < 0.2) {
                        sum += dt
                        cnt++
                    }
                }
                prev = t
            }
        }
        END {
            if (cnt >= 3 && sum > 0) {
                hz = int((cnt / sum) + 0.5)
                print hz, cnt
            } else {
                print 0, cnt+0
            }
        }')
    hz="${1:-0}"
    samples="${2:-0}"

    if [ "$hz" -gt 0 ] 2>/dev/null; then
        status="MEASURED"
        msg="Measured real touchscreen SYN_REPORT rate from $TOUCH_EVENT_DEV."
    else
        status="NO_TOUCH_INPUT"
        msg="Touch screen during measurement window to sample real report Hz."
    fi

    printf '{"supported":true,"driver":"%s","event_dev":"%s","hz":%s,"samples":%s,"status":"%s","note":"%s"}\n' \
        "$(json_escape "$TOUCH_DRIVER")" "$TOUCH_EVENT_DEV" "$hz" "$samples" "$status" "$(json_escape "$msg")"
}
