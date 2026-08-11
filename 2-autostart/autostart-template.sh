#!/bin/bash
# Copyright (c) 2026 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/linux-server-reboot-management

# Autostart Template - 13-Phase Boot Orchestration
# Generic template for production server autostart automation.
# Template demonstrating 13-phase boot orchestration pattern used
# in production environments. Customize phases for your setup.
#
# Usage:
#   1. Copy this template to your project
#   2. Customize service lists in each phase
#   3. Adjust timeouts and retry logic
#   4. Configure feature flags
#   5. Test thoroughly before production deployment
#
# systemd Service Example:
#   [Unit]
#   Description=Autostart Orchestration
#   After=network-online.target
#   Wants=network-online.target
#
#   [Service]
#   Type=oneshot
#   ExecStart=/opt/linux-server-reboot-management/2-autostart/autostart-template.sh
#   RemainAfterExit=no
#   StandardOutput=journal
#   StandardError=journal
#
#   [Install]
#   WantedBy=multi-user.target
#

set -uo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

LOG_FILE="${LOG_FILE:-/var/log/autostart.log}"
LOCK_FILE="${LOCK_FILE:-/var/run/autostart.lock}"
PID_FILE="${PID_FILE:-/var/run/autostart.pid}"
BOOT_START_TIME=$(date +%s)
MAX_BOOT_TIME=120  # Target: Complete boot in 120 seconds

# Feature Flags (customize for your environment)
ENABLE_PROMETHEUS_METRICS="${ENABLE_PROMETHEUS_METRICS:-true}"
ENABLE_RECOVERY_MODE="${ENABLE_RECOVERY_MODE:-true}"
ENABLE_DOCKER_STACK="${ENABLE_DOCKER_STACK:-true}"
ENABLE_PHASE_TIMING="${ENABLE_PHASE_TIMING:-true}"

# Phase timing tracker (associative array)
declare -A PHASE_TIMINGS

# Graceful shutdown flag
GRACEFUL_SHUTDOWN=false

# ============================================================================
# LOGGING
# ============================================================================

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"

    # Also log to journal if running under systemd
    if [[ -n "${JOURNAL_STREAM:-}" ]]; then
        # Map log levels to valid syslog priorities
        local syslog_priority
        case "$level" in
            INFO)  syslog_priority="info" ;;
            WARN)  syslog_priority="warning" ;;
            ERROR) syslog_priority="err" ;;
            *)     syslog_priority="notice" ;;
        esac
        logger -t autostart -p "user.$syslog_priority" "$message"
    fi
}

log_info() { log INFO "$@"; }
log_warn() { log WARN "$@"; }
log_error() { log ERROR "$@"; }
log_success() { log INFO "✓ $*"; }

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

start_service() {
    local service=$1
    service="${service%.service}"  # Strip .service suffix if already present
    local friendly_name=${2:-$service}
    local max_retries=${3:-2}
    local timeout=${4:-10}

    # Check if service exists via LoadState (more reliable than list-units)
    local load_state
    load_state=$(systemctl show -p LoadState --value "${service}.service" 2>/dev/null)
    if [[ -z "$load_state" ]] || [[ "$load_state" == "not-found" ]]; then
        return 0  # Service doesn't exist, skip silently
    fi

    # Check if already active
    if systemctl is-active --quiet "$service"; then
        local state
        state=$(systemctl show -p SubState --value "$service")
        if [[ "$state" == "running" ]] || [[ "$state" == "exited" ]]; then
            log_success "$friendly_name already active (state: $state)"
            return 0
        fi
    fi

    # Try to start with retry logic
    for attempt in $(seq 1 "$max_retries"); do
        log_info "Starting $friendly_name (attempt $attempt/$max_retries)..."

        if timeout "$timeout" systemctl start "$service" 2>&1 | tee -a "$LOG_FILE"; then
            sleep 2

            if systemctl is-active --quiet "$service"; then
                local state
                state=$(systemctl show -p SubState --value "$service")
                if [[ "$state" == "running" ]] || [[ "$state" == "exited" ]]; then
                    log_success "$friendly_name started successfully"
                    return 0
                fi
            fi
        fi

        if [[ $attempt -lt $max_retries ]]; then
            sleep 3
        fi
    done

    log_error "$friendly_name failed after $max_retries attempts"
    return 1
}

