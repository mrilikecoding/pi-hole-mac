# Pi-hole on macOS with Tailscale

Run Pi-hole on a Mac (Intel or Apple Silicon) as a network-wide ad blocker accessible via Tailscale.

## Architecture
```
Tailscale devices → Mac (socat) → Colima VM → Pi-hole container
                    100.x.x.x     192.168.64.x
```

Pi-hole runs in a Docker container inside a Colima VM. Since the VM uses a private bridge network, `socat` forwards DNS queries from the Tailscale interface into the VM.

## Requirements

- macOS
- [Homebrew](https://brew.sh)
- [Tailscale](https://tailscale.com/download) installed and connected

## Installation

1. Clone this repo:
```bash
   git clone https://github.com/mrilikecoding/pi-hole-mac.git
   cd pi-hole-mac
```

2. Copy and edit the config:
```bash
   cp config.example.sh config.sh
   nano config.sh  # Set your password, timezone, etc.
```

3. Run the installer:
```bash
   ./install.sh
```

4. Configure Tailscale DNS:
   - Go to https://login.tailscale.com/admin/dns
   - Click "Add nameserver" → "Custom"
   - Enter your Mac's Tailscale IP (shown at end of install)
   - Enable "Override DNS servers"
   - If using this Mac as an exit node, enable "Use with exit node"

## Usage

- **Dashboard**: `http://<tailscale-hostname>:8053/admin`
- **Check status**: `docker ps` and `dig @<tailscale-ip> google.com`
- **View logs**: `docker logs pihole`

## Uninstallation
```bash
./uninstall.sh
```

## Troubleshooting

### DNS not working after reboot

The LaunchDaemons may start before Colima is ready. SSH in and run:
```bash
colima start --network-address
colima ssh -- sudo pkill dnsmasq
docker start pihole
sudo launchctl kickstart -k system/com.pihole.dns
sudo launchctl kickstart -k system/com.pihole.forward
```

### Check if services are running
```bash
colima status
docker ps
sudo launchctl list | grep pihole
```

### Port 53 conflict

macOS runs `mDNSResponder` on port 53. The install script binds socat only to the Tailscale IP to avoid conflicts. If you see "address already in use" errors, check:
```bash
sudo lsof -i :53
```

## Files

| File | Purpose |
|------|---------|
| `~/Library/LaunchAgents/com.colima.start.plist` | Starts Colima on login |
| `/Library/LaunchDaemons/com.pihole.dns.plist` | Forwards DNS (UDP 53) |
| `/Library/LaunchDaemons/com.pihole.forward.plist` | Forwards dashboard (TCP 8053) |
| `~/pihole/` | Pi-hole persistent config |

## License

MIT
