#!/bin/bash
set -e

echo "==> Stopping and removing Pi-hole container..."
docker rm -f pihole 2>/dev/null || true

echo "==> Unloading LaunchDaemons..."
sudo launchctl unload /Library/LaunchDaemons/com.pihole.dns.plist 2>/dev/null || true
sudo launchctl unload /Library/LaunchDaemons/com.pihole.forward.plist 2>/dev/null || true
launchctl unload ~/Library/LaunchAgents/com.colima.start.plist 2>/dev/null || true

echo "==> Removing LaunchDaemons and LaunchAgents..."
sudo rm -f /Library/LaunchDaemons/com.pihole.dns.plist
sudo rm -f /Library/LaunchDaemons/com.pihole.forward.plist
rm -f ~/Library/LaunchAgents/com.colima.start.plist

echo "==> Stopping Colima..."
colima stop 2>/dev/null || true

echo ""
echo "==> Uninstall complete!"
echo ""
echo "Optional cleanup (run manually if desired):"
echo "  rm -rf ~/pihole          # Remove Pi-hole config"
echo "  colima delete            # Remove Colima VM"
echo "  brew uninstall socat colima docker docker-compose"
echo ""
echo "Don't forget to remove the DNS entry from Tailscale admin:"
echo "  https://login.tailscale.com/admin/dns"
