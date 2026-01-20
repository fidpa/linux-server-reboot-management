# 3-Phase Core Workflow

## ⚡ TL;DR

3-phase workflow: graceful shutdown (stop containers), autostart (orchestrated boot), verification (health checks). Optional pre-reboot snapshots.

---

## Table of Contents

- [Overview](#overview)
- [Optional Phase 0: Pre-Reboot Snapshots](#optional-phase-0-pre-reboot-snapshots)
- [Phase 1: Graceful Shutdown](#phase-1-graceful-shutdown)
- [Phase 2: Autostart](#phase-2-autostart)
- [Phase 3: Verification](#phase-3-verification)
- [Complete Workflow Example](#complete-workflow-example)
- [Production Best Practices](#production-best-practices)
- [Troubleshooting](#troubleshooting)
- [See Also](#see-also)

---

Complete guide to the production reboot management workflow.

## Overview

Production server reboots require careful orchestration across **three core phases (plus optional pre-reboot snapshots)**:

1. **Pre-Reboot**: Capture system state baseline
2. **Graceful Shutdown**: Stop services cleanly
3. **Autostart**: Orchestrated service restoration
4. **Verification**: Validate system recovery

The three core phases are critical. Phase 0 (snapshots) is optional but recommended for compliance. Skipping core phases risks data loss, service unavailability, or undetected failures.

---

## Optional Phase 0: Pre-Reboot Snapshots

⚠️ **This phase is OPTIONAL** - The core workflow (Phases 1-3) works without it. Enable for compliance/audit requirements.

**Goal**: Capture complete system state baseline for comparison

**Script**: `0-pre-reboot/system-snapshot.sh`

**Customization Required**: This script needs adaptation for your specific environment (device-specific metrics, custom services, etc.).

**What to Capture**:
- System information (kernel, OS, uptime, load)
- systemd services (running, failed, enabled)
- Docker containers (names, states, health)
- Network configuration (interfaces, routes, gateway)
- Storage mounts and disk usage

**Usage**:
```bash
cd 0-pre-reboot/
./system-snapshot.sh pre-reboot

# Output: /var/log/snapshots/pre-reboot-YYYYMMDD-HHMMSS.json
```

**Custom Metrics** (optional):
```bash
# Enable extensions for device-specific metrics
ENABLE_EXTENSIONS=true ./examples/snapshot-extensions-example.sh pre-reboot
```

**Timing**: Run 1-5 minutes before reboot

**Why This Matters**:
- Baseline for post-reboot comparison
- Audit trail for troubleshooting
- Compliance documentation

---

## Phase 1: Graceful Shutdown

**Goal**: Stop Docker containers gracefully before system shutdown

**Script**: `1-graceful-shutdown/docker-graceful-shutdown.sh`

**What Happens**:
1. Enumerate all running Docker containers
2. Stop each container with 30s timeout (SIGTERM → SIGKILL)
3. Stop Docker daemon
4. Flush filesystem buffers (`sync`)

**systemd Integration**:
```ini
[Unit]
Description=Docker Graceful Shutdown Hook
Conflicts=shutdown.target halt.target reboot.target
Before=shutdown.target halt.target reboot.target

[Service]
Type=oneshot
ExecStart=/bin/true
ExecStop=/opt/docker-shutdown/docker-graceful-shutdown.sh
TimeoutStopSec=120

[Install]
WantedBy=multi-user.target
```

**Critical Pattern**: `Conflicts=shutdown.target`

Without `Conflicts=`, `ExecStop` NEVER runs during shutdown. `Before=` alone is NOT enough!

**Why This Matters**:
- PostgreSQL needs checkpoint time
- Redis needs AOF/RDB persistence
- Applications need request completion
- Prevents data corruption

**Reboot Command**:
```bash
# Standard reboot (graceful shutdown runs automatically)
sudo reboot
```

---

## Phase 2: Autostart

**Goal**: Orchestrated service restoration in dependency order

**Script**: `2-autostart/autostart-template.sh` (customize for your setup)

**13-Phase Architecture**:
1. **System Initialization** - Logging, lock files, crash detection
2. **System Optimization** - Memory tuning (swappiness), disk scheduler
3. **Network Foundation** - NetworkManager, systemd-resolved
4. **Device-Specific** - Hardware init, USB recovery, storage validation
5. **Storage Validation** - Mount points, disk space, LVM/RAID
6. **Core Services** - SSH, cron, time sync
7. **Network Services** - Firewall, VPN, DNS, DHCP
8. **Application Layer** - Web servers, application servers, caches
9. **Docker Stack** - Docker daemon, container orchestration
10. **Service Verification** - Health checks for critical services
11. **Monitoring** - Exporters, timers, scheduled tasks
12. **System Snapshot** - Post-reboot state capture
13. **Completion** - Performance metrics, cleanup

**systemd Service**:
```ini
[Unit]
Description=Autostart Orchestration
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/opt/autostart/autostart-template.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

**Customization**:
- Start with `autostart-minimal.sh` for simple setups
- Use `autostart-template.sh` for production environments
- See `TEMPLATES.md` for adaptation guide

**Why This Matters**:
- Dependency-aware startup order
- Retry logic for transient failures
- Health verification before completion
- Performance tracking

---

## Phase 3: Verification

**Goal**: Validate complete system recovery

**Scripts**:
- `3-verification/post-reboot-check.sh` - Automated health checks
- `3-verification/snapshot-compare.py` - Pre/post comparison

### 4.1 Post-Reboot Health Check

**Run Time**: 5-10 minutes after reboot (allow container startup time)

```bash
cd 3-verification/
./post-reboot-check.sh
```

**Checks Performed**:
1. Graceful shutdown hook execution (journalctl verification)
2. All containers running (no 'exited' state)
3. Container health checks (Docker health status)
4. Network connectivity (gateway, DNS, internet)
5. Critical services (SSH, Docker, custom services)

**Output Formats**:
- Terminal: Colored output with ✓/✗ indicators
- JSON: `--json` flag for CI/CD integration
- Report: `/var/log/reboot-reports/reboot-check-*.txt`

**Exit Codes**:
- 0: All checks passed
- 1: Graceful shutdown hook didn't run
- 2: Containers not running
- 3: Health checks failing
- 4: Network issues

### 4.2 Snapshot Comparison

**Compares pre-reboot and post-reboot snapshots**:

```bash
cd 3-verification/
./snapshot-compare.py --auto-latest

# Or specify snapshots manually
./snapshot-compare.py \
    /var/log/snapshots/pre-reboot-20260116-120000.json \
    /var/log/snapshots/post-reboot-20260116-120500.json
```

**Comparisons**:
- **Services**: Stopped/started/failed services
- **Docker**: Missing/changed container states
- **Network**: Gateway changes, connectivity issues
- **System**: Kernel changes, disk space warnings

**Output**:
```
=== SNAPSHOT COMPARISON ===
Pre-reboot:  /var/log/snapshots/pre-reboot-20260116-120000.json
Post-reboot: /var/log/snapshots/post-reboot-20260116-120500.json

=== SERVICE COMPARISON ===
✓ All services maintained their state

=== DOCKER CONTAINER COMPARISON ===
✓ All containers maintained their state

=== NETWORK COMPARISON ===
✓ Network configuration maintained

=== SYSTEM COMPARISON ===
✓ System metrics healthy

=== SUMMARY ===
Pre-reboot time:  20260116-120000
Post-reboot time: 20260116-120500
✅ System recovered successfully after reboot
```

---

## Complete Workflow Example

```bash
# === OPTIONAL PHASE 0: PRE-REBOOT ===
cd /opt/reboot-management/0-pre-reboot
./system-snapshot.sh pre-reboot
# Output: /var/log/snapshots/pre-reboot-20260116-120000.json

# === PHASE 1: GRACEFUL SHUTDOWN ===
# (Happens automatically during reboot via systemd service)
sudo reboot

# === PHASE 2: AUTOSTART ===
# (Happens automatically during boot via systemd service)
# Monitor: journalctl -u autostart.service -f

# === PHASE 3: VERIFICATION ===
# (Wait 5-10 minutes after boot)

# 4.1 Health Check
cd /opt/reboot-management/3-verification
./post-reboot-check.sh

# 4.2 Snapshot Comparison
./snapshot-compare.py --auto-latest

# 4.3 Manual Verification (optional)
systemctl --failed               # Check for failed services
docker ps -a                     # Verify all containers running
journalctl -xe                   # Review system logs
```

---

## Production Best Practices

### 1. Consider Pre-Reboot Snapshots (Optional)
**Why**: Provides baseline for recovery verification and compliance/audit trail
**When**: 1-5 minutes before reboot
**Storage**: Keep last 7 days of snapshots

### 2. Test Graceful Shutdown Hook
**Before production use**:
```bash
# Test without rebooting
sudo systemctl stop docker-graceful-shutdown.service
journalctl -u docker-graceful-shutdown -n 50
```

### 3. Customize Autostart for Your Environment
- Start with `autostart-minimal.sh`
- Add phases incrementally
- Test each phase independently
- Document device-specific requirements

### 4. Wait Before Verification
**Containers need startup time**:
- Databases: 30-60 seconds
- Web applications: 10-30 seconds
- Monitoring exporters: 5-10 seconds

**Recommended wait**: 5 minutes after boot completion

### 5. Automate Verification
**Run post-reboot-check via systemd timer**:
```ini
[Unit]
Description=Post-Reboot Verification Timer
Requires=multi-user.target
After=multi-user.target

[Timer]
OnBootSec=5min
Unit=post-reboot-check.service

[Install]
WantedBy=timers.target
```

### 6. Keep Audit Trail
**Log retention**:
- Snapshots: 7 days
- Reboot reports: 30 days
- systemd journal: 14 days

**Compliance**: Meets SOC 2, ISO 27001 change management requirements

---

## Troubleshooting

### Problem: Graceful shutdown hook didn't run

**Symptoms**:
- `post-reboot-check.sh` reports "Graceful shutdown hook did NOT execute"
- Docker containers show unclean shutdown in logs

**Diagnosis**:
```bash
# Check service status
systemctl status docker-graceful-shutdown.service

# Check if service is enabled
systemctl is-enabled docker-graceful-shutdown.service
```

**Fix**:
```bash
# Ensure service is enabled
sudo systemctl enable docker-graceful-shutdown.service

# Verify Conflicts= directive in service file
grep "Conflicts=" /etc/systemd/system/docker-graceful-shutdown.service
```

### Problem: Containers not restarting after reboot

**Symptoms**:
- `docker ps` shows containers in 'exited' state
- snapshot-compare shows missing containers

**Diagnosis**:
```bash
# Check restart policy
docker inspect <container> --format '{{.HostConfig.RestartPolicy.Name}}'
```

**Fix**:
- **restart=unless-stopped** won't auto-start after reboot
- Change to **restart=always** for production containers:
```bash
docker update --restart=always <container>
```

### Problem: Autostart times out

**Symptoms**:
- Boot hangs or takes >5 minutes
- systemctl shows autostart.service failed

**Diagnosis**:
```bash
journalctl -u autostart.service -n 200
```

**Common causes**:
- Network service waiting for unreachable resource
- Container failing health check repeatedly
- Storage mount timeout

**Fix**:
- Add timeouts to service start commands
- Reduce retry attempts for non-critical services
- Move problematic services to later phase

---

## See Also

- [ARCHITECTURE.md](ARCHITECTURE.md) - Deep dive into `Conflicts=` pattern and 13-phase model
- [TEMPLATES.md](TEMPLATES.md) - How to customize templates for your environment
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues and solutions

---

**Status**: Production-Ready
**Tested**: Multiple environments (ARM, x86_64, Ubuntu, Debian)
**Last Updated**: January 2026
