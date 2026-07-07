#!/bin/bash
# sing-box portable manager (Linux)
# Usage: ./sing.sh {start|stop|restart|status|install|uninstall|add-bypass|del-bypass}

DIR="$(cd "$(dirname "$0")" && pwd)"
SERVICE="sing-box.service"
UNIT_FILE="/etc/systemd/system/sing-box.service"
TUN_IF="sing-tun"
LOG="$DIR/sing-box.log"
BYPASS_IPS=("46.8.233.202/32" "31.77.77.47/32" "94.126.153.10/32")
export ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true
BYPASS_PRIO=8998

add_bypass_routes() {
    local gw dev
    gw=$(ip route show default | awk '{print $3}' | head -1)
    dev=$(ip route show default | awk '{print $5}' | head -1)
    [ -z "$gw" ] && { echo "[!] no default gateway"; return 1; }
    for ip in "${BYPASS_IPS[@]}"; do
        sudo ip route replace "$ip" via "$gw" dev "$dev" 2>/dev/null
        sudo ip rule add to "$ip" table main priority $BYPASS_PRIO 2>/dev/null || true
    done
    echo "[+] bypass routes set (via $gw dev $dev)"
}

del_bypass_routes() {
    for ip in "${BYPASS_IPS[@]}"; do
        sudo ip route del "$ip" 2>/dev/null || true
    done
    while ip rule show | grep -q "^${BYPASS_PRIO}:"; do
        sudo ip rule del priority $BYPASS_PRIO 2>/dev/null || break
    done
    echo "[+] bypass routes cleaned"
}

start() {
    echo "[*] Starting sing-box..."
    [ ! -f "$DIR/sing-box" ] && { echo "[!] sing-box binary not found"; exit 1; }
    [ ! -f "$DIR/config.json" ] && { echo "[!] config.json not found"; exit 1; }

    # Kill any existing instance
    pkill -f "sing-box run -c $DIR" 2>/dev/null
    sleep 1

    # Clean stale TUN interfaces
    for iface in sing-tun0 sing-tun1 sing-tun; do
        ip link show "$iface" &>/dev/null && ip link delete "$iface" 2>/dev/null
    done

    # Add bypass routes before starting
    add_bypass_routes || echo "[!] bypass routes failed, continuing anyway"

    # Start sing-box
    nohup "$DIR/sing-box" run -c "$DIR/config.json" > "$LOG" 2>&1 &
    local pid=$!
    echo "[*] PID: $pid"

    # Wait for TUN and SOCKS to come up
    for i in $(seq 1 10); do
        if ip link show "$TUN_IF" 2>/dev/null | grep -q UP && \
           ss -tlnp | grep -q ":1080 "; then
            echo "[+] sing-tun UP, SOCKS5 on :1080"
            break
        fi
        sleep 1
    done

    if ! ip link show "$TUN_IF" 2>/dev/null | grep -q UP; then
        echo "[!] TUN did not come up. Check logs: $LOG"
        tail -5 "$LOG" 2>/dev/null
        exit 1
    fi

    # Disable systemd-resolved TUN hijack
    resolvectl dns "$TUN_IF" '' 2>/dev/null || true
    resolvectl default-route "$TUN_IF" false 2>/dev/null || true

    sleep 2
    echo -n "[+] Exit IP: "
    curl -4 -s --connect-timeout 5 --socks5 127.0.0.1:1080 https://ifconfig.me 2>/dev/null || echo "(connecting...)"
    echo ""
    echo "[+] Clash API: http://127.0.0.1:9090"
}

stop() {
    echo "[*] Stopping sing-box..."
    pkill -f "sing-box run -c $DIR" 2>/dev/null
    sleep 1
    pkill -9 -f "sing-box run -c $DIR" 2>/dev/null
    # Clean TUN
    for iface in sing-tun0 sing-tun1 sing-tun; do
        ip link show "$iface" &>/dev/null && ip link delete "$iface" 2>/dev/null && echo "  removed $iface"
    done
    del_bypass_routes
    echo "[+] Stopped"
}

restart() {
    stop
    sleep 1
    start
}

status() {
    local pid
    pid=$(pgrep -f "sing-box run -c $DIR")
    if [ -n "$pid" ]; then
        echo "sing-box: RUNNING (PID $pid)"
        echo -n "  Exit IP: "
        curl -4 -s --connect-timeout 3 --socks5 127.0.0.1:1080 https://ifconfig.me 2>/dev/null || echo "(timeout)"
        echo ""
        echo "  SOCKS5: 127.0.0.1:1080"
        echo "  HTTP:   127.0.0.1:8080"
        echo "  Clash:  127.0.0.1:9090"
        echo -n "  TUN:    "; ip link show "$TUN_IF" 2>/dev/null | grep -q UP && echo "UP" || echo "DOWN"
        echo "  Active: $(curl -s --connect-timeout 2 http://127.0.0.1:9090/proxies/auto 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('now','?'))" 2>/dev/null || echo '?')"
    else
        echo "sing-box: STOPPED"
    fi
}

install() {
    echo "[*] Installing systemd service..."
    [ ! -f "$DIR/sing-box.service" ] && { echo "[!] sing-box.service not found"; exit 1; }
    sudo cp "$DIR/sing-box.service" "$UNIT_FILE"
    sudo sed -i "s|/home/vladimir/vpn|$DIR|g" "$UNIT_FILE"
    sudo systemctl daemon-reload
    echo "[+] Installed. Use: systemctl start sing-box"
}

uninstall() {
    echo "[*] Uninstalling..."
    sudo systemctl disable --now "$SERVICE" 2>/dev/null
    sudo rm -f "$UNIT_FILE"
    sudo systemctl daemon-reload
    del_bypass_routes
    echo "[+] Uninstalled"
}

case "${1:-}" in
    start)      start ;;
    stop)       stop ;;
    restart)    restart ;;
    status)     status ;;
    install)    install ;;
    uninstall)  uninstall ;;
    add-bypass) add_bypass_routes ;;
    del-bypass) del_bypass_routes ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|install|uninstall|add-bypass|del-bypass}"
        exit 1
        ;;
esac
