# Architecture Deep Dive

## ⚡ TL;DR

systemd shutdown hooks require `Conflicts=shutdown.target` to trigger `ExecStop` before reboot; `Before=` alone does not work.

---

Understanding how graceful shutdown hooks work with systemd.

## The Core Problem

When you run `sudo reboot`, systemd:
1. Activates `reboot.target`
2. Stops all services in dependency order
3. Kills remaining processes
4. Unmounts filesystems
5. Reboots

**Problem**: Docker containers are killed in step 3, without graceful shutdown.

Result:
- PostgreSQL loses in-flight transactions
- Redis loses unsaved cache data
- Applications crash mid-request
- File corruption risk

## The Solution: Shutdown Hooks

A **shutdown hook** is a systemd service that:
1. Stays "active" during normal operation (does nothing)
2. Runs its `ExecStop` command BEFORE shutdown
3. Stops Docker containers gracefully
4. Allows system to continue shutdown afterwards

## The Critical Pattern: `Conflicts=`

### Common Mistake

Most guides show this:

```ini
[Unit]
Before=shutdown.target

[Service]
ExecStop=/path/to/shutdown-script.sh
```

**This DOES NOT WORK!**

Why? `Before=` only controls **ordering** (when service stops relative to shutdown.target).
It does **NOT** trigger the service to stop.

Result: ExecStop NEVER runs, containers die ungracefully.

### Correct Pattern

```ini
[Unit]
Conflicts=shutdown.target reboot.target halt.target
Before=shutdown.target reboot.target halt.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true
ExecStop=/path/to/shutdown-script.sh
```

**Why this works**:

1. **`Conflicts=shutdown.target`** - Tells systemd: "If shutdown.target activates, STOP this service"
2. **`Before=shutdown.target`** - Tells systemd: "Stop this service BEFORE starting shutdown.target"
3. **`Type=oneshot` + `RemainAfterExit=yes`** - Service stays "active" after ExecStart completes
4. **`ExecStop=`** - Runs when service is stopped (triggered by Conflicts=)

### Timeline

```
User runs: sudo reboot
  ↓
systemd activates reboot.target
  ↓
Conflicts= triggers service stop ← KEY!
  ↓
ExecStop runs (graceful shutdown script)
  ↓
Containers stop gracefully (30s timeout each)
  ↓
ExecStop completes
  ↓
shutdown.target proceeds
  ↓
System reboots
```

## Service Configuration Breakdown

```ini
[Unit]
Description=Docker Graceful Shutdown Hook
Documentation=https://github.com/fidpa/linux-server-reboot-management
DefaultDependencies=no  # Don't pull in default dependencies

# CRITICAL: Forces service to stop when shutdown/reboot/halt activates
Conflicts=shutdown.target reboot.target halt.target

# Ensures ExecStop runs BEFORE shutdown begins
Before=shutdown.target reboot.target halt.target

# Wait for Docker to be ready (optional but recommended)
After=network.target docker.service

[Service]
# oneshot: Service runs once and exits
Type=oneshot

# RemainAfterExit: Service stays "active" even after ExecStart finishes
# This is CRITICAL - without it, ExecStop won't run!
RemainAfterExit=yes

# User that runs the scripts
User=root

# ExecStart: Must complete successfully for service to be "active"
# We use /bin/true (always succeeds) since we don't need startup logic
ExecStart=/bin/true

# ExecStop: The actual shutdown hook
# Runs when service is stopped (triggered by Conflicts=)
ExecStop=/opt/linux-server-reboot-management/docker-graceful-shutdown.sh

# Timeout for ExecStop
# Must be long enough for all containers to stop gracefully
# Formula: (container_count * container_timeout) + buffer
# Example: 20 containers * 30s + 30s = 630s
TimeoutStopSec=120

# Logging
StandardOutput=journal
StandardError=journal

[Install]
# Start service automatically at boot
WantedBy=multi-user.target
```

## Container Stop Flow

