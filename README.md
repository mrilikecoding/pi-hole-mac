# Pi-hole on Mac Mini Setup

## Architecture
- Pi-hole runs in Docker via Colima VM at 192.168.64.2
- socat forwards from Mac's Tailscale IP (100.92.166.102) to the VM
- Tailscale DNS configured to use 100.92.166.102

## Components
- Colima: manages Docker VM
- Pi-hole: Docker container with --restart=unless-stopped
- socat: forwards DNS (UDP 53) and dashboard (TCP 8053)

## Files
- ~/Library/LaunchAgents/com.colima.start.plist
- /Library/LaunchDaemons/com.pihole.forward.plist
- /Library/LaunchDaemons/com.pihole.dns.plist
- ~/pihole/etc-pihole (Pi-hole config)
- ~/pihole/etc-dnsmasq.d (dnsmasq config)

## Manual recovery if needed
colima start --network-address
colima ssh -- sudo pkill dnsmasq
docker start pihole
sudo launchctl load /Library/LaunchDaemons/com.pihole.dns.plist
sudo launchctl load /Library/LaunchDaemons/com.pihole.forward.plist
