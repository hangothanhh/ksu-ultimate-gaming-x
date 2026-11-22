#!/system/bin/sh
# KSU Ultimate Gaming X - Network Gaming Priority & Latency Telemetry Engine (v3.0 - Zero netpolicy disruption)

network_detect_transport() {
    local conn=""
    if [ -r "$KGX_SYS_ROOT/class/net/wlan0/operstate" ]; then
        if [ "$(cat "$KGX_SYS_ROOT/class/net/wlan0/operstate" 2>/dev/null)" = "up" ]; then
            printf 'WIFI\n'; return 0
        fi
    fi
    if command -v ip >/dev/null 2>&1; then
        case "$(ip route get 1.1.1.1 2>/dev/null)" in
            *wlan*) printf 'WIFI\n'; return 0 ;;
            *rmnet*|*ccmni*) printf 'MOBILE\n'; return 0 ;;
            *eth*) printf 'ETHERNET\n'; return 0 ;;
        esac
    fi
    if command -v dumpsys >/dev/null 2>&1; then
        conn="$(dumpsys connectivity 2>/dev/null | grep -E 'VALIDATED|CONNECTED' | head -n 10)"
        case "$(printf '%s' "$conn" | tr '[:lower:]' '[:upper:]')" in
            *ETHERNET*) printf 'ETHERNET\n'; return 0 ;;
            *WIFI*)     printf 'WIFI\n'; return 0 ;;
            *CELLULAR*|*MOBILE*) printf 'MOBILE\n'; return 0 ;;
        esac
    fi
    printf 'NONE\n'
}

network_apply() {
    local _pkg="${1:-}"
    local transport wifi_ll=0
    local state_file="$KGX_DATA_DIR/state/active_net.env"

    [ "${NET_OPT_ENABLED:-1}" = "1" ] || return 0
    transport="$(network_detect_transport)"

    if [ "$transport" = "WIFI" ] && [ "${NET_WIFI_LOW_LATENCY:-1}" = "1" ] && command -v cmd >/dev/null 2>&1; then
        if cmd wifi force-low-latency-mode enabled >/dev/null 2>&1; then
            wifi_ll=1
        fi
    fi

    cat > "$state_file" <<EOF
NET_TRANSPORT='$transport'
NET_WIFI_LL='$wifi_ll'
EOF
    kgx_log "INFO" "network" "Applied network profile (transport=$transport, wifi_low_latency=$wifi_ll)"
    return 0
}

network_restore() {
    local state_file="$KGX_DATA_DIR/state/active_net.env"

    if [ -f "$state_file" ]; then
        . "$state_file"
        if command -v cmd >/dev/null 2>&1 && [ "${NET_WIFI_LL:-0}" = "1" ]; then
            cmd wifi force-low-latency-mode disabled >/dev/null 2>&1 || true
        fi
        rm -f "$state_file" 2>/dev/null || true
    fi
    kgx_log "INFO" "network" "Restored Wi-Fi latency mode."
    return 0
}

network_measure_ping() {
    local host="${1:-${NET_PING_HOST:-1.1.1.1}}"
    local transport out loss min_ms avg_ms max_ms jitter_ms status

    kgx_sanitize_id "$host" || host="1.1.1.1"
    transport="$(network_detect_transport)"

    if ! command -v ping >/dev/null 2>&1; then
        printf '{"transport":"%s","host":"%s","reachable":false,"loss_pct":100,"min_ms":0,"avg_ms":0,"max_ms":0,"jitter_ms":0,"note":"ping command unavailable"}\n' \
            "$transport" "$(json_escape "$host")"
        return 0
    fi

    out="$(ping -c 4 -W 2 "$host" 2>/dev/null || true)"
    if [ -z "$out" ]; then
        printf '{"transport":"%s","host":"%s","reachable":false,"loss_pct":100,"min_ms":0,"avg_ms":0,"max_ms":0,"jitter_ms":0,"note":"No ICMP response (offline or ICMP blocked)."}\n' \
            "$transport" "$(json_escape "$host")"
        return 0
    fi

    loss="$(printf '%s\n' "$out" | awk -F '%' '/packet loss/{for(i=1;i<=NF;i++){}; if(match($1,/ [0-9.]+$/)){print substr($1,RSTART+1,RLENGTH-1); exit}}')"
    [ -n "$loss" ] || loss="100"

    set -- $(printf '%s\n' "$out" | awk -F '=' '/min\/avg\/max/{
        val=$2; gsub(/ ms.*/,"",val); gsub(/^ /,"",val)
        split(val, a, "/")
        printf "%s %s %s %s\n", (a[1]?a[1]:0), (a[2]?a[2]:0), (a[3]?a[3]:0), (a[4]?a[4]:0)
        exit
    }')
    min_ms="${1:-0}"; avg_ms="${2:-0}"; max_ms="${3:-0}"; jitter_ms="${4:-0}"
    status="true"
    [ "$avg_ms" = "0" ] && [ "$loss" = "100" ] && status="false"

    printf '{"transport":"%s","host":"%s","reachable":%s,"loss_pct":%s,"min_ms":%s,"avg_ms":%s,"max_ms":%s,"jitter_ms":%s,"note":"Real ICMP probe to %s. Wi-Fi low-latency reduces local queueing; ISP routing and server distance govern base ping."}\n' \
        "$transport" "$(json_escape "$host")" "$status" "$loss" "$min_ms" "$avg_ms" "$max_ms" "$jitter_ms" "$(json_escape "$host")"
}