```
ExecStop runs shutdown script
  ↓
Script lists running containers
  ↓
For each container:
  docker stop --time 30 <container>
    ↓
  Docker sends SIGTERM to container
    ↓
  Container has 30 seconds to gracefully shutdown
    ↓
  If still running after 30s: Docker sends SIGKILL
  ↓
All containers stopped
  ↓
Docker service stopped (optional)
  ↓
Filesystem buffers flushed (sync)
  ↓
ExecStop completes (exit 0)
  ↓
systemd proceeds with shutdown
```

## Key Patterns

### Pattern 1: Graceful Timeout

```bash
# Good: 30s timeout for databases
docker stop --time 30 postgres

# Bad: No timeout (default 10s, too short!)
docker stop postgres
```

**Why 30s?**
- PostgreSQL needs time to checkpoint transactions
- Redis needs time to flush AOF/RDB
- Applications need time to drain connections

### Pattern 2: Error Handling

```bash
# Good: Explicit exit code capture
docker stop --time 30 "$container" 2>&1 | tee -a "$LOG_FILE"
local exit_code="${PIPESTATUS[0]}"

if [[ $exit_code -eq 0 ]]; then
    ((stopped_containers++))
else
    ((failed_containers++))
fi

# Bad: Assumes success
docker stop "$container"
```

**Why explicit?**
- Some containers may fail to stop gracefully
- Don't want to block shutdown if a few containers fail
- Need to log failures for troubleshooting

### Pattern 3: Always Exit 0

```bash
# At end of shutdown script
return 0  # Even if some containers failed!
```

**Why?**
- Don't block system shutdown
- Partial shutdown is better than no shutdown
- Log failures for later investigation

## Restart Policies

Container restart policy affects post-reboot behavior:

| Policy | After Reboot | Use Case |
|--------|--------------|----------|
| `restart: always` | ✅ Auto-starts | Production services |
| `restart: unless-stopped` | ❌ Stays stopped | Test containers |
| `restart: on-failure` | ❌ Stays stopped | Batch jobs |
| `restart: no` | ❌ Stays stopped | One-time tasks |

**Recommendation**: Use `restart: always` for production containers.

```yaml
services:
  postgres:
    restart: always  # ✅ Best for production
```

**Why?**
- Graceful shutdown hook stops containers
- `unless-stopped` remembers "stopped" state
- Container won't restart after reboot
- `always` ignores previous state, always restarts

## Security Considerations

### Service User

**Options**:

1. **Run as root** (simplest)
   ```ini
   User=root
   ```
   - ✅ Full Docker access
   - ❌ Security risk

2. **Run as docker group user** (recommended)
   ```ini
   User=admin
   ```
   ```bash
   sudo usermod -aG docker admin
   ```
   - ✅ Docker socket access
   - ✅ Limited privileges
   - ✅ Production-ready

3. **Run with systemd hardening**
   ```ini
   User=admin
   ProtectSystem=strict
   ReadWritePaths=/var/log
   NoNewPrivileges=true
   ```
   - ✅ Maximum security
   - ⚠️ Requires careful path configuration

### Log File Permissions

```bash
# Create log directory with proper ownership
sudo mkdir -p /var/log/docker-graceful-shutdown
sudo chown admin:admin /var/log/docker-graceful-shutdown
sudo chmod 755 /var/log/docker-graceful-shutdown

# Log file
sudo touch /var/log/docker-graceful-shutdown/shutdown.log
sudo chown admin:admin /var/log/docker-graceful-shutdown/shutdown.log
sudo chmod 644 /var/log/docker-graceful-shutdown/shutdown.log
```

## Performance Considerations

### Parallel vs Sequential Shutdown

**Current implementation: Sequential**

```bash
while IFS= read -r container; do
    docker stop --time 30 "$container"
done
```

**Pros**:
- Simple, predictable
- Easy to debug
- Logs are sequential

**Cons**:
- Slower for many containers
- 10 containers * 30s = 300s total

**Alternative: Parallel**

```bash
for container in $running_containers; do
    docker stop --time 30 "$container" &
done
wait
```

**Pros**:
- Much faster (30s total regardless of count)
- Better for large stacks

**Cons**:
- Harder to debug
- More complex error handling
- Logs are interleaved

