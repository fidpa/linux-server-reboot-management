#!/bin/bash
# Copyright (c) 2026 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/linux-server-reboot-management

# Docker Graceful Shutdown Hook
# Stops Docker containers gracefully before system halt/reboot.
# Prevents unsafe shutdowns by gracefully stopping all Docker containers
#   before systemd shutdown.target is reached. Eliminates data corruption risk
#   for databases (PostgreSQL, MariaDB, MongoDB), caches (Redis, Memcached),
#   and application containers.
#
# Requirements:
#   - Docker 19.03+
#   - systemd 240+
#   - Bash 4.0+
#
# Usage:
#   Called automatically by systemd service during shutdown/reboot.
#   DO NOT run manually unless testing.
#
# Version: 1.0.0
#
# Features:
#   - Graceful container stop with configurable timeout (default: 30s)
#   - Configurable log file via environment variable
#   - Restart policy check with warnings
#   - Explicit buffer flush (sync) after container stops
#
set -uo pipefail  # No -e: Explicit error handling (Best Practice 2025)

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_NAME="docker-graceful-shutdown"

# Log file location (configurable via environment variable)
LOG_FILE="${GRACEFUL_SHUTDOWN_LOG_FILE:-/var/log/docker-graceful-shutdown.log}"

# Container stop timeout (seconds)
CONTAINER_TIMEOUT="${GRACEFUL_SHUTDOWN_TIMEOUT:-30}"

# ============================================================================
# LOGGING
# ============================================================================

# Ensure log directory exists
LOG_DIR="$(dirname "$LOG_FILE")"
if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
    echo "ERROR: Failed to create log directory: $LOG_DIR" >&2
    exit 1
fi

# Simple logging function (no external dependencies)
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date +'%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "UNKNOWN")

    echo "[${timestamp}] [${level}] ${message}" | tee -a "$LOG_FILE"
}

# ============================================================================
# MAIN SHUTDOWN SEQUENCE
# ============================================================================

main() {
    log "INFO" "Graceful shutdown initiated"

    local stopped_containers=0
    local failed_containers=0
    local containers_with_unless_stopped=0

    # Get list of all running containers
    local running_containers
    if ! running_containers=$(docker ps --format "{{.Names}}" 2>/dev/null); then
        log "WARN" "Failed to get running containers list (docker may not be running)"
        running_containers=""
    fi

    local container_count
    container_count=$(echo "$running_containers" | grep -c . || echo 0)

    if [[ $container_count -eq 0 ]]; then
        log "INFO" "No running containers found"
    else
        log "INFO" "Found $container_count running containers"

        # Stop each container gracefully
        while IFS= read -r container; do
            [[ -z "$container" ]] && continue

            log "INFO" "Stopping container: $container (timeout: ${CONTAINER_TIMEOUT}s)"

            # Check restart policy (warn if unless-stopped)
            local restart_policy
            restart_policy=$(docker inspect "$container" --format '{{.HostConfig.RestartPolicy.Name}}' 2>/dev/null || echo "unknown")

            if [[ "$restart_policy" == "unless-stopped" ]]; then
                ((containers_with_unless_stopped++))
                log "WARN" "Container '$container' has restart=unless-stopped (won't auto-restart after reboot!)"
            fi

            # Attempt graceful stop with timeout
            # Use PIPESTATUS[0] to get docker's exit code, not tee's
            docker stop --time "$CONTAINER_TIMEOUT" "$container" 2>&1 | tee -a "$LOG_FILE"
            local docker_exit_code="${PIPESTATUS[0]}"

            if [[ $docker_exit_code -eq 0 ]]; then
                ((stopped_containers++))
                log "INFO" "Successfully stopped: $container"
            else
                ((failed_containers++))
                log "WARN" "Failed to stop: $container (docker exit code: $docker_exit_code)"
            fi
        done <<< "$running_containers"
    fi

    # Alert if containers with unless-stopped found
    if [[ $containers_with_unless_stopped -gt 0 ]]; then
        log "WARN" "Found $containers_with_unless_stopped container(s) with restart=unless-stopped"
        log "WARN" "These containers will NOT auto-restart after reboot!"
        log "WARN" "Consider changing to restart=always for production containers"
    fi

    # Stop Docker daemon (allows full cleanup)
    log "INFO" "Stopping Docker service"
    # Use PIPESTATUS[0] to get systemctl's exit code
    systemctl stop docker.service 2>&1 | tee -a "$LOG_FILE"
    local systemctl_exit_code="${PIPESTATUS[0]}"

    if [[ $systemctl_exit_code -eq 0 ]]; then
        log "INFO" "Docker service stopped successfully"
    else
        log "WARN" "Failed to stop Docker service (systemctl exit code: $systemctl_exit_code)"
    fi

    # Explicit buffer flush (ensures all data written to disk)
    log "INFO" "Flushing filesystem buffers (sync)"
    if sync; then
        log "INFO" "Buffers flushed successfully"
    else
        log "ERROR" "Buffer flush failed (exit code: $?)"
    fi

    # Final summary
    log "INFO" "Graceful shutdown completed: $stopped_containers stopped, $failed_containers failed"

    # Exit 0 even if some containers failed (don't block shutdown)
    return 0
}

# ============================================================================
# EXECUTION
# ============================================================================

# Execute main function
main "$@"