start_timer() {
    local timer=$1
    timer="${timer%.timer}"  # Strip .timer suffix if already present
    local friendly_name=${2:-$timer}

    # Check if timer exists via LoadState
    local load_state
    load_state=$(systemctl show -p LoadState --value "${timer}.timer" 2>/dev/null)
    if [[ -z "$load_state" ]] || [[ "$load_state" == "not-found" ]]; then
        return 0  # Timer doesn't exist, skip silently
    fi

    if systemctl is-active --quiet "${timer}.timer"; then
        log_success "$friendly_name already active"
        return 0
    fi

    log_info "Starting $friendly_name..."
    if timeout 10 systemctl start "${timer}.timer"; then
        log_success "$friendly_name started"
    else
        log_warn "$friendly_name failed to start"
    fi
}

wait_for_service() {
    local service=$1
    local timeout=${2:-30}
    local waited=0

    log_info "Waiting for $service (max ${timeout}s)..."

    while [ $waited -lt "$timeout" ]; do
        if systemctl is-active --quiet "$service"; then
            log_success "$service active after ${waited}s"
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done

    log_warn "$service did not become active within ${timeout}s"
    return 1
}

start_container() {
    local container=$1
    local health_mode=${2:-started}  # Options: healthy, started, none
    local timeout=${3:-60}

    # Check if Docker is available
    if ! command -v docker &>/dev/null; then
        log_warn "Docker not available, skipping container $container"
        return 1
    fi

    # Check if container exists
    if ! docker ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
        log_warn "Container $container does not exist"
        return 1
    fi

    # Check if already running
    if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
        if [[ "$health_mode" == "healthy" ]]; then
            local health
            health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")
            if [[ "$health" == "healthy" ]] || [[ "$health" == "none" ]]; then
                log_success "$container already running (health: $health)"
                return 0
            else
                log_warn "$container running but health: $health (restarting...)"
                docker restart "$container" &>/dev/null
            fi
        else
            log_success "$container already running"
            return 0
        fi
    else
        # Start container
        log_info "Starting $container..."
        docker start "$container" &>/dev/null || {
            log_error "Failed to start $container"
            return 1
        }
    fi

    # Wait for health if requested
    if [[ "$health_mode" == "healthy" ]] && [[ $timeout -gt 0 ]]; then
        log_info "  Waiting for $container health check (max ${timeout}s)..."
        local waited=0
        while [ $waited -lt "$timeout" ]; do
            local health
            health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")
            if [[ "$health" == "healthy" ]]; then
                log_success "$container healthy after ${waited}s"
                return 0
            elif [[ "$health" == "none" ]]; then
                log_success "$container started (no health check)"
                return 0
            fi
            sleep 2
            waited=$((waited + 2))
        done

        log_warn "$container health check timeout (${timeout}s)"
        return 1
    fi

    log_success "$container started"
    return 0
}

check_service_health() {
    local service=$1
    local health_command=${2:-}

    # If custom health command provided, use it
    if [[ -n "$health_command" ]]; then
        if eval "$health_command" &>/dev/null; then
            return 0
        else
            return 1
        fi
    fi

    # Default: Check systemd state
    local state
    state=$(systemctl show -p SubState --value "$service" 2>/dev/null || echo "unknown")

    if systemctl is-active --quiet "$service"; then
        if [[ "$state" == "running" ]] || [[ "$state" == "exited" ]]; then
            return 0
        fi
    fi
    return 1
}

# ============================================================================
# PHASE 1: System Initialization
# ============================================================================