**Recommendation**: Use sequential for <20 containers, parallel for 20+.

## Testing Strategy

### 1. Dry-Run Test

```bash
sudo systemctl stop docker-graceful-shutdown
journalctl -u docker-graceful-shutdown -n 50
```

Verifies:
- ExecStop runs
- Containers stop
- Logging works

### 2. Reboot Test

```bash
sudo reboot
# After reboot:
journalctl -b -1 -u docker-graceful-shutdown
docker ps
```

Verifies:
- Hook runs during reboot
- Containers restart (if restart: always)
- No data corruption

### 3. Load Test

```bash
# Start many containers
for i in {1..30}; do
    docker run -d --name test$i nginx
done

# Test graceful shutdown
sudo systemctl stop docker-graceful-shutdown

# Check timing
journalctl -u docker-graceful-shutdown -n 100 | grep "completed"
```

Verifies:
- Performance with many containers
- Timeout settings adequate

## Origin Story: The `Conflicts=` Discovery

This pattern was discovered through incident report analysis:

**Original Problem** (Production Docker Host):
- Docker graceful shutdown service configured
- `Before=shutdown.target` set
- ExecStop never ran during reboots

**Investigation**:
- Checked systemd documentation
- Found: `Before=` only controls ordering, NOT activation
- Discovery: `Conflicts=` forces service to stop

**Fix**:
- Added `Conflicts=shutdown.target reboot.target halt.target`
- ExecStop now runs reliably

**Validation**:
- Tested on network gateway (6 containers)
- Tested on Docker host (38 containers)
- 100% success rate across multiple reboots

## References

