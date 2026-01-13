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

echo "==> Permanently disabling Colima's built-in dnsmasq..."
colima ssh -- sudo pkill dnsmasq || true
colima ssh -- sudo rm -f /etc/init.d/dnsmasq
colima ssh -- sudo rm -f /etc/runlevels/default/dnsmasq 2>/dev/null || true

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

echo "==> Creating DNS forwarder LaunchDaemon..."
sudo tee /Library/LaunchDaemons/com.pihole.dns.plist > /dev/null << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
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
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
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

echo "==> Creating startup script..."
sudo tee /usr/local/bin/pihole-startup.sh > /dev/null << 'STARTUP'
#!/bin/bash
# Startup script for Pi-hole on macOS
# Run by LaunchDaemon at boot

LOG="/tmp/pihole-startup.log"
exec > "$LOG" 2>&1

# Set PATH to include Homebrew (Intel and Apple Silicon paths)
export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

echo "$(date): Starting Pi-hole startup script"

# Wait for network
echo "$(date): Waiting for network..."
while ! ping -c 1 1.1.1.1 &>/dev/null; do
    sleep 5
done
echo "$(date): Network is up"

# Find the user who owns the colima config
CONSOLE_USER="$(stat -f %Su /Users/*/.colima 2>/dev/null | head -1)"

if [[ -z "$CONSOLE_USER" ]]; then
    echo "$(date): ERROR - Could not determine user"
    exit 1
fi

echo "$(date): Running as user: $CONSOLE_USER"

# Start Colima as the user
echo "$(date): Starting Colima..."
sudo -u "$CONSOLE_USER" /usr/local/bin/colima start --network-address

# Wait for Colima to be ready
echo "$(date): Waiting for Colima..."
sleep 10

# Kill dnsmasq inside the VM
echo "$(date): Killing dnsmasq..."
sudo -u "$CONSOLE_USER" /usr/local/bin/colima ssh -- sudo pkill dnsmasq || true

# Start Pi-hole container
echo "$(date): Starting Pi-hole container..."
sudo -u "$CONSOLE_USER" /usr/local/bin/docker restart pihole

# Wait for Pi-hole to be ready
sleep 5

# Restart the socat forwarders
echo "$(date): Restarting socat forwarders..."
launchctl kickstart -k system/com.pihole.dns || true
launchctl kickstart -k system/com.pihole.forward || true

echo "$(date): Startup complete"
STARTUP

sudo chmod +x /usr/local/bin/pihole-startup.sh

echo "==> Creating boot LaunchDaemon..."
sudo tee /Library/LaunchDaemons/com.pihole.startup.plist > /dev/null << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.pihole.startup</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/pihole-startup.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/pihole-startup.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/pihole-startup.log</string>
</dict>
</plist>
PLIST

sudo launchctl load /Library/LaunchDaemons/com.pihole.startup.plist

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
echo "  5. Add a fallback DNS (e.g. 1.1.1.1) so you don't lose access if Pi-hole is down"
echo ""
echo "Dashboard: http://<tailscale-hostname>:${DASHBOARD_PORT}/admin"
echo "Password:  $PIHOLE_PASSWORD"
