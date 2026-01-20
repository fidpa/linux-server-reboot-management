# Setup Guide

## ⚡ TL;DR

Install Docker graceful shutdown hook via systemd service; requires Linux systemd 240+, Docker 19.03+, and root access.

---

Complete installation and configuration guide for Linux Server Reboot Management.

## Prerequisites

### Required

- **Linux** with systemd 240+ (Debian 10+, Ubuntu 18.04+, RHEL 8+)
- **Docker** 19.03+ or docker-compose v1.25+
- **Bash** 4.0+
- **Root/sudo access** for systemd service installation

### Optional

- **Prometheus** (for metrics export)
- **Telegram Bot** (for alerts)

## Installation

### 1. Clone Repository

```bash
git clone https://github.com/fidpa/linux-server-reboot-management.git
cd linux-server-reboot-management
```

### 2. Install Shutdown Script

```bash
# Choose installation location (adjust as needed)
sudo mkdir -p /opt/linux-server-reboot-management
sudo cp 1-graceful-shutdown/docker-graceful-shutdown.sh /opt/linux-server-reboot-management/
sudo chmod +x /opt/linux-server-reboot-management/docker-graceful-shutdown.sh
```

### 3. Configure systemd Service

**Option A: Generic Template**

```bash
# Copy template
sudo cp config/systemd/docker-graceful-shutdown.service /etc/systemd/system/

# Edit service file
sudo nano /etc/systemd/system/docker-graceful-shutdown.service
```

Edit these values:
- `User=` - Set to your service user (e.g., `root`, `admin`, `docker-user`)
- `ExecStop=` - Update path to match your installation
- `TimeoutStopSec=` - Adjust based on container count (120s = ~20-30 containers)

**Option B: Use Example** (Network Gateway or Docker Host)

```bash
# For network gateway setup (6-8 containers, moderate resources)
sudo cp config/examples/gateway-server.service /etc/systemd/system/docker-graceful-shutdown.service

# For Docker host setup (30+ containers, high resources)
sudo cp config/examples/docker-host.service /etc/systemd/system/docker-graceful-shutdown.service

# Edit as needed
sudo nano /etc/systemd/system/docker-graceful-shutdown.service
```

### 4. Enable Service

```bash
sudo systemctl daemon-reload
sudo systemctl enable docker-graceful-shutdown
sudo systemctl start docker-graceful-shutdown
```

Verify:
```bash
systemctl status docker-graceful-shutdown
# Should show: Active: active (exited)
```

## Configuration

### Environment Variables

Configure via systemd service file:

```ini
[Service]
# Log file location (default: /var/log/docker-graceful-shutdown.log)
Environment="GRACEFUL_SHUTDOWN_LOG_FILE=/var/log/myapp/graceful-shutdown.log"

# Container stop timeout in seconds (default: 30)
Environment="GRACEFUL_SHUTDOWN_TIMEOUT=30"
```

### Container Stop Timeout

Adjust based on your container types:

| Container Type | Recommended Timeout |
|----------------|---------------------|
| Nginx, lightweight apps | 10-15s |
| PostgreSQL, MariaDB | 30-60s |
| MongoDB, large databases | 60-120s |
| Redis with persistence | 15-30s |

**Calculation**:
- Count containers: `docker ps --format "{{.Names}}" | wc -l`
- Max timeout per container: e.g., 30s
- Service timeout: `container_count * max_timeout + 30s buffer`

Example: 20 containers * 30s + 30s = 630s (set `TimeoutStopSec=630`)

### Log Rotation

Create logrotate config:

```bash
sudo nano /etc/logrotate.d/docker-graceful-shutdown
```

```
/var/log/docker-graceful-shutdown.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
}
```

## Testing

### Dry-Run Test (Safe - No Reboot)

```bash
# Stop service (triggers ExecStop hook)
sudo systemctl stop docker-graceful-shutdown

# Check logs
journalctl -u docker-graceful-shutdown -n 50

# Look for:
# - "Graceful shutdown initiated"
# - Container stop success/failures
# - "Graceful shutdown completed"

# Restart service
sudo systemctl start docker-graceful-shutdown
```

### Verify Containers Restarted

