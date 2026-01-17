# Phase 1: Graceful Shutdown

systemd hook for graceful Docker container shutdown before system halt/reboot.

## The Problem

Standard `sudo reboot` kills Docker containers immediately (SIGKILL), causing:
- PostgreSQL loses in-flight transactions
- Redis loses unsaved cache data
- Applications crash mid-request
- File corruption risk

## The Solution

A systemd service that:
1. Stays "active" during normal operation
2. Runs `ExecStop` when shutdown/reboot is triggered
3. Stops containers gracefully (SIGTERM → timeout → SIGKILL)
4. Flushes filesystem buffers before shutdown proceeds

## Quick Start

```bash
# 1. Install script
sudo mkdir -p /opt/linux-server-reboot-management
sudo cp docker-graceful-shutdown.sh /opt/linux-server-reboot-management/
sudo chmod +x /opt/linux-server-reboot-management/docker-graceful-shutdown.sh

# 2. Install systemd service
sudo cp ../config/systemd/docker-graceful-shutdown.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable docker-graceful-shutdown
sudo systemctl start docker-graceful-shutdown

# 3. Test (does NOT reboot!)
sudo systemctl stop docker-graceful-shutdown
journalctl -u docker-graceful-shutdown -n 50
```

## The Critical Pattern: `Conflicts=`

**Most guides get this wrong.** This does NOT work:

```ini
[Unit]
Before=shutdown.target

[Service]
ExecStop=/path/to/script.sh
```

**Why?** `Before=` only controls ordering, NOT activation. `ExecStop` never runs.

**Correct pattern:**

```ini
[Unit]
Conflicts=shutdown.target reboot.target halt.target
Before=shutdown.target reboot.target halt.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true
ExecStop=/opt/linux-server-reboot-management/docker-graceful-shutdown.sh
TimeoutStopSec=120
```

**Why this works:**
- `Conflicts=` forces the service to STOP when shutdown.target activates
- `Before=` ensures it stops BEFORE shutdown proceeds
- `RemainAfterExit=yes` keeps service "active" after ExecStart
- `ExecStop=` runs when service stops (triggered by Conflicts=)

## Configuration

| Environment Variable | Default | Description |
|---------------------|---------|-------------|
| `GRACEFUL_SHUTDOWN_LOG_FILE` | `/var/log/docker-graceful-shutdown.log` | Log file location |
| `GRACEFUL_SHUTDOWN_TIMEOUT` | `30` | Container stop timeout (seconds) |

```bash
# In systemd service file
[Service]
Environment="GRACEFUL_SHUTDOWN_TIMEOUT=60"
Environment="GRACEFUL_SHUTDOWN_LOG_FILE=/var/log/myapp/shutdown.log"
```

## Container Restart Policy

| Policy | After Reboot | Recommendation |
|--------|--------------|----------------|
| `restart: always` | Auto-starts | **Use this** |
| `restart: unless-stopped` | Stays stopped | Avoid |
| `restart: on-failure` | Stays stopped | Batch jobs only |
| `restart: no` | Stays stopped | One-time tasks |

**Important:** The script warns about containers with `unless-stopped` policy.

## Shutdown Flow

```
sudo reboot
  ↓
systemd activates reboot.target
  ↓
Conflicts= triggers service stop
  ↓
ExecStop runs (this script)
  ↓
docker stop --time 30 <container> (for each)
  ↓
Container receives SIGTERM
  ↓
30s timeout (configurable)
  ↓
SIGKILL if still running
  ↓
Docker service stopped
  ↓
sync (flush buffers)
  ↓
Shutdown proceeds
```

## Testing

### Dry-Run Test (Recommended First)

```bash
# Stop service (triggers ExecStop without rebooting)
sudo systemctl stop docker-graceful-shutdown

# Check logs
journalctl -u docker-graceful-shutdown -n 50

# Verify containers stopped
docker ps

# Restart service for next test
sudo systemctl start docker-graceful-shutdown
```

### Full Reboot Test

```bash
# Reboot system
sudo reboot

# After reboot, check previous boot logs
journalctl -b -1 -u docker-graceful-shutdown

# Verify containers restarted
docker ps
```

## Troubleshooting

### Hook Doesn't Run

```bash
# Check service is active
systemctl status docker-graceful-shutdown
# Should show: Active: active (exited)

# Verify Conflicts= is set
systemctl cat docker-graceful-shutdown | grep Conflicts
```

### Containers Don't Restart

```bash
# Check restart policy
docker inspect <container> --format '{{.HostConfig.RestartPolicy.Name}}'

# Should be "always", not "unless-stopped"
```

### Timeout Too Short

```bash
# Increase timeout in service file
sudo systemctl edit docker-graceful-shutdown

# Add:
[Service]
TimeoutStopSec=300
Environment="GRACEFUL_SHUTDOWN_TIMEOUT=60"
```

## Files

| File | Purpose |
|------|---------|
| `docker-graceful-shutdown.sh` | Main shutdown script |

## See Also

- [../docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) - Technical deep dive on `Conflicts=` pattern
- [../docs/TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md) - Common issues
- [../config/systemd/](../config/systemd/) - systemd service templates

---

**License**: MIT | **Author**: Marc Allgeier ([@fidpa](https://github.com/fidpa))
