#!/bin/bash
# Copyright (c) 2026 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/linux-server-reboot-management
#
# Version: 1.0.0
#
# Features:
# - JSON snapshots with system state (services, Docker, network, storage)
# - Robust JSON escaping for special characters
# - Root privilege check and restrictive file permissions
# - Extension API for custom metrics
#
# System Snapshot Tool (Optional) - requires customization
# Generic system snapshot tool with extension API for custom metrics.
# Captures: System info, services, Docker containers, network, storage.
# Usage:
#   ./system-snapshot.sh [pre-reboot|post-reboot]
#
# Extension API:
#   Source this script and implement collect_custom_metrics() function
#   to add device-specific metrics. See examples/ directory.
#
# Environment Variables:
#   SNAPSHOT_DIR    Output directory (default: /var/log/snapshots)
#   ENABLE_EXTENSIONS  Enable custom metrics collection (default: false)
#
# Output:
#   JSON file: $SNAPSHOT_DIR/{pre|post}-reboot-YYYYMMDD-HHMMSS.json
#

set -uo pipefail

# ============================================================================
# SECURITY CHECKS
# ============================================================================

# Root check (script may need root for docker, systemctl commands)
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "ERROR: This script should be run as root for complete metrics" >&2
    echo "Usage: sudo $0 [pre-reboot|post-reboot]" >&2
    exit 1
fi

# Set restrictive umask (snapshots may contain sensitive info: IPs, routes, services)
umask 077

# ============================================================================
# CONFIGURATION
# ============================================================================

SNAPSHOT_DIR="${SNAPSHOT_DIR:-/var/log/snapshots}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SNAPSHOT_TYPE="${1:-pre-reboot}"

# Validate SNAPSHOT_TYPE (prevent arbitrary filenames)
case "$SNAPSHOT_TYPE" in
    pre-reboot|post-reboot)
        # Valid snapshot type
        ;;
    *)
        echo "ERROR: Invalid snapshot type '$SNAPSHOT_TYPE'" >&2
        echo "Usage: $0 [pre-reboot|post-reboot]" >&2
        exit 1
        ;;
esac

OUTPUT_FILE="$SNAPSHOT_DIR/${SNAPSHOT_TYPE}-${TIMESTAMP}.json"
ENABLE_EXTENSIONS="${ENABLE_EXTENSIONS:-false}"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# ============================================================================
# LOGGING
# ============================================================================

log() {
    local level=$1
    shift
    local message="$*"

    case "$level" in
        INFO)
            printf "%s[INFO]%s %s\n" "$GREEN" "$NC" "$message"
            ;;
        WARN)
            printf "%s[WARN]%s %s\n" "$YELLOW" "$NC" "$message"
            ;;
        ERROR)
            printf "%s[ERROR]%s %s\n" "$RED" "$NC" "$message" >&2
            ;;
    esac
}

# ============================================================================
# JSON BUFFER
# ============================================================================

# Write-buffer pattern: Accumulate all JSON in memory, write once at end
BUFFER=""

append_buffer() {
    BUFFER="${BUFFER}${1}"$'\n'
    return 0
}

