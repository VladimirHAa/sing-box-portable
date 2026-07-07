# sing-box portable client

Portable sing-box with auto-failover VPS (46.8.233.202) ↔ VDS (31.77.77.47).

## Quick start

### Linux
```bash
./sing.sh start     # start with bypass routes
./sing.sh stop      # stop and cleanup
./sing.sh status    # check exit IP and active outbound
./sing.sh restart   # restart
```

### Windows
```
run.bat              # start (auto-detects config-windows.json)
stop.bat             # stop
```

## Modes

| Mode | Interface | Port | Use case |
|------|-----------|------|----------|
| SOCKS5 | `127.0.0.1:1080` | TCP | Browser/app proxy |
| HTTP | `127.0.0.1:8080` | TCP | Browser HTTP proxy |
| TUN | `sing-tun` | — | Full system VPN |
| Clash API | `127.0.0.1:9090` | TCP | Web UI / status |

## Route rules

- Russian domains/IPs (`.ru`, `.su`, geoip-ru) → direct
- VPN server IPs (46.8.233.202, 31.77.77.47, 94.126.153.10) → direct
- Private IPs → direct
- Everything else → auto (VPS or VDS)

## Auto-failover

urltest checks `https://www.gstatic.com/generate_204` every 60s.
If VPS fails, traffic switches to VDS automatically.

## Files

| File | Purpose |
|------|---------|
| `config.json` | Linux config (`auto_route: false`) |
| `config-windows.json` | Windows config (`auto_route: true`) |
| `sing.sh` | Linux manager script |
| `run.bat` | Windows start script |
| `stop.bat` | Windows stop script |
| `sing-box` | Linux binary |
| `sing-box.exe` | Windows binary |
| `geoip-ru.srs` | GeoIP Russia rule set |
| `geosite-ru.srs` | GeoSite Russia rule set |
| `sing-box.service` | systemd service |

## Install as systemd service (Linux)

```bash
./sing.sh install
sudo systemctl enable --now sing-box
sudo systemctl status sing-box
```

## Phone testing

Phone connects to SOCKS5 proxy at `<this-machine-ip>:1080`:
- Android: WiFi settings → Proxy → Manual → `<IP>:1080`
- iOS: Settings → Wi-Fi → Configure Proxy → Manual → `<IP>:1080`
