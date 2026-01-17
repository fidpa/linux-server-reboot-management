#!/bin/bash
# Copyright (c) 2026 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/linux-server-reboot-management

# Custom Health Checks Example
# Advanced post-reboot verification with container-specific health checks.
# Demonstrates how to extend basic verification with custom logic.
#
# Usage:
#   ./03-custom-healthchecks.sh [OPTIONS]
#
# Options:
#   --verbose     Enable verbose output
#   --containers  Comma-separated list of containers to check (default: all)
#   --help        Show this help message
#
# Exit Codes:
#   0 - All checks passed
#   1 - Container health check failed
#   2 - Database connectivity failed
#   3 - Application endpoint failed
#

set -uo pipefail

# Configuration
VERBOSE=false
CONTAINERS=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose)
            VERBOSE=true
            shift
            ;;
        --containers)
            CONTAINERS="$2"
            shift 2
            ;;
        --help)
            grep '^#' "$0" | grep -v '#!/bin/bash' | sed 's/^# //; s/^#//'
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging
log() {
    local level=$1
    shift
    local message="$*"

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
}

verbose_log() {
    if [[ "$VERBOSE" == true ]]; then
        echo "[VERBOSE] $*" >&2
    fi
}

# Check PostgreSQL container
check_postgres() {
    local container=$1
    log INFO "Checking PostgreSQL container: $container"

    # 1. Check if running
    if ! docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
        log ERROR "Container $container is not running"
        return 1
    fi

    # 2. Check health status
    local health_status
    health_status=$(docker inspect "$container" --format '{{.State.Health.Status}}' 2>/dev/null || echo "unknown")

    if [[ "$health_status" != "healthy" ]]; then
        log WARN "Container $container health status: $health_status"
    fi

    # 3. Check database connectivity
    verbose_log "Testing PostgreSQL connectivity..."

    if docker exec "$container" pg_isready -U postgres >/dev/null 2>&1; then
        log INFO "✓ PostgreSQL is ready"
    else
        log ERROR "✗ PostgreSQL is not ready"
        return 1
    fi

    # 4. Test simple query
    verbose_log "Running test query..."

    if docker exec "$container" psql -U postgres -c "SELECT 1;" >/dev/null 2>&1; then
        log INFO "✓ PostgreSQL accepts queries"
    else
        log ERROR "✗ PostgreSQL does not accept queries"
        return 1
    fi

    # 5. Check for crash recovery
    if docker logs "$container" 2>&1 | grep -q "database system was not properly shut down"; then
        log WARN "⚠ PostgreSQL detected unclean shutdown (crash recovery ran)"
        return 1
    fi

    log INFO "✓ PostgreSQL: All checks passed"
    return 0
}

# Check Redis container
check_redis() {
    local container=$1
    log INFO "Checking Redis container: $container"

    # 1. Check if running
    if ! docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
        log ERROR "Container $container is not running"
        return 1
    fi

    # 2. Check health status
    local health_status
    health_status=$(docker inspect "$container" --format '{{.State.Health.Status}}' 2>/dev/null || echo "unknown")

    if [[ "$health_status" != "healthy" ]]; then
        log WARN "Container $container health status: $health_status"
    fi

    # 3. Ping Redis
    verbose_log "Pinging Redis..."

    if docker exec "$container" redis-cli ping | grep -q "PONG"; then
        log INFO "✓ Redis is responding"
    else
        log ERROR "✗ Redis is not responding"
        return 1
    fi

    # 4. Check memory usage
    verbose_log "Checking Redis memory..."

    local mem_used
    mem_used=$(docker exec "$container" redis-cli INFO memory | grep "used_memory_human" | cut -d: -f2 | tr -d '\r')

    if [[ -n "$mem_used" ]]; then
        verbose_log "Redis memory usage: $mem_used"
    fi

    # 5. Check for AOF/RDB errors
    if docker logs "$container" 2>&1 | grep -E "(AOF|RDB).*error"; then
        log WARN "⚠ Redis persistence errors detected"
    fi

    log INFO "✓ Redis: All checks passed"
    return 0
}

# Check web application container
check_web_app() {
    local container=$1
    log INFO "Checking web application: $container"

    # 1. Check if running
    if ! docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
        log ERROR "Container $container is not running"
        return 1
    fi

    # 2. Check health status
    local health_status
    health_status=$(docker inspect "$container" --format '{{.State.Health.Status}}' 2>/dev/null || echo "unknown")

    if [[ "$health_status" != "healthy" ]]; then
        log WARN "Container $container health status: $health_status"
    fi

    # 3. Check HTTP endpoint (if nginx)
    verbose_log "Testing HTTP endpoint..."

    local port
    port=$(docker inspect "$container" --format '{{(index (index .NetworkSettings.Ports "80/tcp") 0).HostPort}}' 2>/dev/null)

    if [[ -n "$port" ]]; then
        if curl -sf "http://localhost:${port}/health" >/dev/null 2>&1; then
            log INFO "✓ Health endpoint responding"
        else
            log WARN "⚠ Health endpoint not responding (may be expected)"
        fi
    fi

    log INFO "✓ Web app: All checks passed"
    return 0
}

# Main execution
main() {
    echo -e "${GREEN}=== Custom Health Checks ===${NC}"
    echo "Time: $(date)"
    echo "----------------------------------------"

    local exit_code=0

    # Get container list
    local container_list
    if [[ -n "$CONTAINERS" ]]; then
        IFS=',' read -ra container_list <<< "$CONTAINERS"
    else
        # Auto-detect running containers
        mapfile -t container_list < <(docker ps --format "{{.Names}}")
    fi

    if [[ ${#container_list[@]} -eq 0 ]]; then
        log WARN "No containers found to check"
        return 0
    fi

    log INFO "Checking ${#container_list[@]} containers..."
    echo ""

    # Check each container
    for container in "${container_list[@]}"; do
        # Detect container type and run appropriate checks
        if [[ "$container" =~ postgres ]]; then
            check_postgres "$container" || exit_code=1
        elif [[ "$container" =~ redis ]]; then
            check_redis "$container" || exit_code=1
        elif [[ "$container" =~ (nginx|app|web) ]]; then
            check_web_app "$container" || exit_code=1
        else
            # Generic check for unknown container types
            log INFO "Checking generic container: $container"

            if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
                log INFO "✓ Container $container is running"
            else
                log ERROR "✗ Container $container is not running"
                exit_code=1
            fi
        fi

        echo ""
    done

    # Summary
    echo "----------------------------------------"
    if [[ $exit_code -eq 0 ]]; then
        echo -e "${GREEN}✓ All health checks passed${NC}"
    else
        echo -e "${RED}✗ Some health checks failed${NC}"
    fi

    return $exit_code
}

# Run main
main
