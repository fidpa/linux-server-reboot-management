# Phase 2: Autostart Orchestration

13-phase boot orchestration template with dependency management and retry logic.

## The Problem

Default systemd boot order doesn't account for:
- Service dependencies (VPN before Docker)
- Hardware initialization (USB devices, storage)
- Application-specific startup sequences
- Health verification before marking "ready"

## The Solution

A 13-phase boot orchestration that:
1. Starts services in correct dependency order
2. Validates each phase before proceeding
3. Retries failed services with configurable retry delays
4. Tracks boot performance metrics
5. Enters recovery mode on critical failures

## Important: Examples vs. Production

### What's in This Directory

- **`autostart-template.sh`** (792 LOC): Full 13-phase reference implementation
- **`examples/*.sh`**: Focused use-case demonstrations (67-205 LOC each)

### What You Should Deploy

**For production, we recommend a single monolithic script** based on `autostart-template.sh`.

The examples are intentionally modular for learning, but combining them into one script offers:
- ✅ Atomic deployment (one file to manage)
- ✅ Better error handling (shared state)
- ✅ Faster execution (no file I/O)
- ✅ Simpler debugging (single trace)

### Our Production Setup

We maintain device-specific monolithic scripts:
- **Pi 5 Router**: 1443 LOC (network-heavy, Pi Zero fleet integration)
- **NAS Server**: 1139 LOC (Docker-heavy, 18 containers, LVM validation)

These scripts evolved from `autostart-template.sh` + relevant example patterns.

### Recommended Workflow

1. **Learn**: Study individual examples to understand patterns
2. **Experiment**: Test phases relevant to your setup
3. **Merge**: Copy `autostart-template.sh` and integrate needed phases
4. **Deploy**: Use the merged monolithic script in production

## Quick Start

```bash
# 1. Create installation directory and copy template
sudo mkdir -p /opt/linux-server-reboot-management/2-autostart
sudo cp autostart-template.sh /opt/linux-server-reboot-management/2-autostart/
sudo chmod +x /opt/linux-server-reboot-management/2-autostart/autostart-template.sh

# 2. Edit phases for your environment
sudo nano /opt/linux-server-reboot-management/2-autostart/autostart-template.sh

# 3. Install systemd service (path matches service file)
sudo cp ../config/systemd/autostart.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable autostart

# 4. Test (without reboot)
sudo /opt/linux-server-reboot-management/2-autostart/autostart-template.sh

# 5. Reboot to verify
sudo reboot
```

## 13-Phase Architecture

| Phase | Name | Purpose | Critical |
|-------|------|---------|----------|
| 1 | Initialization | Lock files, crash detection | Yes |
| 2 | System Optimization | Memory tuning, swappiness | No |
| 3 | Network Foundation | NetworkManager, DNS resolution | Yes |
| 4 | Device-Specific | Hardware init, USB, storage | No |
| 5 | Storage Validation | Mounts, disk space, LVM | No |
| 6 | Core Services | SSH, cron, time sync | Yes |
| 7 | Network Services | Firewall, VPN, DNS server | No |
| 8 | Application Layer | Web servers, app servers | No |
| 9 | Docker Stack | Docker daemon, containers | No |
| 10 | Service Verification | Health checks | No |
| 11 | Monitoring | Exporters, metrics | No |
| 12 | System Snapshot | Post-boot state capture | No |
| 13 | Completion | Metrics export, cleanup | No |

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `LOG_FILE` | `/var/log/autostart.log` | Log file location |
| `LOCK_FILE` | `/var/run/autostart.lock` | Lock file path |
| `PID_FILE` | `/var/run/autostart.pid` | PID file path |
| `MAX_BOOT_TIME` | `120` | Target boot time (seconds) |

### Feature Flags

Control optional features via environment variables:

| Flag | Default | Description |
|------|---------|-------------|
| `ENABLE_PROMETHEUS_METRICS` | `true` | Export boot metrics to Prometheus |
| `ENABLE_RECOVERY_MODE` | `true` | Activate emergency recovery on critical failures |
| `ENABLE_DOCKER_STACK` | `true` | Enable Docker container management |
| `ENABLE_PHASE_TIMING` | `true` | Track per-phase timing metrics |

**Example:**
```bash
# Disable Docker and Prometheus
export ENABLE_DOCKER_STACK=false
export ENABLE_PROMETHEUS_METRICS=false
/opt/autostart/autostart-template.sh
```

## Customization

### Minimal Setup (3 Phases)

```bash
# For simple setups with <10 services
main() {
    phase_6_core_services
    phase_9_docker_stack
    phase_13_completion
}
```

### Basic Setup (5 Phases)

```bash
# For typical Docker hosts
main() {
    phase_1_system_initialization
    phase_3_network_foundation
    phase_6_core_services
    phase_9_docker_stack
    phase_13_completion
}
```

