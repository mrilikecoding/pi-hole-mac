#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load config
if [[ ! -f "$SCRIPT_DIR/config.sh" ]]; then
    echo "Error: config.sh not found. Copy config.example.sh to config.sh and edit it."
    exit 1
fi
source "$SCRIPT_DIR/config.sh"

echo "==> Installing dependencies..."
if ! command -v brew &> /dev/null; then
    echo "Error: Homebrew is required. Install from https://brew.sh"
    exit 1
fi

brew install colima docker docker-compose socat

echo "==> Starting Colima..."
colima start --cpu "$COLIMA_CPUS" --memory "$COLIMA_MEMORY" --network-address

echo "==> Disabling Colima's built-in dnsmasq..."
colima ssh -- sudo pkill dnsmasq || true
colima ssh -- sudo rc-update del dnsmasq default 2>/dev/null || true

echo "==> Getting network addresses..."
COLIMA_IP=$(colima list -j | grep -o '"address":"[^"]*"' | cut -d'"' -f4)
if [[ -z "$COLIMA_IP" ]]; then
    echo "Error: Could not determine Colima VM IP"
    exit 1
fi

if ! command -v tailscale &> /dev/null; then
    echo "Error: Tailscale is required. Install from https://tailscale.com/download"
    exit 1
fi

TAILSCALE_IP=$(tailscale ip -4)
if [[ -z "$TAILSCALE_IP" ]]; then
    echo "Error: Could not determine Tailscale IP. Is Tailscale running?"
    exit 1
fi

echo "    Colima VM IP: $COLIMA_IP"
echo "    Tailscale IP: $TAILSCALE_IP"

# Save IPs for other scripts
cat > "$SCRIPT_DIR/.env" << ENVFILE
COLIMA_IP=$COLIMA_IP
TAILSCALE_IP=$TAILSCALE_IP
ENVFILE

echo "==> Creating Pi-hole config directory..."
mkdir -p ~/pihole/etc-pihole ~/pihole/etc-dnsmasq.d

echo "==> Starting Pi-hole container..."
docker rm -f pihole 2>/dev/null || true
docker run -d \
  --name pihole \
  --network=host \
  -e TZ="$PIHOLE_TIMEZONE" \
  -e WEBPASSWORD="$PIHOLE_PASSWORD" \
  -e PIHOLE_DNS_="$PIHOLE_UPSTREAM_DNS" \
  --dns=1.1.1.1 \
  -v ~/pihole/etc-pihole:/etc/pihole \
  -v ~/pihole/etc-dnsmasq.d:/etc/dnsmasq.d \
  --restart=unless-stopped \
  pihole/pihole:latest

echo "==> Waiting for Pi-hole to start..."
sleep 10

echo "==> Verifying Pi-hole is responding..."
if ! docker exec pihole dig @127.0.0.1 google.com +short &>/dev/null; then
    echo "Warning: Pi-hole may not be ready yet. Check 'docker logs pihole'"
fi

echo "==> Creating Colima LaunchAgent..."
mkdir -p ~/Library/LaunchAgents
cat > ~/Library/LaunchAgents/com.colima.start.plist << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"\>
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.colima.start</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/colima</string>
        <string>start</string>
        <string>--network-address</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/colima.out.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/colima.err.log</string>
</dict>
</plist>
PLIST

echo "==> Creating DNS forwarder LaunchDaemon..."
sudo tee /Library/LaunchDaemons/com.pihole.dns.plist > /dev/null << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"\>
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.pihole.dns</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/socat</string>
        <string>UDP-RECVFROM:53,bind=${TAILSCALE_IP},fork,reuseaddr</string>
        <string>UDP-SENDTO:${COLIMA_IP}:53</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> Creating dashboard forwarder LaunchDaemon..."
sudo tee /Library/LaunchDaemons/com.pihole.forward.plist > /dev/null << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"\>
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.pihole.forward</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/socat</string>
        <string>TCP-LISTEN:${DASHBOARD_PORT},fork,reuseaddr</string>
        <string>TCP:${COLIMA_IP}:80</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> Loading LaunchDaemons..."
sudo launchctl unload /Library/LaunchDaemons/com.pihole.dns.plist 2>/dev/null || true
sudo launchctl unload /Library/LaunchDaemons/com.pihole.forward.plist 2>/dev/null || true
sudo launchctl load /Library/LaunchDaemons/com.pihole.dns.plist
sudo launchctl load /Library/LaunchDaemons/com.pihole.forward.plist

echo "==> Configuring power management for headless operation..."
sudo pmset -a sleep 0 disksleep 0 displaysleep 0 autorestart 1

echo ""
echo "==> Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Go to https://login.tailscale.com/admin/dns"
echo "  2. Add nameserver: $TAILSCALE_IP"
echo "  3. Enable 'Override DNS servers'"
echo "  4. (Optional) Enable 'Use with exit node' if you use this machine as an exit node"
echo ""
echo "Dashboard: http://<tailscale-hostname>:${DASHBOARD_PORT}/admin"
echo "Password:  $PIHOLE_PASSWORD"