phase_1_system_initialization() {
    log_info "=== Phase 1: System Initialization ==="
    local phase_start
    phase_start=$(date +%s)

    # Check for existing instance
    if [[ -f "$PID_FILE" ]]; then
        local old_pid
        old_pid=$(cat "$PID_FILE")
        if kill -0 "$old_pid" 2>/dev/null; then
            log_warn "Autostart already running (PID: $old_pid)"
            exit 0
        else
            log_warn "Found stale PID file from previous run"
            rm -f "$PID_FILE" "$LOCK_FILE"
        fi
    fi

    # Create PID file
    echo "$$" > "$PID_FILE"
    touch "$LOCK_FILE"
    log_success "Autostart process initialized (PID: $$)"

    if [[ "$ENABLE_PHASE_TIMING" == "true" ]]; then
        PHASE_TIMINGS[1]=$(($(date +%s) - phase_start))
    fi
}

# ============================================================================
# PHASE 2: System Optimization
# ============================================================================

phase_2_system_optimization() {
    log_info "=== Phase 2: System Optimization ==="
    local phase_start
    phase_start=$(date +%s)

    # Memory optimization example
    if [[ -w /proc/sys/vm/swappiness ]]; then
        echo 10 > /proc/sys/vm/swappiness
        log_success "Memory swappiness optimized (10)"
    fi

    # Other optimizations (examples)
    # - Disk scheduler tuning
    # - Network buffer sizes
    # - File descriptor limits

    if [[ "$ENABLE_PHASE_TIMING" == "true" ]]; then
        PHASE_TIMINGS[2]=$(($(date +%s) - phase_start))
    fi
}

# ============================================================================
# PHASE 3: Network Foundation
# ============================================================================

phase_3_network_foundation() {
    log_info "=== Phase 3: Network Foundation ==="
    local phase_start
    phase_start=$(date +%s)

    # Wait for NetworkManager
    local timeout=30
    local elapsed=0

    while ! systemctl is-active --quiet NetworkManager && [[ $elapsed -lt $timeout ]]; do
        sleep 1
        ((elapsed++))
    done

    if systemctl is-active --quiet NetworkManager; then
        log_success "NetworkManager active"
    else
        log_warn "NetworkManager not active after ${timeout}s"
        if [[ "$ENABLE_RECOVERY_MODE" == "true" ]]; then
            minimal_recovery_mode
        fi
    fi

    # Start core network services
    start_service "systemd-resolved.service" "systemd-resolved"

    if [[ "$ENABLE_PHASE_TIMING" == "true" ]]; then
        PHASE_TIMINGS[3]=$(($(date +%s) - phase_start))
    fi
}

# ============================================================================
# PHASE 4: Device-Specific Initialization
# ============================================================================

phase_4_device_specific() {
    log_info "=== Phase 4: Device-Specific Initialization ==="
    local phase_start
    phase_start=$(date +%s)

    # Examples:
    # - USB hardware initialization
    # - Storage volume validation (LVM, RAID)
    # - Hardware monitoring setup
    # - Peripheral device checks

    log_info "Device-specific initialization (customize here)"

    if [[ "$ENABLE_PHASE_TIMING" == "true" ]]; then
        PHASE_TIMINGS[4]=$(($(date +%s) - phase_start))
    fi
}

# ============================================================================
# PHASE 5: Storage & Filesystem Validation
# ============================================================================

phase_5_storage_validation() {
    log_info "=== Phase 5: Storage & Filesystem Validation ==="
    local phase_start
    phase_start=$(date +%s)

    # Check critical mounts
    local critical_mounts=("/" "/var" "/tmp")

    for mount in "${critical_mounts[@]}"; do
        if mountpoint -q "$mount"; then
            log_success "Mount point $mount is valid"
        else
            log_error "Mount point $mount is NOT mounted"
        fi
    done

    # Check disk space
    local root_usage
    root_usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')

    if [[ $root_usage -lt 90 ]]; then
        log_success "Disk space OK ($root_usage% used)"
    else
        log_warn "Disk space critical ($root_usage% used)"
    fi

    if [[ "$ENABLE_PHASE_TIMING" == "true" ]]; then
        PHASE_TIMINGS[5]=$(($(date +%s) - phase_start))
    fi
}

