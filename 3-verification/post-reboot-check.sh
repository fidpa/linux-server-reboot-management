#!/bin/bash
# Copyright (c) 2026 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/linux-server-reboot-management
# Version: 1.0.0

# Post-Reboot Verification Script
# Automated verification script that checks system state after reboot.
# Verifies graceful shutdown hook execution, container restart, health checks,
# and network connectivity.
#
# Usage:
#   ./post-reboot-check.sh [OPTIONS]
#
# Options:
#   --verbose     Enable verbose output
#   --json        Output results in JSON format
#   --help        Show this help message
#
# Exit Codes:
#   0 - All checks passed
#   1 - Graceful shutdown hook didn't run
#   2 - Containers not running
#   3 - Health checks failing
#   4 - Network issues
#
# Environment Variables:
#   LOG_DIR               Directory for reports (default: /var/log)
#   DOCKER_SERVICE_NAME   Name of graceful shutdown service (default: docker-graceful-shutdown)
#

set -uo pipefail  # NO -e: Best Practice 2025

# Configuration
LOG_DIR="${LOG_DIR:-/var/log}"
REPORT_DIR="$LOG_DIR/reboot-reports"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
DOCKER_SERVICE_NAME="${DOCKER_SERVICE_NAME:-docker-graceful-shutdown}"

# Parse command-line arguments
VERBOSE=false
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose)
            VERBOSE=true
            shift
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --help)
            grep '^#' "$0" | grep -v '#!/bin/bash' | sed 's/^# //; s/^#//'
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Colors (disabled in JSON mode)
if [[ "$JSON_OUTPUT" == false ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
fi

# Logging function
log() {
    local level=$1
    shift
    local message="$*"

    if [[ "$JSON_OUTPUT" == false ]]; then
        case "$level" in
            INFO)
                echo -e "${GREEN}[INFO]${NC} $message"
                ;;
            WARN)
                echo -e "${YELLOW}[WARN]${NC} $message"
                ;;
            ERROR)
                echo -e "${RED}[ERROR]${NC} $message"
                ;;
            *)
                echo "$message"
                ;;
        esac
    fi

    # Always log to verbose
    if [[ "$VERBOSE" == true ]]; then
        echo "[$(date)] [$level] $message" >&2
    fi
}

# JSON accumulator
JSON_RESULTS=()

# JSON escape function (handles quotes, newlines, tabs, backslashes)
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

add_json_result() {
    local check_name=$1
    local status=$2
    local message=$3

    # Escape all values for valid JSON
    check_name=$(json_escape "$check_name")
    status=$(json_escape "$status")
    message=$(json_escape "$message")

    JSON_RESULTS+=("{\"check\": \"$check_name\", \"status\": \"$status\", \"message\": \"$message\"}")
}

# Check 1: Verify graceful shutdown hook executed
check_graceful_shutdown() {
    log INFO "Checking graceful shutdown hook execution..."

    if journalctl -b -1 -u "$DOCKER_SERVICE_NAME" 2>/dev/null | grep -q "Graceful shutdown completed"; then
        log INFO "✓ Graceful shutdown hook executed successfully"
        add_json_result "graceful_shutdown" "pass" "Hook executed"
        return 0
    else
        log ERROR "✗ Graceful shutdown hook did NOT execute"
        add_json_result "graceful_shutdown" "fail" "Hook not executed"
        return 1
    fi
}

# Check 2: Verify all containers are running
check_containers_running() {
    log INFO "Checking Docker containers..."

    if ! systemctl is-active --quiet docker; then
        log ERROR "✗ Docker service is not running"
        add_json_result "containers" "fail" "Docker service not running"
        return 1
    fi

    local total_containers
    local running_containers
    local exited_containers

    total_containers=$(docker ps -a --format "{{.Names}}" 2>/dev/null | wc -l)
    running_containers=$(docker ps --format "{{.Names}}" 2>/dev/null | wc -l)
    exited_containers=$(docker ps -a --filter "status=exited" --format "{{.Names}}" 2>/dev/null | wc -l)

    if [[ "$total_containers" -eq 0 ]]; then
        log WARN "⚠ No containers found (expected behavior if not using Docker)"
        add_json_result "containers" "skip" "No containers"
        return 0
    fi

    if [[ "$exited_containers" -gt 0 ]]; then
        log ERROR "✗ $exited_containers containers in 'exited' state"
        if [[ "$VERBOSE" == true ]]; then
            docker ps -a --filter "status=exited" --format "  - {{.Names}}: {{.Status}}"
        fi
        add_json_result "containers" "fail" "$exited_containers containers exited"
        return 1
    fi

    log INFO "✓ All $running_containers containers are running"
    add_json_result "containers" "pass" "$running_containers containers running"
    return 0
}

