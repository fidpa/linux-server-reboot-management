#!/bin/bash
# Copyright (c) 2026 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/linux-server-reboot-management

# Minimal Autostart Example
# Simplified boot orchestration for small setups.
# Minimal implementation showing core autostart concepts without
# full 13-phase complexity. Perfect for learning or simple setups.
# Usage:
#   sudo ./autostart-minimal.sh
#

set -euo pipefail

LOG_FILE="/var/log/autostart-minimal.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

start_service() {
    local service=$1
    local name=${2:-$service}

    log "Starting $name..."

    if systemctl start "$service"; then
        log "✓ $name started"
        return 0
    else
        log "✗ $name failed"
        return 1
    fi
}

main() {
    log "=== Minimal Autostart ==="

    # 1. Core Services
    start_service "ssh.service" "SSH"
    start_service "cron.service" "Cron"

    # 2. Docker (if installed)
    if systemctl list-units --all | grep -q "docker.service"; then
        start_service "docker.service" "Docker"

        # Wait for Docker socket
        sleep 5

        # Start containers
        if [[ -f /opt/docker/docker-compose.yml ]]; then
            log "Starting Docker containers..."
            cd /opt/docker && docker-compose up -d || log "✗ Docker compose failed"
        fi
    fi

    # 3. Monitoring (optional)
    if systemctl list-units --all | grep -q "node_exporter.service"; then
        start_service "node_exporter.service" "Node Exporter"
    fi

    log "=== Autostart Complete ==="
}

main "$@"