# ============================================================================
# PHASE 6: Core System Services
# ============================================================================

phase_6_core_services() {
    log_info "=== Phase 6: Core System Services ==="
    local phase_start
    phase_start=$(date +%s)

    # SSH (critical for remote management)
    start_service "ssh.service" "SSH Server" 3 15

    # Cron for scheduled tasks
    start_service "cron.service" "Cron Daemon"

    # Other core services
    # start_service "rsyslog.service" "Syslog"
    # start_service "systemd-timesyncd.service" "Time Sync"

    if [[ "$ENABLE_PHASE_TIMING" == "true" ]]; then
        PHASE_TIMINGS[6]=$(($(date +%s) - phase_start))
    fi
}

# ============================================================================
# PHASE 7: Network Services
# ============================================================================

phase_7_network_services() {
    log_info "=== Phase 7: Network Services ==="
    local phase_start
    phase_start=$(date +%s)

    # Examples:
    # - Firewall (ufw, nftables)
    # - VPN (WireGuard, OpenVPN)
    # - DNS server
    # - DHCP server

    log_info "Network services (customize here)"

    if [[ "$ENABLE_PHASE_TIMING" == "true" ]]; then
        PHASE_TIMINGS[7]=$(($(date +%s) - phase_start))
    fi
}

# ============================================================================
# PHASE 8: Application Layer
# ============================================================================

phase_8_application_layer() {
    log_info "=== Phase 8: Application Layer ==="
    local phase_start
    phase_start=$(date +%s)

    # Examples:
    # - Web server (nginx, apache)
    # - Application servers
    # - Message queues
    # - Cache services (Redis, Memcached)

    log_info "Application layer services (customize here)"

    if [[ "$ENABLE_PHASE_TIMING" == "true" ]]; then
        PHASE_TIMINGS[8]=$(($(date +%s) - phase_start))
    fi
}

# ============================================================================
# PHASE 9: Docker Stack
# ============================================================================

phase_9_docker_stack() {
    log_info "=== Phase 9: Docker Stack ==="
    local phase_start
    phase_start=$(date +%s)

    if [[ "$ENABLE_DOCKER_STACK" != "true" ]]; then
        log_info "Docker stack disabled (ENABLE_DOCKER_STACK=false)"
        if [[ "$ENABLE_PHASE_TIMING" == "true" ]]; then
            PHASE_TIMINGS[9]=0
        fi
        return 0
    fi

    # Start Docker daemon
    if systemctl list-units --all | grep -q "docker.service"; then
        start_service "docker.service" "Docker Daemon" 3 30

        if systemctl is-active --quiet docker; then
            log_success "Docker daemon running"

            # Wait for Docker socket
            local timeout=30
            local elapsed=0

            while [[ ! -S /var/run/docker.sock ]] && [[ $elapsed -lt $timeout ]]; do
                sleep 1
                ((elapsed++))
            done

            if [[ -S /var/run/docker.sock ]]; then
                log_success "Docker socket ready"

                # Start containers (if using docker-compose)
                # cd /opt/docker && docker-compose up -d || log_warn "Docker compose failed"

                # Or start individual containers
                # docker start container1 container2 || log_warn "Container start failed"
            else
                log_warn "Docker socket not available after ${timeout}s"
            fi
        fi
    else
        log_info "Docker not installed (skipping)"
    fi

    if [[ "$ENABLE_PHASE_TIMING" == "true" ]]; then
        PHASE_TIMINGS[9]=$(($(date +%s) - phase_start))
    fi
}

# ============================================================================
# PHASE 10: Service Verification
# ============================================================================

phase_10_service_verification() {
    log_info "=== Phase 10: Service Verification ==="
    local phase_start
    phase_start=$(date +%s)

    # Define critical services to verify
    local critical_services=(
        "ssh.service"
        "systemd-resolved.service"
        # Add your critical services here
    )

    local failed_count=0

    for service in "${critical_services[@]}"; do
        if systemctl list-units --all | grep -q "$service"; then
            if check_service_health "$service"; then
                log_success "$service is healthy"
            else
                log_error "$service is NOT healthy"
                ((failed_count++))
            fi
        fi
    done

    if [[ $failed_count -eq 0 ]]; then
        log_success "All critical services healthy"
    else
        log_warn "$failed_count critical service(s) unhealthy"
    fi

    if [[ "$ENABLE_PHASE_TIMING" == "true" ]]; then
        PHASE_TIMINGS[10]=$(($(date +%s) - phase_start))
    fi
}

