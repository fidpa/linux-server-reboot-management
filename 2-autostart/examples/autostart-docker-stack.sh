#!/bin/bash
# Copyright (c) 2026 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/linux-server-reboot-management

# Docker Stack Autostart Example
# Demonstrates tiered container startup pattern for multi-service Docker stacks.
# Pattern: Databases → Cache → Processing → Applications → Monitoring

set -euo pipefail

LOG_FILE="/var/log/autostart-docker.log"
BOOT_START_TIME=$(date +%s)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

start_container() {
    local container=$1
    local health_mode=${2:-started}
    local timeout=${3:-60}

    if ! docker ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
        log "⚠ Container $container does not exist"
        return 1
    fi

    if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
        log "✓ $container already running"
        return 0
    fi

    log "Starting $container..."
    docker start "$container" &>/dev/null || {
        log "✗ Failed to start $container"
        return 1
    }

    if [[ "$health_mode" == "healthy" ]] && [[ $timeout -gt 0 ]]; then
        local waited=0
        while [ $waited -lt "$timeout" ]; do
            local health
            health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")
            if [[ "$health" == "healthy" ]] || [[ "$health" == "none" ]]; then
                log "✓ $container healthy after ${waited}s"
                return 0
            fi
            sleep 2
            waited=$((waited + 2))
        done
        log "⚠ $container health timeout (${timeout}s)"
        return 1
    fi

    log "✓ $container started"
    return 0
}

main() {
    log "=== Docker Stack Autostart ==="

    # 1. Wait for Docker daemon
    log "Waiting for Docker daemon..."
    if ! systemctl start docker; then
        log "✗ Docker daemon failed to start"
        exit 1
    fi

    local docker_wait=0
    while [ $docker_wait -lt 30 ]; do
        if docker info &>/dev/null; then
            log "✓ Docker daemon ready after ${docker_wait}s"
            break
        fi
        sleep 1
        docker_wait=$((docker_wait + 1))
    done

    if [ $docker_wait -ge 30 ]; then
        log "✗ Docker daemon timeout"
        exit 1
    fi

    # 2. Tier 1: Databases (parallel with PID tracking)
    log "Tier 1: Starting database containers..."
    declare -a tier1_pids=()
    start_container "mariadb" "healthy" 60 & tier1_pids+=($!)
    start_container "postgres" "healthy" 60 & tier1_pids+=($!)

    # Wait for all Tier 1 containers
    local tier1_failed=false
    for pid in "${tier1_pids[@]}"; do
        if ! wait "$pid"; then
            log "✗ Tier 1: Container startup failed (PID: $pid)"
            tier1_failed=true
        fi
    done

    if [ "$tier1_failed" = true ]; then
        log "⚠ Tier 1: Database startup had failures"
    else
        log "✓ Tier 1: Databases started"
    fi

    # 3. Tier 2: Caching layers
    log "Tier 2: Starting cache containers..."
    start_container "redis" "healthy" 30
    start_container "memcached" "started" 0
    log "✓ Tier 2: Cache started"

    # 4. Tier 3: Processing engines
    log "Tier 3: Starting processing engines..."
    start_container "rabbitmq" "healthy" 60
    start_container "elasticsearch" "healthy" 90
    log "✓ Tier 3: Processing engines started"

    # 5. Tier 4: Applications (depend on Tier 1-3)
    log "Tier 4: Starting application containers..."
    start_container "webapp" "healthy" 180
    start_container "api-server" "healthy" 120
    log "✓ Tier 4: Applications started"

    # 6. Tier 5: Monitoring (independent)
    log "Tier 5: Starting monitoring containers..."
    start_container "prometheus" "started" 0
    start_container "grafana" "healthy" 60
    start_container "node-exporter" "started" 0
    log "✓ Tier 5: Monitoring started"

    # 7. Verify critical containers
    log "Verifying critical containers..."
    local failed=0
    for container in mariadb postgres webapp; do
        if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
            local health
            health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")
            log "✓ $container running (health: $health)"
        else
            log "✗ $container not running"
            failed=$((failed + 1))
        fi
    done

    if [ $failed -eq 0 ]; then
        log "✓ All critical containers verified"
    else
        log "⚠ $failed critical container(s) failed"
    fi

    # 8. Boot performance
    local boot_time=$(($(date +%s) - BOOT_START_TIME))
    log "=== Docker Stack Boot Complete: ${boot_time}s ==="

    # Prometheus metrics (optional)
    if [[ -d /var/lib/node_exporter/textfile_collector ]]; then
        cat > /var/lib/node_exporter/textfile_collector/docker-boot.prom <<EOF
# HELP docker_stack_boot_duration_seconds Docker stack boot duration
# TYPE docker_stack_boot_duration_seconds gauge
docker_stack_boot_duration_seconds $boot_time
docker_stack_boot_timestamp $(date +%s)
EOF
        log "✓ Metrics exported"
    fi
}

main "$@"