- [systemd.unit(5)](https://www.freedesktop.org/software/systemd/man/systemd.unit.html) - Conflicts= documentation
- [systemd.service(5)](https://www.freedesktop.org/software/systemd/man/systemd.service.html) - Service types
- [Docker stop documentation](https://docs.docker.com/engine/reference/commandline/stop/) - Graceful shutdown

## Summary

**Key Takeaways**:

1. ✅ **Use `Conflicts=shutdown.target`** - This is NOT optional
2. ✅ **Use `Type=oneshot` + `RemainAfterExit=yes`** - Required pattern
3. ✅ **Set `TimeoutStopSec=` appropriately** - Based on container count
4. ✅ **Use `restart: always`** - For automatic container restart
5. ✅ **Test with `systemctl stop`** - Before rebooting production

**The Pattern**:
```ini
Conflicts=shutdown.target reboot.target halt.target
Before=shutdown.target reboot.target halt.target
```

**Without `Conflicts=`**: Hook never runs ❌
**With `Conflicts=`**: Hook runs reliably ✅

---

## 13-Phase Boot Orchestration

The autostart template demonstrates a **13-phase boot orchestration pattern** used in production environments.

### Why 13 Phases?

**Dependency ordering**: Services must start in correct order
**Fault isolation**: Each phase can fail independently
**Performance tracking**: Measure per-phase timing
**Incremental testing**: Test one phase at a time

### Phase Architecture

```
Boot Start
  ↓
Phase 1: System Initialization (Lock files, crash detection)
  ↓
Phase 2: System Optimization (Memory tuning, swappiness)
  ↓
Phase 3: Network Foundation (NetworkManager, DNS)
  ↓
Phase 4: Device-Specific (Hardware init, USB, storage)
  ↓
Phase 5: Storage Validation (Mounts, disk space, LVM)
  ↓
Phase 6: Core Services (SSH, cron, time sync)
  ↓
Phase 7: Network Services (Firewall, VPN, DNS server)
  ↓
Phase 8: Application Layer (Web servers, app servers)
  ↓
Phase 9: Docker Stack (Docker daemon, containers)
  ↓
Phase 10: Service Verification (Health checks)
  ↓
Phase 11: Monitoring (Exporters, timers)
  ↓
Phase 12: System Snapshot (Post-boot state capture)
  ↓
Phase 13: Completion (Metrics, cleanup)
  ↓
Boot Complete
```

### Phase Design Principles

#### 1. Foundation First
**Phases 1-3** establish system foundation:
- Logging infrastructure
- Memory optimization
- Network connectivity

**Why**: Later phases depend on these fundamentals

#### 2. Hardware Before Services
**Phases 4-5** validate hardware:
- USB devices available
- Storage volumes mounted
- Disk space sufficient

**Why**: Services fail if hardware isn't ready

#### 3. Core Before Application
**Phases 6-8** follow dependency order:
- Core services (SSH, cron)
- Network services (firewall, VPN)
- Application services (web, apps)

**Why**: Applications need core services running

#### 4. Docker Last
**Phase 9** starts Docker stack:
- Docker daemon
- Container orchestration
- Health checks

**Why**: Containers are highest-level services

#### 5. Verify, Monitor, Snapshot
**Phases 10-12** ensure completeness:
- Verify critical services healthy
- Start monitoring infrastructure
- Capture post-boot state

**Why**: Know if boot succeeded before marking complete

#### 6. Metrics and Cleanup
**Phase 13** finalizes boot:
- Calculate boot duration
- Export Prometheus metrics
- Mark completion
- Clean up lock files

**Why**: Performance tracking and proper cleanup

### Customization Strategy

**Start minimal, add incrementally**:

1. **Minimal** (3 phases):
   - Phase 6: Core Services
   - Phase 9: Docker Stack
   - Phase 13: Completion

2. **Basic** (5 phases):
   - Phase 1: Initialization
   - Phase 3: Network Foundation
   - Phase 6: Core Services
   - Phase 9: Docker Stack
   - Phase 13: Completion

3. **Production** (13 phases):
   - Full template with all phases

**See**: `TEMPLATES.md` for customization guide

### Performance Targets

| Environment | Target Boot Time | Typical Phases Used |
|-------------|------------------|---------------------|
| Development | <180s | 5-7 phases |
| Staging | <120s | 9-11 phases |
| Production | <90s | All 13 phases |

**Bottlenecks**:
- Docker container startup: 30-60s
- Database initialization: 20-30s
- Network service readiness: 10-20s

### Boot Performance Tracking

**Metrics exported** (Prometheus format):
```
# Boot duration
last_boot_duration_seconds 89

# Boot success counter
boot_success_total 1642346400

# Per-phase timing (advanced)
boot_phase_duration_seconds{phase="6_core_services"} 12
boot_phase_duration_seconds{phase="9_docker_stack"} 45
```

**Monitoring**:
```bash
# View phase timings
journalctl -u autostart.service | grep "Phase"

# Boot duration
journalctl -u autostart.service | grep "Total boot time"
```

### Real-World Example

**Production Gateway** (ARM-based, 16GB RAM):
- **Phase 1-3**: Network foundation (15s)
- **Phase 4**: USB Ethernet recovery (5s)
- **Phase 5**: Storage validation (3s)
- **Phase 6-7**: SSH, firewall, VPN (20s)
- **Phase 9**: Docker stack (6 containers, 35s)
- **Phase 10-13**: Verification, monitoring, snapshot (12s)
- **Total**: 90 seconds

**Docker Host** (x86_64, 32GB RAM):
- **Phase 1-3**: Foundation (8s)
- **Phase 4-5**: LVM validation, storage (10s)
- **Phase 6-8**: Core + network + app services (25s)
- **Phase 9**: Docker stack (38 containers, 60s)
- **Phase 10-13**: Verification, monitoring (17s)
- **Total**: 120 seconds

### Failure Handling

**Per-Phase Failure Strategy**:

| Phase | Failure Impact | Recovery Action |
|-------|----------------|-----------------|
| 1-3 | ❌ CRITICAL | Enter minimal recovery mode (SSH only) |
| 4-5 | ⚠️ WARNING | Continue with degraded functionality |
| 6 | ❌ CRITICAL | SSH required for remote management |
| 7-8 | ⚠️ WARNING | Log failures, continue boot |
| 9 | ⚠️ WARNING | Continue, mark containers as failed |
| 10-13 | ℹ️ INFO | Log only, don't block completion |

**Minimal Recovery Mode**:
```bash
minimal_recovery_mode() {
    log_error "Critical boot failure, entering recovery mode"

    # Ensure SSH is running
    systemctl start ssh.service

    # Mark boot as failed
    touch /var/run/autostart.failed

    # Exit without blocking
    exit 0
}
```

### Testing Phases

**Test individual phases**:
```bash
# Source the autostart script functions
source autostart-template.sh

# Test specific phase
phase_6_core_services

# Check result
echo $?
```

**Test full boot**:
```bash
# Enable service
sudo systemctl enable autostart.service

# Reboot
sudo reboot

# After reboot, check logs
journalctl -u autostart.service -n 200
```

---

## Design Philosophy: Modular Examples, Monolithic Production

### The Paradox

This repository provides **modular examples** but recommends **monolithic deployment**. Why?

### Examples are for Learning

The 4 example scripts demonstrate:
- **Minimal**: Core concepts (67 LOC - digestible)
- **Docker Stack**: Container orchestration patterns
- **Network Gateway**: Routing/firewall patterns
- **Database Server**: DB-centric patterns

Each example is **intentionally focused** on a specific use case to make learning easier.

### Production is Monolithic

Our actual production scripts (not in this public repo) are:
- **Pi 5 Router**: Single 1443-line script
  - All 13 phases
  - Device-specific checks (vcgencmd, Pi Zero fleet)
  - Nextcloud integration via Vaultwarden
  - Emergency recovery modes

- **NAS Server**: Single 1139-line script
  - All 13 phases
  - LVM validation
  - Docker 18-container stack
  - Nextcloud permission automation

### Why Monolithic for Production?

1. **Atomic Deployment**
   - One file to edit/test/deploy
   - No partial deployments
   - Single version control unit

2. **Better Error Context**
   - All state in one process
   - Shared variables across phases
   - Unified error handling

3. **Performance**
   - No file I/O between phases
   - Faster execution (no subprocess spawning)
   - Lower memory footprint

4. **Simpler Operations**
   - One systemd service
   - One log file
   - One PID to track

### When to Use What?

**Use Modular (Multiple Scripts)** when:
- Learning boot orchestration concepts
- Testing individual phase patterns
- Simple setups (<10 services, 1-3 phases)
- Rapid prototyping

**Use Monolithic (Single Script)** when:
- Deploying to production (recommended)
- Managing complex dependencies (10+ services)
- Requiring atomic updates and rollbacks
- Optimizing boot performance

### How to Transition

**Phase 1: Learn** (use examples as-is)
```bash
# Test individual patterns
./examples/autostart-minimal.sh
./examples/autostart-docker-stack.sh
```

**Phase 2: Merge** (combine what you need)
```bash
# Copy autostart-template.sh
cp autostart-template.sh /opt/mydevice/autostart.sh

# Add relevant sections from examples
# - Docker phases from autostart-docker-stack.sh
# - Network phases from autostart-network-gateway.sh
```

**Phase 3: Customize** (device-specific)
```bash
# Add your device-specific logic
# - Hardware checks (temperature, storage)
# - Device-specific services
# - Custom recovery modes
```

**Phase 4: Deploy** (production-ready)
```bash
# Single file deployment
sudo cp /opt/mydevice/autostart.sh /opt/autostart/
sudo systemctl enable autostart.service
```

### Real-World Example

Our Pi 5 Router script evolution:
- **v1.0**: Started with autostart-minimal.sh (67 LOC)
- **v2.0**: Added network phases from autostart-network-gateway.sh (+138 LOC)
- **v3.0**: Added Docker phases from autostart-docker-stack.sh (+200 LOC)
- **v4.0**: Custom phases (Pi Zero fleet, Nextcloud, WireGuard) (+500 LOC)
- **v5.0**: Emergency recovery, metrics, optimization (+538 LOC)
- **Current**: Monolithic 1443 LOC production script

**Key insight**: Examples are **building blocks**, not final solutions.

---

## See Also

- [WORKFLOW.md](WORKFLOW.md) - Complete reboot workflow
- [TEMPLATES.md](TEMPLATES.md) - Customization guide
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues

---

**Last Updated**: January 2026