# Check 3: Verify container health checks
check_container_health() {
    log INFO "Checking container health..."

    if ! systemctl is-active --quiet docker; then
        add_json_result "health" "skip" "Docker not running"
        return 0
    fi

    local unhealthy_count
    unhealthy_count=$(docker ps --format "{{.Names}} {{.Status}}" 2>/dev/null | grep -c "unhealthy" || true)

    if [[ "$unhealthy_count" -gt 0 ]]; then
        log WARN "⚠ $unhealthy_count containers are unhealthy"
        if [[ "$VERBOSE" == true ]]; then
            docker ps --format "{{.Names}}: {{.Status}}" | grep "unhealthy" | sed 's/^/  - /'
        fi
        add_json_result "health" "warn" "$unhealthy_count containers unhealthy"
        return 1
    fi

    log INFO "✓ All containers are healthy"
    add_json_result "health" "pass" "All containers healthy"
    return 0
}

# Check 4: Verify network connectivity
check_network() {
    log INFO "Checking network connectivity..."

    # Check if at least one interface has an IP
    local interfaces_with_ip
    interfaces_with_ip=$(ip -4 addr show | grep -c "inet " || true)

    if [[ "$interfaces_with_ip" -eq 0 ]]; then
        log ERROR "✗ No network interfaces have an IP address"
        add_json_result "network" "fail" "No IP addresses"
        return 1
    fi

    # Try to ping a public DNS (optional, may fail in isolated environments)
    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        log INFO "✓ Network connectivity verified (ping 8.8.8.8 success)"
        add_json_result "network" "pass" "Internet connectivity"
    else
        log WARN "⚠ Cannot reach 8.8.8.8 (may be expected in isolated networks)"
        add_json_result "network" "warn" "No internet connectivity"
    fi

    return 0
}

# Check 5: Verify critical services (generic list)
check_critical_services() {
    log INFO "Checking critical services..."

    # Generic service list (users should customize)
    local services=("ssh" "docker")
    local failed_services=0

    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            if [[ "$VERBOSE" == true ]]; then
                log INFO "  ✓ $service: running"
            fi
        else
            log WARN "  ✗ $service: not running"
            ((failed_services++))
        fi
    done

    if [[ "$failed_services" -eq 0 ]]; then
        log INFO "✓ All critical services are running"
        add_json_result "services" "pass" "All services running"
        return 0
    else
        log WARN "⚠ $failed_services critical services not running"
        add_json_result "services" "warn" "$failed_services services down"
        return 1
    fi
}

# Main execution
main() {
    local exit_code=0

    if [[ "$JSON_OUTPUT" == false ]]; then
        echo -e "${GREEN}=== Post-Reboot Verification ===${NC}"
        echo "Time: $(date)"
        echo "----------------------------------------"
    fi

    # Ensure report directory exists
    mkdir -p "$REPORT_DIR"

    # Run all checks (first-failure-wins: preserve first error code)
    check_graceful_shutdown || { [[ $exit_code -eq 0 ]] && exit_code=1; }
    check_containers_running || { [[ $exit_code -eq 0 ]] && exit_code=2; }
    check_container_health || { [[ $exit_code -eq 0 ]] && exit_code=3; }
    check_network || { [[ $exit_code -eq 0 ]] && exit_code=4; }
    check_critical_services || true  # Don't fail on service check

    # Generate report
    REPORT="$REPORT_DIR/reboot-check-${TIMESTAMP}.txt"

    if [[ "$JSON_OUTPUT" == true ]]; then
        # JSON output (escape values for safety)
        local json_hostname
        json_hostname=$(json_escape "$(hostname)")
        echo "{"
        echo "  \"timestamp\": \"$(date -Iseconds)\","
        echo "  \"hostname\": \"$json_hostname\","
        echo "  \"checks\": ["

        local first=true
        for result in "${JSON_RESULTS[@]}"; do
            if [[ "$first" == true ]]; then
                first=false
            else
                echo ","
            fi
            echo "    $result"
        done

        echo ""
        echo "  ],"
        echo "  \"exit_code\": $exit_code"
        echo "}"
    else
        # Text summary
        {
            echo "Post-Reboot Verification Report"
            echo "================================"
            echo "Generated: $(date)"
            echo "Hostname: $(hostname)"
            echo ""
            echo "Exit Code: $exit_code"
            echo ""
            echo "Check Results:"
            for result in "${JSON_RESULTS[@]}"; do
                echo "  $result"
            done
        } > "$REPORT"

        echo ""
        echo -e "${GREEN}Report saved to:${NC} $REPORT"

        if [[ "$exit_code" -eq 0 ]]; then
            echo -e "${GREEN}✓ All checks passed${NC}"
        else
            echo -e "${RED}⚠ Some checks failed (exit code: $exit_code)${NC}"
            echo "  1 - Graceful shutdown hook didn't run"
            echo "  2 - Containers not running"
            echo "  3 - Health checks failing"
            echo "  4 - Network issues"
        fi
    fi

    return $exit_code
}

# Run main function
main