# ============================================================================
# PHASE 11: Monitoring Services
# ============================================================================

phase_11_monitoring() {
    log_info "=== Phase 11: Monitoring Services ==="
    local phase_start
    phase_start=$(date +%s)

    # Start monitoring exporters
    # start_service "node_exporter.service" "Node Exporter"
    # start_service "cadvisor.service" "cAdvisor"

    # Start monitoring timers
    # start_timer "health-check.timer" "Health Check Timer"
    # start_timer "backup.timer" "Backup Timer"

    log_info "Monitoring services (customize here)"

    if [[ "$ENABLE_PHASE_TIMING" == "true" ]]; then
        PHASE_TIMINGS[11]=$(($(date +%s) - phase_start))
    fi
}

# ============================================================================
# PHASE 12: System Snapshot
# ============================================================================

phase_12_system_snapshot() {
    log_info "=== Phase 12: System Snapshot ==="
    local phase_start
    phase_start=$(date +%s)

    # Create post-boot snapshot (check installed path first, then relative)
    if [[ -x "/opt/linux-server-reboot-management/0-pre-reboot/system-snapshot.sh" ]]; then
        log_info "Creating post-reboot snapshot..."
        "/opt/linux-server-reboot-management/0-pre-reboot/system-snapshot.sh" post-reboot || log_warn "Snapshot failed"
    elif [[ -x "../0-pre-reboot/system-snapshot.sh" ]]; then
        log_info "Creating post-reboot snapshot (relative path)..."
        "../0-pre-reboot/system-snapshot.sh" post-reboot || log_warn "Snapshot failed"
    else
        log_info "Snapshot tool not available (skipping)"
    fi

    if [[ "$ENABLE_PHASE_TIMING" == "true" ]]; then
        PHASE_TIMINGS[12]=$(($(date +%s) - phase_start))
    fi
}

# ============================================================================
# PHASE 13: Boot Performance & Cleanup
# ============================================================================

phase_13_completion() {
    log_info "=== Phase 13: Boot Performance & Cleanup ==="
    local phase_start
    phase_start=$(date +%s)

    # Calculate boot time
    local boot_end_time
    boot_end_time=$(date +%s)
    local boot_duration=$((boot_end_time - BOOT_START_TIME))

    log_info "Total boot time: $boot_duration seconds"

    if [[ $boot_duration -le $MAX_BOOT_TIME ]]; then
        log_success "Boot completed within target ($MAX_BOOT_TIME seconds)"
    else
        log_warn "Boot exceeded target ($boot_duration > $MAX_BOOT_TIME seconds)"
    fi

    # Per-phase timing summary
    if [[ "$ENABLE_PHASE_TIMING" == "true" ]]; then
        log_info "Per-phase timings:"
        for phase in {1..13}; do
            if [[ -n "${PHASE_TIMINGS[$phase]:-}" ]]; then
                log_info "  Phase $phase: ${PHASE_TIMINGS[$phase]}s"
            fi
        done
    fi

    # Export metrics (if Prometheus node_exporter is available)
    if [[ "$ENABLE_PROMETHEUS_METRICS" == "true" ]] && [[ -d /var/lib/node_exporter/textfile_collector ]]; then
        cat > /var/lib/node_exporter/textfile_collector/boot.prom << EOF
# HELP last_boot_duration_seconds Last boot duration in seconds
# TYPE last_boot_duration_seconds gauge
last_boot_duration_seconds $boot_duration
# HELP last_boot_timestamp_seconds Timestamp of last successful boot
# TYPE last_boot_timestamp_seconds gauge
last_boot_timestamp_seconds $(date +%s)
EOF
        log_success "Boot metrics exported"
    fi

    # Mark completion
    touch /var/run/autostart.done
    rm -f "$LOCK_FILE"

    log_success "Autostart orchestration completed successfully"

    if [[ "$ENABLE_PHASE_TIMING" == "true" ]]; then
        PHASE_TIMINGS[13]=$(($(date +%s) - phase_start))
    fi
}

