# Template Customization Guide

## ⚡ TL;DR

Templates require customization; system-snapshot.sh and autostart-template.sh provide Extension API for environment-specific metrics and service orchestration.

---

## Table of Contents

- [Overview](#overview)
- [System Snapshot Customization](#system-snapshot-customization)
- [Autostart Template Customization](#autostart-template-customization)
- [systemd Service Customization](#systemd-service-customization)
- [Post-Reboot Check Customization](#post-reboot-check-customization)
- [Common Customization Patterns](#common-customization-patterns)
- [See Also](#see-also)

---

How to adapt the templates for your environment.

## Overview

This repository provides **templates** demonstrating production patterns, not ready-to-run scripts. Customization is required.

**Templates**:
1. `0-pre-reboot/system-snapshot.sh` - Core + Extension API
2. `2-autostart/autostart-template.sh` - 13-phase boot orchestration
3. `2-autostart/autostart-minimal.sh` - Simplified alternative

**Ready-to-use**:
- `1-graceful-shutdown/docker-graceful-shutdown.sh` ✅
- `3-verification/post-reboot-check.sh` ✅
- `3-verification/snapshot-compare.py` ✅

---

## System Snapshot Customization

### Base Configuration

**File**: `0-pre-reboot/system-snapshot.sh`

**Environment Variables**:
```bash
# Customize output location
export SNAPSHOT_DIR="/var/log/my-app/snapshots"

# Run snapshot
./system-snapshot.sh pre-reboot
```

### Adding Custom Metrics

**Two approaches**:

#### A) Extension API (Recommended)

Create wrapper script:
```bash
#!/bin/bash
# my-snapshot.sh

# Source core snapshot tool
source "0-pre-reboot/system-snapshot.sh"

# Override custom metrics function
collect_custom_metrics() {
    append_buffer '  "custom": {'

    # Your custom metrics here
    local app_status
    app_status=$(systemctl is-active myapp.service)
    append_buffer "    \"myapp_status\": \"$app_status\","

    # Database size
    local db_size
    db_size=$(du -sh /var/lib/mysql | cut -f1)
    append_buffer "    \"database_size\": \"$db_size\""

    append_buffer '  }'
}

# Enable extensions
ENABLE_EXTENSIONS=true
```

#### B) Fork and Modify

Copy `system-snapshot.sh` and add metrics directly after line 130 (after `collect_storage()`).

### Examples

See `0-pre-reboot/examples/snapshot-extensions-example.sh` for:
- Hardware temperature (vcgencmd)
- Network interface statistics
- Custom service health
- WireGuard VPN stats
- Disk I/O metrics
- Application metrics

---

## Autostart Template Customization

### Choosing the Right Template

**Use `autostart-minimal.sh` if**:
- Small setup (<10 services)
- No complex dependencies
- Simple Docker stack
- **Example**: Personal homelab, single Docker Compose stack

**Use `autostart-template.sh` if**:
- Production environment
- Multiple service dependencies
- Network services (VPN, firewall, DNS)
- Storage validation required (LVM, RAID)
- **Example**: Production server, gateway/router, database server

**Use specialized examples** (`2-autostart/examples/`):
- `autostart-docker-stack.sh`: Multi-tier container startup (databases → cache → apps → monitoring)
- `autostart-network-gateway.sh`: Network foundation (NAT, firewall, VPN, DNS)
- `autostart-database-server.sh`: Database-centric startup (storage → databases → backup → monitoring)

### Helper Functions Available

The template provides 5 helper functions:

1. **`start_service()`** - Start systemd service with LoadState check and retry logic
2. **`start_timer()`** - Start systemd timer with existence check
3. **`wait_for_service()`** - Wait for service to become active (timeout configurable)
4. **`start_container()`** - Start Docker container with 3 health modes (healthy, started, none)
5. **`check_service_health()`** - Check service health with optional custom command

**Usage Examples**:
```bash
# Start service with 3 retries, 15s timeout each
start_service "postgresql.service" "PostgreSQL" 3 15

# Wait for Docker daemon (max 60s)
wait_for_service "docker.service" 60

# Start container with health check (max 120s)
start_container "postgres" "healthy" 120

# Custom health check
check_service_health "nginx" "curl -sf http://localhost"
```

### Customization Steps

#### 1. Copy Template

```bash
cp 2-autostart/autostart-template.sh /opt/my-autostart.sh
chmod +x /opt/my-autostart.sh
```

#### 2. Update Configuration

Edit lines 40-57:
```bash
LOG_FILE="/var/log/my-app-autostart.log"
LOCK_FILE="/var/run/my-app-autostart.lock"
PID_FILE="/var/run/my-app-autostart.pid"
MAX_BOOT_TIME=180  # Adjust for your environment

# Feature Flags (customize for your environment)
ENABLE_PROMETHEUS_METRICS="${ENABLE_PROMETHEUS_METRICS:-true}"
ENABLE_RECOVERY_MODE="${ENABLE_RECOVERY_MODE:-true}"
ENABLE_DOCKER_STACK="${ENABLE_DOCKER_STACK:-true}"
ENABLE_PHASE_TIMING="${ENABLE_PHASE_TIMING:-true}"
```

**Feature Flags Explained**:
- `ENABLE_PROMETHEUS_METRICS`: Export boot metrics to `/var/lib/node_exporter/textfile_collector/`
- `ENABLE_RECOVERY_MODE`: Activate emergency SSH on critical failures (Phase 1, 3, 6)
- `ENABLE_DOCKER_STACK`: Enable/disable Phase 9 (Docker container management)
- `ENABLE_PHASE_TIMING`: Track per-phase timing metrics (stored in `PHASE_TIMINGS` array)

#### 3. Customize Phase 4: Device-Specific

**Example: USB Hardware Init**:
```bash
phase_4_device_specific() {
    log_info "=== Phase 4: Device-Specific Initialization ==="

    # Wait for USB devices
    sleep 5

    # Check USB network adapter
    if [[ ! -d /sys/class/net/eth1 ]]; then
        log_warn "USB network adapter not found"
        # Recovery logic here
    fi

    # Initialize hardware monitoring
    start_service "lm-sensors.service" "Hardware Sensors"
}
```

#### 4. Customize Phase 6: Core Services

**Replace generic services with yours**:
```bash
phase_6_core_services() {
    log_info "=== Phase 6: Core System Services ==="

    # Critical services for your environment
    start_service "ssh.service" "SSH Server" 3 15
    start_service "postgresql.service" "PostgreSQL" 3 30
    start_service "redis.service" "Redis" 2 10
    start_service "nginx.service" "Nginx" 2 10
}
```

#### 5. Customize Phase 7: Network Services

**Example: Firewall + VPN**:
```bash
phase_7_network_services() {
    log_info "=== Phase 7: Network Services ==="

    # Firewall first (blocks unwanted traffic)
    start_service "ufw.service" "UFW Firewall" 2 10

    # VPN second
    start_service "wg-quick@wg0.service" "WireGuard VPN" 3 15

    # Wait for VPN to establish
    sleep 5

    if ip link show wg0 &>/dev/null; then
        log_success "VPN interface wg0 active"
    else
        log_warn "VPN interface wg0 not found"
    fi
}
```

#### 6. Customize Phase 9: Docker Stack

**Option A: Using start_container() helper** (Recommended):
```bash
phase_9_docker_stack() {
    log_info "=== Phase 9: Docker Stack ==="

    if [[ "$ENABLE_DOCKER_STACK" != "true" ]]; then
        log_info "Docker stack disabled (ENABLE_DOCKER_STACK=false)"
        return 0
    fi

    start_service "docker.service" "Docker Daemon" 3 30
    wait_for_service "docker.service" 60

    # Tier 1: Databases (parallel)
    start_container "postgres" "healthy" 60 &
    start_container "mariadb" "healthy" 60 &
    wait

    # Tier 2: Cache
    start_container "redis" "healthy" 30

    # Tier 3: Applications
    start_container "webapp" "healthy" 180
    start_container "api-server" "healthy" 120
}
```

**Option B: docker-compose deployment**:
```bash
phase_9_docker_stack() {
    log_info "=== Phase 9: Docker Stack ==="

    start_service "docker.service" "Docker Daemon" 3 30

    if systemctl is-active --quiet docker; then
        # Wait for Docker socket
        local timeout=30
        while [[ ! -S /var/run/docker.sock ]] && [[ $timeout -gt 0 ]]; do
            sleep 1
            ((timeout--))
        done

        # Start containers via docker-compose
        cd /opt/my-app || exit 1

        log_info "Starting Docker Compose stack..."
        if docker-compose up -d --remove-orphans; then
            log_success "Docker Compose stack started"

            # Wait for health checks
            sleep 10

            # Verify containers
            local unhealthy
            unhealthy=$(docker ps --filter "health=unhealthy" -q | wc -l)
            if [[ $unhealthy -gt 0 ]]; then
                log_warn "$unhealthy containers are unhealthy"
            fi
        else
            log_error "Docker Compose failed to start"
        fi
    fi
}
```

**See also**: `2-autostart/examples/autostart-docker-stack.sh` for multi-tier startup pattern

#### 7. Customize Phase 10: Service Verification

**Define your critical services**:
```bash
phase_10_service_verification() {
    log_info "=== Phase 10: Service Verification ==="

    local critical_services=(
        "ssh.service"
        "postgresql.service"
        "redis.service"
        "nginx.service"
        "docker.service"
    )

    # Check each service
    # (rest of function stays the same)
}
```

### Testing Your Customized Autostart

**Never test with reboot first!**

```bash
# 1. Syntax check
bash -n /opt/my-autostart.sh

# 2. Dry-run simulation (add --dry-run flag to your script)
sudo /opt/my-autostart.sh --dry-run

# 3. Manual execution (before systemd integration)
sudo /opt/my-autostart.sh

# 4. Check logs
tail -f /var/log/my-app-autostart.log

# 5. systemd integration
sudo cp my-autostart.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable my-autostart.service

# 6. Test reboot
sudo reboot
```

---

## systemd Service Customization

### Graceful Shutdown Service

**File**: `config/systemd/docker-graceful-shutdown.service`

**Customization points**:
```ini
[Service]
# Adjust timeout for your container count
TimeoutStopSec=120  # 30-180s depending on stack size

# Environment variables
Environment="GRACEFUL_SHUTDOWN_LOG_FILE=/var/log/my-app/shutdown.log"
Environment="GRACEFUL_SHUTDOWN_TIMEOUT=60"  # Per-container timeout
```

### Autostart Service

**Create**: `my-autostart.service`

```ini
[Unit]
Description=My Application Autostart Orchestration
After=network-online.target
Wants=network-online.target
# Add dependencies for your environment
After=postgresql.service
After=redis.service

[Service]
Type=oneshot
ExecStart=/opt/my-autostart.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

# Adjust timeout for your boot target
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
```

---

## Post-Reboot Check Customization

**File**: `3-verification/post-reboot-check.sh`

**Environment Variables**:
```bash
# Customize service name
export DOCKER_SERVICE_NAME="my-graceful-shutdown"

# Customize log directory
export LOG_DIR="/var/log/my-app"

# Run check
./post-reboot-check.sh --verbose
```

**Custom Health Checks**:

See `3-verification/examples/03-custom-healthchecks.sh` for container-specific checks (PostgreSQL, Redis, web apps).

---

## Common Customization Patterns

### Pattern 1: Multi-Environment Support

```bash
# Detect environment
ENVIRONMENT="${ENVIRONMENT:-production}"

case "$ENVIRONMENT" in
    production)
        MAX_BOOT_TIME=120
        CRITICAL_SERVICES=("nginx" "postgresql" "redis")
        ;;
    staging)
        MAX_BOOT_TIME=180
        CRITICAL_SERVICES=("nginx")
        ;;
    development)
        MAX_BOOT_TIME=300
        CRITICAL_SERVICES=()
        ;;
esac
```

### Pattern 2: Conditional Phases

```bash
phase_7_network_services() {
    log_info "=== Phase 7: Network Services ==="

    # Only on gateway nodes
    if [[ "$NODE_TYPE" == "gateway" ]]; then
        start_service "nftables.service" "nftables Firewall"
        start_service "wg-quick@wg0.service" "WireGuard VPN"
    fi

    # Only on DNS nodes
    if [[ "$NODE_TYPE" == "dns" ]]; then
        start_service "bind9.service" "BIND DNS"
    fi
}
```

### Pattern 3: Retry with Backoff

```bash
start_service_with_backoff() {
    local service=$1
    local max_attempts=5

    for attempt in $(seq 1 $max_attempts); do
        if start_service "$service" "$service" 1 10; then
            return 0
        fi

        local backoff=$((attempt * attempt))  # Exponential backoff
        log_warn "Retry $service in ${backoff}s..."
        sleep $backoff
    done

    log_error "$service failed after $max_attempts attempts"
    return 1
}
```

---

## See Also

- [WORKFLOW.md](WORKFLOW.md) - Complete workflow guide
- [ARCHITECTURE.md](ARCHITECTURE.md) - 13-phase model deep dive
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues

---

**Last Updated**: January 2026
