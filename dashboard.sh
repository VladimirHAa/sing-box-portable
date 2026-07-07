#!/bin/bash
# sing-box portable dashboard — status + traffic in one window
# Usage: ./dashboard.sh [start|stop|status]

DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$DIR/sing-box.log"
CLASH="http://127.0.0.1:9090"
BYPASS_IPS=("46.8.233.202/32" "31.77.77.47/32" "94.126.153.10/32")
BYPASS_PRIO=8998
TUN_IF="sing-tun"
INTERVAL=2
export ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true

fmt_bytes() {
    local b=$1
    if   (( b >= 1073741824 )); then printf "%.2f GB" "$(echo "scale=2; $b/1073741824" | bc)"
    elif (( b >= 1048576 ));    then printf "%.1f MB" "$(echo "scale=1; $b/1048576" | bc)"
    elif (( b >= 1024 ));       then printf "%.0f KB" "$(echo "scale=0; $b/1024" | bc)"
    else                             printf "%d B" "$b"
    fi
}

fmt_rate() {
    local bps=$1
    if   (( bps >= 1048576 )); then printf "%.1f MB/s" "$(echo "scale=1; $bps/1048576" | bc)"
    elif (( bps >= 1024 ));    then printf "%.0f KB/s" "$(echo "scale=0; $bps/1024" | bc)"
    else                             printf "%d B/s" "$bps"
    fi
}

is_running() { pgrep -f "sing-box run -c $DIR" >/dev/null 2>&1; }

add_bypass_routes() {
    local gw dev
    gw=$(ip route show default | awk '{print $3}' | head -1)
    dev=$(ip route show default | awk '{print $5}' | head -1)
    [ -z "$gw" ] && return 1
    for ip in "${BYPASS_IPS[@]}"; do
        sudo ip route replace "$ip" via "$gw" dev "$dev" 2>/dev/null
        sudo ip rule add to "$ip" table main priority $BYPASS_PRIO 2>/dev/null || true
    done
}

del_bypass_routes() {
    for ip in "${BYPASS_IPS[@]}"; do sudo ip route del "$ip" 2>/dev/null || true; done
    while sudo ip rule show 2>/dev/null | grep -q "^${BYPASS_PRIO}:"; do
        sudo ip rule del priority $BYPASS_PRIO 2>/dev/null || break
    done
}

start_singbox() {
    echo "[*] Starting sing-box..."
    [ ! -f "$DIR/sing-box" ] && { echo "[!] sing-box binary not found"; exit 1; }
    [ ! -f "$DIR/config.json" ] && { echo "[!] config.json not found"; exit 1; }
    pkill -f "sing-box run -c $DIR" 2>/dev/null; sleep 1
    for iface in sing-tun0 sing-tun1 sing-tun; do
        ip link show "$iface" &>/dev/null && ip link delete "$iface" 2>/dev/null
    done
    add_bypass_routes || true
    nohup "$DIR/sing-box" run -c "$DIR/config.json" > "$LOG" 2>&1 &
    echo "[*] PID: $!"
    for i in $(seq 1 10); do
        if ip link show "$TUN_IF" 2>/dev/null | grep -q UP && ss -tlnp 2>/dev/null | grep -q ":1080 "; then break; fi
        sleep 1
    done
    resolvectl dns "$TUN_IF" '' 2>/dev/null || true
    resolvectl default-route "$TUN_IF" false 2>/dev/null || true
    sleep 1
    echo -n "[+] Exit IP: "
    curl -4 -s --connect-timeout 5 --socks5 127.0.0.1:1080 https://ifconfig.me 2>/dev/null || echo "?"
    echo ""
}

stop_singbox() {
    echo "[*] Stopping sing-box..."
    pkill -f "sing-box run -c $DIR" 2>/dev/null; sleep 1
    pkill -9 -f "sing-box run -c $DIR" 2>/dev/null
    for iface in sing-tun0 sing-tun1 sing-tun; do
        ip link show "$iface" &>/dev/null && ip link delete "$iface" 2>/dev/null
    done
    del_bypass_routes
    echo "[+] Stopped"
}