### Production Setup (All 13 Phases)

Use the full template for:
- Network gateways
- Multi-service hosts
- Compliance environments

## Helper Functions

### start_service

Start a systemd service with retry logic and health verification.

```bash
start_service "nginx.service" "Web Server" 3 15
#             ^service        ^name       ^retries ^timeout
```

**Parameters:**
- `service`: Systemd service name (with or without .service)
- `friendly_name`: Human-readable name for logs (default: service name)
- `max_retries`: Number of retry attempts (default: 2)
- `timeout`: Timeout per attempt in seconds (default: 10)

**Features:**
- LoadState check (more reliable than list-units)
- SubState verification (running/exited)
- Automatic retry with configurable delay (default: 3s between attempts)
- Skip silently if service doesn't exist

### start_timer

Start a systemd timer with existence check.

```bash
start_timer "backup.timer" "Backup Timer"
#           ^timer         ^name
```

**Parameters:**
- `timer`: Systemd timer name (with or without .timer)
- `friendly_name`: Human-readable name for logs

### wait_for_service

Wait for a service to become active with timeout.

```bash
wait_for_service "docker.service" 30
#                ^service         ^timeout
```

**Parameters:**
- `service`: Systemd service name
- `timeout`: Maximum wait time in seconds (default: 30)

**Returns:** 0 if active, 1 on timeout

### start_container

Start a Docker container with health check modes.

```bash
start_container "postgres" "healthy" 60
#               ^name      ^mode     ^timeout
```

**Parameters:**
- `container`: Container name
- `health_mode`: Health check mode (default: started)
  - `healthy`: Wait for Docker health check to pass
  - `started`: Wait for container start only
  - `none`: No wait
- `timeout`: Health check timeout in seconds (default: 60)

**Features:**
- Parallel startup support (background with `&`)
- Health check polling with timeout
- Automatic restart on unhealthy state

### check_service_health

Check service health with optional custom command.

```bash
# Default: Check systemd state
check_service_health "nginx"

# Custom: Use health command
check_service_health "postgres" "pg_isready -q"
```

**Parameters:**
- `service`: Service name
- `health_command`: Optional custom health check command

**Returns:** 0 if healthy, 1 if unhealthy

## Failure Handling

| Phase | On Failure | Action |
|-------|------------|--------|
| 1-3 | Critical | Enter recovery mode (SSH only) |
| 4-5 | Warning | Continue with degraded state |
| 6 | Critical | SSH required, enter recovery |
| 7-8 | Warning | Log and continue |
| 9 | Warning | Mark containers as failed |
| 10-13 | Info | Log only |

### Recovery Mode

Automatically activated on critical failures (Phase 1, 3, 6):

**Features:**
- Automatic SSH setup on primary interface
- Emergency IP configuration
- Recovery log with next steps
- Exit code 2 (distinguishable from general errors)

**Customization:**
Edit `minimal_recovery_mode()` to configure:
- Primary network interface (default: eth0)
- Recovery IP address (default: 192.168.1.100)
- SSH access credentials

**Recovery Log:** `<log_dir>/recovery-mode.log`

**Disable:** `export ENABLE_RECOVERY_MODE=false`

## Performance Targets

| Environment | Target | Phases |
|-------------|--------|--------|
| Development | <180s | 5-7 |
| Staging | <120s | 9-11 |
| Production | <90s | All 13 |

## Monitoring

### View Boot Logs

```bash
# Current boot
journalctl -u autostart -b

# Previous boot
journalctl -u autostart -b -1

# Phase timings
grep "Phase" /var/log/autostart.log
```

### Prometheus Metrics

```bash
# Exported to textfile collector
cat /var/lib/node_exporter/textfile_collector/autostart.prom

# Metrics:
# last_boot_duration_seconds 89
# boot_success_total 1642346400
```

## Files

| File | Purpose | Lines | Use Case |
|------|---------|-------|----------|
| `autostart-template.sh` | Full 13-phase template | ~792 | Production baseline |
| `examples/autostart-minimal.sh` | Minimal implementation | ~70 | Learning/simple setups |
| `examples/autostart-docker-stack.sh` | Multi-tier Docker startup | ~167 | Container platforms |
| `examples/autostart-network-gateway.sh` | Network foundation | ~205 | Router/gateway systems |
| `examples/autostart-database-server.sh` | Database-centric startup | ~200 | DB servers |

## See Also

- [../docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) - 13-phase design rationale
- [../docs/TEMPLATES.md](../docs/TEMPLATES.md) - Customization guide
- [examples/](examples/) - Ready-to-use examples

---

**License**: MIT | **Author**: Marc Allgeier ([@fidpa](https://github.com/fidpa))
