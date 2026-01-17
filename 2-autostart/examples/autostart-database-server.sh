#!/bin/bash
# Copyright (c) 2026 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/linux-server-reboot-management

# Database Server Autostart Example
# Demonstrates database-centric startup pattern for DB servers.
# Pattern: Storage → Databases → Backup → Monitoring

set -euo pipefail

LOG_FILE="/var/log/autostart-database.log"
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

wait_for_database() {
    local db_type=$1
    local timeout=${2:-30}
    local waited=0

    log "Waiting for $db_type (max ${timeout}s)..."

    while [ $waited -lt "$timeout" ]; do
        case "$db_type" in
            postgresql)
                if pg_isready -q 2>/dev/null; then
                    log "✓ PostgreSQL ready after ${waited}s"
                    return 0
                fi
                ;;
            mariadb|mysql)
                if mysqladmin ping -h localhost 2>/dev/null | grep -q "alive"; then
                    log "✓ MariaDB/MySQL ready after ${waited}s"
                    return 0
                fi
                ;;
            mongodb)
                if mongosh --eval "db.adminCommand('ping')" &>/dev/null; then
                    log "✓ MongoDB ready after ${waited}s"
                    return 0
                fi
                ;;
        esac
        sleep 2
        waited=$((waited + 2))
    done

    log "⚠ $db_type did not become ready within ${timeout}s"
    return 1
}

main() {
    log "=== Database Server Autostart ==="

    # 1. Verify storage mounts
    log "Phase 1: Storage Validation"

    # Check critical database mount points
    local db_mounts=("/var/lib/postgresql" "/var/lib/mysql")
    for mount in "${db_mounts[@]}"; do
        if mountpoint -q "$mount" 2>/dev/null || [ -d "$mount" ]; then
            log "✓ Database storage $mount available"
        else
            log "⚠ Database storage $mount not mounted"
        fi
    done

    # Check disk space
    local var_usage
    var_usage=$(df -h /var | awk 'NR==2 {print $5}' | tr -d '%')
    if [ "$var_usage" -lt 80 ]; then
        log "✓ Disk space OK ($var_usage% used)"
    else
        log "⚠ Disk space critical ($var_usage% used)"
    fi

    # 2. Start database services
    log "Phase 2: Database Services"

    # PostgreSQL
    if systemctl list-unit-files | grep -q "postgresql"; then
        start_service "postgresql" "PostgreSQL Database"
        wait_for_database "postgresql" 30
    fi

    # MariaDB/MySQL
    if systemctl list-unit-files | grep -q "mariadb\|mysql"; then
        start_service "mariadb" "MariaDB Database" || \
            start_service "mysql" "MySQL Database"
        wait_for_database "mariadb" 30
    fi

    # MongoDB
    if systemctl list-unit-files | grep -q "mongod"; then
        start_service "mongod" "MongoDB Database"
        wait_for_database "mongodb" 30
    fi

    # Redis (cache/queue)
    if systemctl list-unit-files | grep -q "redis"; then
        start_service "redis" "Redis Cache"
        sleep 2
        if redis-cli ping 2>/dev/null | grep -q "PONG"; then
            log "✓ Redis responding to ping"
        fi
    fi

    # 3. Verify database connectivity
    log "Phase 3: Database Verification"

    # PostgreSQL connection test
    if command -v psql &>/dev/null && systemctl is-active --quiet postgresql; then
        if psql -U postgres -c "SELECT 1;" &>/dev/null; then
            log "✓ PostgreSQL connection verified"
        else
            log "⚠ PostgreSQL connection failed"
        fi
    fi

    # MariaDB connection test
    if command -v mysql &>/dev/null && systemctl is-active --quiet mariadb; then
        if mysql -e "SELECT 1;" &>/dev/null; then
            log "✓ MariaDB connection verified"
        else
            log "⚠ MariaDB connection failed"
        fi
    fi

    # 4. Start backup services
    log "Phase 4: Backup Services"

    # Database backup timers
    if systemctl list-unit-files | grep -q "database-backup.timer"; then
        systemctl start database-backup.timer 2>/dev/null && \
            log "✓ Database backup timer started" || \
            log "⚠ Database backup timer failed"
    fi

    # 5. Start monitoring
    log "Phase 5: Database Monitoring"

    # PostgreSQL exporter
    if systemctl list-unit-files | grep -q "postgres_exporter"; then
        start_service "postgres_exporter" "PostgreSQL Exporter"
    fi

    # MySQL exporter
    if systemctl list-unit-files | grep -q "mysqld_exporter"; then
        start_service "mysqld_exporter" "MySQL Exporter"
    fi

    # 6. Database health summary
    log "Phase 6: Health Summary"

    local active_dbs=0
    for db_service in postgresql mariadb mysql mongod redis; do
        if systemctl is-active --quiet "$db_service" 2>/dev/null; then
            log "✓ $db_service active"
            active_dbs=$((active_dbs + 1))
        fi
    done

    log "✓ $active_dbs database service(s) active"

    # 7. Boot performance
    local boot_time=$(($(date +%s) - BOOT_START_TIME))
    log "=== Database Server Boot Complete: ${boot_time}s ==="

    # Prometheus metrics (optional)
    if [[ -d /var/lib/node_exporter/textfile_collector ]]; then
        cat > /var/lib/node_exporter/textfile_collector/database-boot.prom <<EOF
# HELP database_boot_duration_seconds Database server boot duration
# TYPE database_boot_duration_seconds gauge
database_boot_duration_seconds $boot_time
database_boot_timestamp $(date +%s)
database_services_active $active_dbs
database_storage_usage_percent $var_usage
EOF
        log "✓ Metrics exported"
    fi
}

main "$@"
