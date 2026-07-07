#!/bin/bash
SERVICE="sing-box.service"
UNIT_FILE="/etc/systemd/system/sing-box.service"
TUN_IF="sing-tun"
BYPASS_IPS=("46.8.233.202/32" "31.77.77.47/32" "94.126.153.10/32")

add_bypass_routes() {
    local gw dev
    gw=$(ip route show default | awk '{print $3}')
    dev=$(ip route show default | awk '{print $5}')
    [ -z "$gw" ] && { echo "[!] no default gateway"; return 1; }
    for ip in "${BYPASS_IPS[@]}"; do
        sudo ip route replace "$ip" via "$gw" dev "$dev"
        sudo ip rule add to "$ip" table main priority 8998 2>/dev/null || true
    done
}

del_bypass_routes() {
    for ip in "${BYPASS_IPS[@]}"; do
        sudo ip route del "$ip" 2>/dev/null || true
    done
    while ip rule show | grep -q "^8998:"; do
        sudo ip rule del priority 8998 2>/dev/null || break
    done
}

start() {
    echo "[*] Starting sing-box (auto-failover VPS ↔ VDS)..."
    [ ! -f "$UNIT_FILE" ] && { echo "[!] Service unit not found. Run install first."; exit 1; }
    add_bypass_routes || echo "[!] bypass routes not set"
    sudo systemctl enable --now "$SERVICE"
    for i in $(seq 1 10); do
        ip link show "$TUN_IF" 2>/dev/null | grep -q UP && { echo "[+] tun is up"; break; }
        sleep 1
    done
    if ! ip link show "$TUN_IF" 2>/dev/null | grep -q UP; then
        echo "[!] tun did not come up"
        sudo systemctl status "$SERVICE" --no-pager -n 10
        exit 1
    fi
    resolvectl dns "$TUN_IF" '' 2>/dev/null || true
    resolvectl default-route "$TUN_IF" false 2>/dev/null || true
    echo "[+] Started. Checking exit IP..."
    sleep 2
    curl -s --connect-timeout 10 https://ifconfig.me || echo "(still connecting...)"
}

stop() {
    echo "[*] Stopping sing-box..."
    sudo systemctl disable --now "$SERVICE" 2>/dev/null
    sudo killall sing-box 2>/dev/null
    sleep 2
    sudo killall -9 sing-box 2>/dev/null
    while ip link show "$TUN_IF" 2>/dev/null; do sleep 1; done
    del_bypass_routes
    echo "[+] Stopped. Routes cleaned."
}

restart() {
    echo "[*] Restarting sing-box..."
    add_bypass_routes
    sudo systemctl restart "$SERVICE"
}

status() {
    if systemctl is-active --quiet "$SERVICE"; then
        echo "sing-box: RUNNING (systemd)"
        ip link show "$TUN_IF" 2>/dev/null
        echo "--- bypass routes ---"
        for ip in "${BYPASS_IPS[@]}"; do
            ip route show "$ip" 2>/dev/null || echo "  $ip: NOT SET"
        done
        echo -n "Exit IP: "
        curl -s --connect-timeout 3 https://ifconfig.me || echo "(unreachable)"
    else
        echo "sing-box: STOPPED"
        systemctl status "$SERVICE" --no-pager -n 5 2>/dev/null
    fi
}

install() {
    echo "[*] Installing systemd service..."
    [ ! -f "/home/vladimir/vpn/sing-box.service" ] && { echo "[!] sing-box.service not found"; exit 1; }
    sudo cp /home/vladimir/vpn/sing-box.service "$UNIT_FILE"
    sudo systemctl daemon-reload
    echo "[+] Installed."
}

uninstall() {
    echo "[*] Uninstalling systemd service..."
    sudo systemctl disable --now "$SERVICE" 2>/dev/null
    sudo rm -f "$UNIT_FILE"
    sudo systemctl daemon-reload
    del_bypass_routes
    echo "[+] Uninstalled."
}

case "${1:-}" in
    start) start ;;
    stop) stop ;;
    restart) restart ;;
    status) status ;;
    install) install ;;
    uninstall) uninstall ;;
    add-bypass) add_bypass_routes ;;
    del-bypass) del_bypass_routes ;;
    *) echo "Usage: $0 {start|stop|restart|status|install|uninstall|add-bypass|del-bypass}" ;;
esac
