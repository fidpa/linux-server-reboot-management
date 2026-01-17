#!/bin/bash
# Copyright (c) 2026 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/linux-server-reboot-management

# System Snapshot Extensions Example (Optional) - requires customization
# Example of device-specific metrics collection.
# This example shows metrics collected from a production ARM-based gateway
# running Debian/Raspberry Pi OS with custom network monitoring.
#
# Usage:
#   ENABLE_EXTENSIONS=true ./snapshot-extensions-example.sh [pre-reboot|post-reboot]

# Source the core snapshot tool
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/system-snapshot.sh"

# ============================================================================
# CUSTOM METRICS COLLECTION
# ============================================================================

# Override the default collect_custom_metrics function
collect_custom_metrics() {
    log INFO "Collecting custom device-specific metrics..."

    append_buffer '  "custom": {'

    # Example 1: Hardware temperature (Raspberry Pi specific)
    if command -v vcgencmd >/dev/null 2>&1; then
        local cpu_temp
        cpu_temp=$(vcgencmd measure_temp 2>/dev/null | cut -d= -f2 | cut -d\' -f1 || echo "0")
        append_buffer "    \"cpu_temp_celsius\": $cpu_temp,"

        local throttle_status
        throttle_status=$(vcgencmd get_throttled 2>/dev/null | cut -d= -f2 || echo "0x0")
        append_buffer "    \"throttle_status\": \"$throttle_status\","
    fi

    # Example 2: Network interface statistics
    append_buffer '    "network_stats": {'
    local interface="eth0"
    if [[ -d "/sys/class/net/$interface" ]]; then
        local rx_bytes tx_bytes
        rx_bytes=$(cat "/sys/class/net/$interface/statistics/rx_bytes" 2>/dev/null || echo "0")
        tx_bytes=$(cat "/sys/class/net/$interface/statistics/tx_bytes" 2>/dev/null || echo "0")

        append_buffer "      \"$interface\": {"
        append_buffer "        \"rx_bytes\": $rx_bytes,"
        append_buffer "        \"tx_bytes\": $tx_bytes"
        append_buffer "      }"
    fi
    append_buffer '    },'

    # Example 3: Custom service health checks
    append_buffer '    "custom_services": {'
    local service_names=("ssh" "NetworkManager" "docker")
    local first=true

    for service in "${service_names[@]}"; do
        if systemctl list-units --full -all | grep -q "^${service}.service"; then
            if [[ "$first" == "false" ]]; then
                append_buffer ","
            fi
            first=false

            local status
            if systemctl is-active --quiet "$service"; then
                status="active"
            else
                status="inactive"
            fi

            append_buffer "      \"$service\": {"
            append_buffer "        \"status\": \"$status\","
            append_buffer "        \"enabled\": $(systemctl is-enabled "$service" 2>/dev/null | grep -q "enabled" && echo "true" || echo "false")"
            append_buffer "      }"
        fi
    done

    append_buffer '    },'

    # Example 4: WireGuard VPN stats (if available)
    if command -v wg >/dev/null 2>&1; then
        append_buffer '    "wireguard": {'

        local wg_interfaces
        wg_interfaces=$(wg show interfaces 2>/dev/null || echo "")

        if [[ -n "$wg_interfaces" ]]; then
            append_buffer "      \"interfaces\": \"$wg_interfaces\","

            local peer_count
            peer_count=$(wg show all peers 2>/dev/null | wc -l || echo "0")
            append_buffer "      \"peer_count\": $peer_count"
        else
            append_buffer "      \"interfaces\": \"\","
            append_buffer "      \"peer_count\": 0"
        fi

        append_buffer '    },'
    fi

    # Example 5: Disk I/O stats
    if [[ -f /proc/diskstats ]]; then
        append_buffer '    "disk_io": {'

        local device="sda"
        if grep -q "^[[:space:]]*[0-9]*[[:space:]]*[0-9]*[[:space:]]*${device}[[:space:]]" /proc/diskstats; then
            local read_ios write_ios
            read_ios=$(awk -v dev="$device" '$3 == dev {print $4}' /proc/diskstats || echo "0")
            write_ios=$(awk -v dev="$device" '$3 == dev {print $8}' /proc/diskstats || echo "0")

            append_buffer "      \"$device\": {"
            append_buffer "        \"read_ios\": $read_ios,"
            append_buffer "        \"write_ios\": $write_ios"
            append_buffer "      }"
        fi

        append_buffer '    },'
    fi

    # Example 6: Custom application metrics (if available)
    append_buffer '    "application_metrics": {'
    append_buffer '      "monitoring_enabled": true,'

    # Check if Prometheus node_exporter is running
    local exporter_running
    if systemctl is-active --quiet node_exporter 2>/dev/null; then
        exporter_running="true"
    else
        exporter_running="false"
    fi

    append_buffer "      \"prometheus_exporter\": $exporter_running"
    append_buffer '    }'

    append_buffer '  }'
}

# Enable extensions by default for this example
ENABLE_EXTENSIONS=true

# Run main (from sourced script)
main "$@"