# ============================================================================
# EMERGENCY RECOVERY MODE
# ============================================================================

minimal_recovery_mode() {
    log_error "⚠️ EMERGENCY RECOVERY MODE ACTIVATED"

    # Attempt to establish minimal SSH access on primary interface
    # Customize interface name (eth0, enp0s3, etc.) for your system
    local primary_interface="eth0"
    local recovery_ip="192.168.1.100"  # Customize for your network

    if ip link show "$primary_interface" &>/dev/null; then
        log_info "Attempting minimal SSH setup on $primary_interface..."
        ip link set "$primary_interface" up 2>/dev/null || true
        ip addr add "${recovery_ip}/24" dev "$primary_interface" 2>/dev/null || true

        # Start SSH if not running
        if ! systemctl is-active --quiet ssh; then
            systemctl start ssh 2>/dev/null || true
        fi

        if ss -tln | grep -q "${recovery_ip}:22"; then
            log_success "✓ Emergency SSH available: ssh user@${recovery_ip}"
        fi
    fi

    # Write recovery status
    mkdir -p "$(dirname "$LOG_FILE")"
    cat > "$(dirname "$LOG_FILE")/recovery-mode.log" <<EOF
RECOVERY MODE ACTIVATED: $(date)
REASON: Critical system failure during autostart
SSH ACCESS: ${recovery_ip}:22 (${primary_interface})
LOG FILE: ${LOG_FILE}

NEXT STEPS:
  1. SSH into system: ssh user@${recovery_ip}
  2. Check logs: journalctl -u autostart.service
  3. Manual service start: systemctl start <service>
  4. Review: ${LOG_FILE}
EOF

    # Log to systemd
    if command -v logger >/dev/null 2>&1; then
        logger -t "autostart-recovery" "Recovery mode: Manual intervention required - SSH: ${recovery_ip}"
    fi

    log_error "Manual intervention required - check $(dirname "$LOG_FILE")/recovery-mode.log"

    # Clean up and exit with critical failure code
    rm -f "$PID_FILE" "$LOCK_FILE"
    exit 2
}

# ============================================================================
# SIGNAL HANDLERS
# ============================================================================

signal_cleanup() {
    local signal=$1
    log_warn "Autostart interrupted by signal $signal"
    rm -f "$LOCK_FILE" "$PID_FILE"
    # No exit here - let trap handler return naturally
}

cleanup_on_exit() {
    local rc=$?

    # Only perform cleanup on graceful shutdown
    if [[ "$GRACEFUL_SHUTDOWN" == "true" ]]; then
        rm -f "$LOCK_FILE" "$PID_FILE"
        log_success "Cleanup complete"
    fi

    return $rc
}

trap 'signal_cleanup INT' INT
trap 'signal_cleanup TERM' TERM
trap cleanup_on_exit EXIT

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    # Ensure log directory exists before first log call
    mkdir -p "$(dirname "$LOG_FILE")"

    log_info "=========================================="
    log_info "Autostart Orchestration - 13-Phase Boot"
    log_info "=========================================="

    phase_1_system_initialization
    phase_2_system_optimization
    phase_3_network_foundation
    phase_4_device_specific
    phase_5_storage_validation
    phase_6_core_services
    phase_7_network_services
    phase_8_application_layer
    phase_9_docker_stack
    phase_10_service_verification
    phase_11_monitoring
    phase_12_system_snapshot
    phase_13_completion

    log_info "=========================================="
    log_info "Boot orchestration complete"
    log_info "=========================================="

    # Set graceful shutdown flag before exit
    GRACEFUL_SHUTDOWN=true
}

# Run main
main "$@"
