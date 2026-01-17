#!/bin/bash
# Copyright (c) 2026 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/linux-server-reboot-management

# Network Gateway Autostart Example
# Demonstrates network foundation pattern for gateway/router systems.
# Pattern: Network → Firewall → NAT → VPN → DNS

set -euo pipefail

LOG_FILE="/var/log/autostart-network.log"
BOOT_START_TIME=$(date +%s)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

start_service() {
    local service=$1
    local friendly_name=${2:-$service}

    log "Starting $friendly_name..."
    if systemctl start "$service"; then
        log "✓ $friendly_name started"
        return 0
    else
        log "✗ $friendly_name failed"
        return 1
    fi
}

main() {
    log "=== Network Gateway Autostart ==="

    # 1. Wait for NetworkManager
    log "Phase 1: Network Foundation"
    local waited=0
    while ! systemctl is-active --quiet NetworkManager && [ $waited -lt 30 ]; do
        sleep 1
        waited=$((waited + 1))
    done

    if systemctl is-active --quiet NetworkManager; then
        log "✓ NetworkManager active after ${waited}s"
    else
        log "✗ NetworkManager timeout"
        exit 1
    fi

    # Wait for network-online
    systemctl is-active --quiet network-online.target || {
        log "Waiting for network-online.target..."
        sleep 5
    }
    log "✓ Network online"

    # 2. Configure network interfaces
    log "Phase 2: Interface Configuration"

    # Example: Bring up WAN interface
    local wan_iface="eth0"
    if ip link show "$wan_iface" &>/dev/null; then
        ip link set "$wan_iface" up 2>/dev/null || true
        log "✓ WAN interface $wan_iface up"
    fi

    # Example: Bring up LAN interface
    local lan_iface="eth1"
    if ip link show "$lan_iface" &>/dev/null; then
        ip link set "$lan_iface" up 2>/dev/null || true
        log "✓ LAN interface $lan_iface up"
    fi

    # 3. Enable IP forwarding
    log "Phase 3: IP Forwarding"
    if [ "$(cat /proc/sys/net/ipv4/ip_forward)" != "1" ]; then
        echo 1 > /proc/sys/net/ipv4/ip_forward
        log "✓ IP forwarding enabled"
    else
        log "✓ IP forwarding already enabled"
    fi

    # 4. Configure firewall
    log "Phase 4: Firewall Configuration"

    # Example: UFW
    if command -v ufw &>/dev/null; then
        start_service "ufw" "UFW Firewall"
        ufw default deny incoming 2>/dev/null || true
        ufw default allow outgoing 2>/dev/null || true
        log "✓ Firewall policies set"
    fi

    # Example: nftables
    if command -v nft &>/dev/null && [ -f /etc/nftables.conf ]; then
        start_service "nftables" "nftables Firewall"
    fi

    # 5. Configure NAT
    log "Phase 5: NAT Configuration"

    # Example: iptables MASQUERADE for LAN
    if command -v iptables &>/dev/null; then
        local lan_subnet="192.168.1.0/24"

        # Check if rule exists
        if ! iptables -t nat -C POSTROUTING -s "$lan_subnet" -o "$wan_iface" -j MASQUERADE 2>/dev/null; then
            iptables -t nat -A POSTROUTING -s "$lan_subnet" -o "$wan_iface" -j MASQUERADE
            log "✓ NAT rule added for $lan_subnet"
        else
            log "✓ NAT rule already exists"
        fi

        # Save rules
        if command -v iptables-save &>/dev/null; then
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
            log "✓ NAT rules saved"
        fi
    fi

    # 6. Start VPN services
    log "Phase 6: VPN Services"

    # Example: WireGuard
    if systemctl list-unit-files | grep -q "wg-quick@"; then
        start_service "wg-quick@wg0" "WireGuard wg0"
    fi

    # Example: OpenVPN
    if systemctl list-unit-files | grep -q "openvpn@"; then
        start_service "openvpn@server" "OpenVPN Server"
    fi

    # 7. Start DNS services
    log "Phase 7: DNS Services"

    # Example: dnsmasq
    if systemctl list-unit-files | grep -q "dnsmasq"; then
        start_service "dnsmasq" "dnsmasq DNS/DHCP"
    fi

    # Example: bind9
    if systemctl list-unit-files | grep -q "named"; then
        start_service "named" "BIND9 DNS"
    fi

    # 8. Verify gateway functionality
    log "Phase 8: Gateway Verification"

    # Check WAN connectivity
    if ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
        log "✓ WAN connectivity verified (ping 8.8.8.8)"
    else
        log "⚠ WAN connectivity failed"
    fi

    # Check LAN interface IP
    if ip addr show "$lan_iface" 2>/dev/null | grep -q "inet "; then
        local lan_ip
        lan_ip=$(ip -4 addr show "$lan_iface" | grep inet | awk '{print $2}' | head -1)
        log "✓ LAN interface has IP: $lan_ip"
    else
        log "⚠ LAN interface has no IP"
    fi

    # Check NAT rules (only if iptables is available)
    local nat_rules=0
    if command -v iptables &>/dev/null; then
        nat_rules=$(iptables -t nat -L POSTROUTING -n 2>/dev/null | grep -c MASQUERADE || echo 0)
        if [ "$nat_rules" -gt 0 ]; then
            log "✓ NAT rules active ($nat_rules MASQUERADE rules)"
        else
            log "⚠ No NAT rules found"
        fi
    else
        log "ℹ iptables not available, skipping NAT verification"
    fi

    # 9. Start monitoring
    log "Phase 9: Network Monitoring"

    # Example: Interface monitoring timer
    if systemctl list-unit-files | grep -q "interface-monitor.timer"; then
        systemctl start interface-monitor.timer 2>/dev/null && \
            log "✓ Interface monitor started" || \
            log "⚠ Interface monitor failed"
    fi

    # 10. Boot performance
    local boot_time=$(($(date +%s) - BOOT_START_TIME))
    log "=== Network Gateway Boot Complete: ${boot_time}s ==="

    # Prometheus metrics (optional)
    if [[ -d /var/lib/node_exporter/textfile_collector ]]; then
        cat > /var/lib/node_exporter/textfile_collector/gateway-boot.prom <<EOF
# HELP gateway_boot_duration_seconds Gateway boot duration
# TYPE gateway_boot_duration_seconds gauge
gateway_boot_duration_seconds $boot_time
gateway_boot_timestamp $(date +%s)
gateway_wan_up $(ip link show "$wan_iface" 2>/dev/null | grep -q "state UP" && echo 1 || echo 0)
gateway_lan_up $(ip link show "$lan_iface" 2>/dev/null | grep -q "state UP" && echo 1 || echo 0)
gateway_nat_rules $nat_rules
EOF
        log "✓ Metrics exported"
    fi
}

main "$@"