# Helper function to escape JSON strings (handles quotes, newlines, tabs, backslashes)
json_escape() {
    local s=${1-}
    # Escape backslashes first (must be first!)
    s=${s//\\/\\\\}
    # Escape double quotes
    s=${s//\"/\\\"}
    # Escape newlines
    s=${s//$'\n'/\\n}
    # Escape carriage returns
    s=${s//$'\r'/\\r}
    # Escape tabs
    s=${s//$'\t'/\\t}
    printf '%s' "$s"
}

# ============================================================================
# CORE METRICS COLLECTION
# ============================================================================

collect_system_info() {
    log INFO "Collecting system information..."

    local kernel
    local os_release
    local uptime_seconds
    local load_avg
    local mem_total
    local mem_free
    local disk_usage

    kernel=$(uname -r)
    os_release=$(grep "^PRETTY_NAME=" /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "Unknown")
    uptime_seconds=$(awk '{print $1}' /proc/uptime 2>/dev/null || echo "0")
    load_avg=$(awk '{print $1", "$2", "$3}' /proc/loadavg 2>/dev/null || echo "0, 0, 0")
    mem_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo "0")
    mem_free=$(awk '/MemFree/ {print $2}' /proc/meminfo 2>/dev/null || echo "0")
    disk_usage=$(df -h / 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%' || echo "0")

    append_buffer '  "system": {'
    append_buffer "    \"kernel\": \"$(json_escape "$kernel")\","
    append_buffer "    \"os_release\": \"$(json_escape "$os_release")\","
    append_buffer "    \"uptime_seconds\": $uptime_seconds,"
    append_buffer "    \"load_average\": [$load_avg],"
    append_buffer "    \"memory_total_kb\": $mem_total,"
    append_buffer "    \"memory_free_kb\": $mem_free,"
    append_buffer "    \"disk_usage_percent\": $disk_usage"
    append_buffer '  },'
}

collect_services() {
    log INFO "Collecting systemd services..."

    append_buffer '  "services": {'

    # Running services (FIRST-Flag pattern for proper comma handling)
    append_buffer '    "running": ['
    local first=true
    while IFS= read -r svc; do
        [[ -z "$svc" ]] && continue
        if $first; then
            append_buffer "      \"$(json_escape "$svc")\""
            first=false
        else
            append_buffer "      ,\"$(json_escape "$svc")\""
        fi
    done < <(systemctl list-units --type=service --state=running --no-pager --no-legend 2>/dev/null | awk '{print $1}' || true)
    append_buffer '    ],'

    # Failed services (FIRST-Flag pattern)
    # Note: systemctl failed output has "●" as first column, so use $2 if $1 is "●"
    append_buffer '    "failed": ['
    first=true
    while IFS= read -r svc; do
        [[ -z "$svc" ]] && continue
        [[ "$svc" == "●" ]] && continue  # Skip bare "●" artifacts
        if $first; then
            append_buffer "      \"$(json_escape "$svc")\""
            first=false
        else
            append_buffer "      ,\"$(json_escape "$svc")\""
        fi
    done < <(systemctl list-units --type=service --state=failed --no-pager --no-legend 2>/dev/null | awk '{print ($1 == "●" ? $2 : $1)}' || true)
    append_buffer '    ],'

    # Service counts
    local running_count failed_count
    running_count=$(systemctl list-units --type=service --state=running --no-pager --no-legend 2>/dev/null | wc -l || echo "0")
    failed_count=$(systemctl list-units --type=service --state=failed --no-pager --no-legend 2>/dev/null | wc -l || echo "0")

    append_buffer "    \"running_count\": $running_count,"
    append_buffer "    \"failed_count\": $failed_count"
    append_buffer '  },'
}

collect_docker() {
    log INFO "Collecting Docker container status..."

    append_buffer '  "docker": {'

    if systemctl is-active --quiet docker 2>/dev/null; then
        append_buffer '    "service_active": true,'
        append_buffer '    "containers": ['

        # Tab-separated output for robust escaping (FIRST-Flag pattern)
        local first=true
        while IFS=$'\t' read -r name status state; do
            [[ -z "$name" ]] && continue
            if $first; then
                append_buffer "      {\"name\":\"$(json_escape "$name")\",\"status\":\"$(json_escape "$status")\",\"state\":\"$(json_escape "$state")\"}"
                first=false
            else
                append_buffer "      ,{\"name\":\"$(json_escape "$name")\",\"status\":\"$(json_escape "$status")\",\"state\":\"$(json_escape "$state")\"}"
            fi
        done < <(docker ps -a --format '{{.Names}}\t{{.Status}}\t{{.State}}' 2>/dev/null || true)

        append_buffer '    ],'

        local running_count total_count
        running_count=$(docker ps -q 2>/dev/null | wc -l || echo "0")
        total_count=$(docker ps -a -q 2>/dev/null | wc -l || echo "0")

        append_buffer "    \"running_count\": $running_count,"
        append_buffer "    \"total_count\": $total_count"
    else
        append_buffer '    "service_active": false,'
        append_buffer '    "containers": [],'
        append_buffer '    "running_count": 0,'
        append_buffer '    "total_count": 0'
    fi

    append_buffer '  },'
}

collect_network() {
    log INFO "Collecting network information..."

    append_buffer '  "network": {'

    # Interfaces (use ip -j for native JSON)
    append_buffer '    "interfaces": '
    local interfaces
    # ip -j outputs valid JSON already; validate but don't require --compact (Python 3.9+)
    interfaces=$(ip -j addr show 2>/dev/null | python3 -m json.tool 2>/dev/null || ip -j addr show 2>/dev/null || echo "[]")
    append_buffer "    $interfaces,"

    # Routes (use ip -j for native JSON)
    append_buffer '    "routes": '
    local routes
    # ip -j outputs valid JSON already; validate but don't require --compact (Python 3.9+)
    routes=$(ip -j route show 2>/dev/null | python3 -m json.tool 2>/dev/null || ip -j route show 2>/dev/null || echo "[]")
    append_buffer "    $routes,"

    # Gateway (escape for safety)
    local gateway
    gateway=$(ip route show default 2>/dev/null | awk '/default/ {print $3; exit}' || echo "none")
    append_buffer "    \"default_gateway\": \"$(json_escape "$gateway")\""

    append_buffer '  },'
}

collect_storage() {
    log INFO "Collecting storage information..."

    append_buffer '  "storage": {'

    # Mounts (FIRST-Flag pattern with proper escaping)
    append_buffer '    "mounts": ['
    local first=true
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # Parse df output fields
        local fs size used avail pct mount
        read -r fs size used avail pct mount <<< "$line"
        [[ -z "$fs" ]] && continue
        if $first; then
            append_buffer "      {\"filesystem\":\"$(json_escape "$fs")\",\"size\":\"$(json_escape "$size")\",\"used\":\"$(json_escape "$used")\",\"available\":\"$(json_escape "$avail")\",\"use_percent\":\"$(json_escape "$pct")\",\"mount\":\"$(json_escape "$mount")\"}"
            first=false
        else
            append_buffer "      ,{\"filesystem\":\"$(json_escape "$fs")\",\"size\":\"$(json_escape "$size")\",\"used\":\"$(json_escape "$used")\",\"available\":\"$(json_escape "$avail")\",\"use_percent\":\"$(json_escape "$pct")\",\"mount\":\"$(json_escape "$mount")\"}"
        fi
    done < <(df -h 2>/dev/null | tail -n +2 || true)
    append_buffer '    ]'

    append_buffer '  }'
}

# ============================================================================
# EXTENSION API
# ============================================================================

# Default implementation (no-op)
collect_custom_metrics() {
    return 0
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    log INFO "=== System Snapshot Tool ==="
    log INFO "Type: $SNAPSHOT_TYPE"
    log INFO "Output: $OUTPUT_FILE"
    echo "----------------------------------------"

    # Ensure snapshot directory exists
    mkdir -p "$SNAPSHOT_DIR" || {
        log ERROR "Failed to create snapshot directory: $SNAPSHOT_DIR"
        exit 1
    }

    # Start JSON structure
    append_buffer '{'
    append_buffer "  \"timestamp\": \"$TIMESTAMP\","
    append_buffer "  \"type\": \"$SNAPSHOT_TYPE\","
    append_buffer "  \"hostname\": \"$(json_escape "$(hostname)")\","

    # Collect core metrics
    collect_system_info
    collect_services
    collect_docker
    collect_network
    collect_storage

    # Collect custom metrics if enabled
    if [[ "$ENABLE_EXTENSIONS" == "true" ]]; then
        log INFO "Collecting custom metrics..."
        # Remove trailing newline and closing brace from storage section
        BUFFER="${BUFFER%$'\n'}"  # Remove trailing newline
        BUFFER="${BUFFER%  }}"    # Remove `  }` (storage close)
        # Add comma after storage section for JSON validity
        append_buffer '  },'

        # Save buffer length before extension call
        local buffer_len_before=${#BUFFER}
        collect_custom_metrics || log WARN "Custom metrics collection failed"

        # If no content was added by extensions, remove trailing comma to keep JSON valid
        if [[ ${#BUFFER} -eq $buffer_len_before ]]; then
            BUFFER="${BUFFER%$'\n'}"  # Remove trailing newline
            BUFFER="${BUFFER%,}"      # Remove trailing comma: `  },` -> `  }`
            BUFFER="${BUFFER}"$'\n'   # Restore newline
        fi
    fi

    # Close JSON structure
    append_buffer '}'

    # Write to file
    printf "%s" "$BUFFER" > "$OUTPUT_FILE" || {
        log ERROR "Failed to write snapshot to $OUTPUT_FILE"
        exit 1
    }

    log INFO "Snapshot saved: $OUTPUT_FILE"

    # Validate JSON
    if command -v python3 >/dev/null 2>&1; then
        if python3 -m json.tool "$OUTPUT_FILE" >/dev/null 2>&1; then
            log INFO "JSON validation: PASSED"
        else
            log ERROR "JSON validation: FAILED"
            exit 1
        fi
    fi

    log INFO "Snapshot complete!"
}

# Run main only if not sourced (allows extension scripts to source this file)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