```bash
# Check all containers are running
docker ps

# Check specific container health
docker inspect <container_name> --format '{{.State.Health.Status}}'
# Expected: healthy (if healthcheck configured)
```

### Full Reboot Test

**⚠️ WARNING**: This will reboot your system!

```bash
# Create test file to verify reboot
echo "Pre-reboot: $(date)" | sudo tee /tmp/reboot-test.txt

# Reboot
sudo reboot
```

After reboot:
```bash
# Check test file survived
cat /tmp/reboot-test.txt

# Check graceful shutdown ran (from PREVIOUS boot)
journalctl -b -1 -u docker-graceful-shutdown

# Verify all containers restarted
docker ps
```

## Troubleshooting

### Hook Not Running

**Symptom**: No graceful shutdown logs in journalctl

**Check**:
```bash
# Service is enabled?
systemctl is-enabled docker-graceful-shutdown
# Expected: enabled

# Service is active?
systemctl is-active docker-graceful-shutdown
# Expected: active

# Check service file has Conflicts=
grep "Conflicts=" /etc/systemd/system/docker-graceful-shutdown.service
# Expected: Conflicts=shutdown.target reboot.target halt.target
```

**Fix**: Add `Conflicts=shutdown.target reboot.target halt.target` to service file (see [ARCHITECTURE.md](ARCHITECTURE.md) for why this is critical).

### Containers Not Restarting

**Symptom**: Containers stopped after reboot, not restarted automatically

**Check restart policies**:
```bash
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{json .HostConfig.RestartPolicy}}"
```

**Fix**: Change `restart: unless-stopped` to `restart: always` in docker-compose.yml:

```yaml
services:
  myapp:
    restart: always  # Instead of unless-stopped
```

### Timeout Exceeded

**Symptom**: systemd kills service before containers stop

```bash
# Check logs
journalctl -u docker-graceful-shutdown -n 100 | grep -i timeout
```

**Fix**: Increase `TimeoutStopSec=` in service file:

```ini
[Service]
TimeoutStopSec=300  # Increase from 120s
```

### Permission Denied

**Symptom**: "Permission denied" in logs when stopping containers

**Fix**: Ensure service user has Docker socket access:

```bash
# Add user to docker group
sudo usermod -aG docker <service-user>

# OR run as root
sudo nano /etc/systemd/system/docker-graceful-shutdown.service
# Change: User=root
```

## Advanced Configuration

### Prometheus Metrics Export

Create textfile collector directory:

```bash
sudo mkdir -p /var/lib/node_exporter/textfile_collector
```

Add to shutdown script:

```bash
# At end of main() function
cat > /var/lib/node_exporter/textfile_collector/graceful_shutdown.prom <<EOF
# HELP docker_graceful_shutdown_containers_stopped Total containers stopped during last graceful shutdown
# TYPE docker_graceful_shutdown_containers_stopped gauge
docker_graceful_shutdown_containers_stopped $stopped_containers

# HELP docker_graceful_shutdown_containers_failed Total containers that failed to stop
# TYPE docker_graceful_shutdown_containers_failed gauge
docker_graceful_shutdown_containers_failed $failed_containers
EOF
```

### Telegram Alerts

Add to shutdown script (requires `curl`):

```bash
# Configuration
TELEGRAM_BOT_TOKEN="YOUR_BOT_TOKEN"
TELEGRAM_CHAT_ID="YOUR_CHAT_ID"

# Alert function
send_alert() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" \
        -d text="$message" \
        -d parse_mode="Markdown" > /dev/null
}

# Call after shutdown
send_alert "🔄 Graceful shutdown: $stopped_containers stopped, $failed_containers failed"
```

## Next Steps

- Read [ARCHITECTURE.md](ARCHITECTURE.md) to understand how `Conflicts=` works
- Read [VERIFICATION.md](VERIFICATION.md) for post-reboot checks
- See [3-verification/examples/](../3-verification/examples/) for docker-compose templates
- See [2-autostart/examples/](../2-autostart/examples/) for autostart script examples
- Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues

## Support

- **Issues**: https://github.com/fidpa/linux-server-reboot-management/issues
- **Documentation**: https://github.com/fidpa/linux-server-reboot-management/docs