dashboard() {
    local prev_up=0 prev_down=0
    while true; do
        clear
        local now=$(date '+%Y-%m-%d %H:%M:%S')
        local pid=$(pgrep -f "sing-box run -c $DIR" 2>/dev/null)

        echo "╔══════════════════════════════════════════════════════╗"
        echo "║          SING-BOX PORTABLE DASHBOARD                ║"
        echo "╠══════════════════════════════════════════════════════╣"

        if [ -n "$pid" ]; then
            echo "║  STATUS:  RUNNING (PID $pid)                       ║"
        else
            echo "║  STATUS:  STOPPED                                  ║"
        fi

        echo "╠══════════════════════════════════════════════════════╣"

        echo -n "║  Exit IP: "
        local exit_ip=$(curl -4 -s --connect-timeout 3 --socks5 127.0.0.1:1080 https://ifconfig.me 2>/dev/null)
        printf "%-40s ║\n" "${exit_ip:-(unavailable)}"

        echo -n "║  TUN:     "
        if ip link show "$TUN_IF" 2>/dev/null | grep -q UP; then printf "%-40s ║\n" "UP"; else printf "%-40s ║\n" "DOWN"; fi

        echo "║  SOCKS5:  127.0.0.1:1080                            ║"
        echo "║  HTTP:    127.0.0.1:8080                            ║"
        echo "║  Clash:   127.0.0.1:9090                            ║"

        echo "╠══════════════════════════════════════════════════════╣"
        echo "║  TRAFFIC                                             ║"
        echo "╠══════════════════════════════════════════════════════╣"

        if is_running; then
            local conns=$(curl -s --connect-timeout 2 "$CLASH/connections" 2>/dev/null)
            local traffic=$(curl -s --connect-timeout 2 "$CLASH/traffic" 2>/dev/null)

            if [ -n "$conns" ]; then
                python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    up=d.get('uploadTotal',0)
    dn=d.get('downloadTotal',0)
    n=len(d.get('connections',[]))
    def fmt(b):
        if b>=1073741824: return f'{b/1073741824:.2f} GB'
        if b>=1048576: return f'{b/1048576:.1f} MB'
        if b>=1024: return f'{b/1024:.0f} KB'
        return f'{b} B'
    print(f'║  \u2191 Upload:   {fmt(up):>12s}                          ║')
    print(f'║  \u2193 Download: {fmt(dn):>12s}                          ║')
    print(f'║  Connections: {n} active{\" \"*(32-len(str(n)))}║')
except: pass
" <<< "$conns"

                if [ -n "$traffic" ]; then
                    echo "╠══════════════════════════════════════════════════════╣"
                    echo "║  PROXY STATS                                        ║"
                    echo "╠══════════════════════════════════════════════════════╣"
                    python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    for name in ['reality-vps','reality-vds','direct']:
        if name in d:
            s=d[name]
            up=s.get('upload',0)
            dn=s.get('download',0)
            def fmt(b):
                if b>=1073741824: return f'{b/1073741824:.2f} GB'
                if b>=1048576: return f'{b/1048576:.1f} MB'
                if b>=1024: return f'{b/1024:.0f} KB'
                return f'{b} B'
            print(f'║  {name:15s}  \u2191 {fmt(up):>10s}  \u2193 {fmt(dn):>10s}       ║')
except: pass
" <<< "$traffic"
                fi
            else
                echo "║  (Clash API unreachable)                             ║"
            fi
        else
            echo "║  (sing-box not running)                              ║"
        fi

        echo "╠══════════════════════════════════════════════════════╣"
        printf "║  Updated: %-42s ║\n" "$now"
        echo "║  [1] START  [2] STOP  [Q] EXIT                      ║"
        echo "╚══════════════════════════════════════════════════════╝"

        # Wait for input with timeout
        read -t $INTERVAL -n 1 -s key 2>/dev/null
        case "$key" in
            1) start_singbox; sleep 1 ;;
            2) stop_singbox; sleep 1 ;;
            q|Q) stop_singbox; exit 0 ;;
        esac
    done
}

case "${1:-}" in
    start)  start_singbox; echo "[*] Starting dashboard..."; sleep 1; dashboard ;;
    stop)   stop_singbox ;;
    status)
        if is_running; then
            echo "sing-box: RUNNING (PID $(pgrep -f "sing-box run -c $DIR"))"
            echo -n "  Exit IP: "; curl -4 -s --connect-timeout 3 --socks5 127.0.0.1:1080 https://ifconfig.me 2>/dev/null || echo "?"
        else
            echo "sing-box: STOPPED"
        fi
        ;;
    *)
        if is_running; then echo "[*] sing-box already running, attaching..."; dashboard
        else echo "Usage: $0 {start|stop|status}"; fi
        ;;
esac
