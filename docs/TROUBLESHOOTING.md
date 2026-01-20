# Troubleshooting Guide

## ⚡ TL;DR

Common issues: missing `Conflicts=` in systemd service, container not restarting, timeout errors, or permission problems.

---

Common issues and solutions for Linux Server Reboot Management.

## Quick Diagnosis

Run these commands to identify the problem:

```bash
# 1. Service status
systemctl status docker-graceful-shutdown

# 2. Recent logs
journalctl -u docker-graceful-shutdown -n 50

# 3. Service configuration
systemctl cat docker-graceful-shutdown

# 4. Container status
docker ps -a

# 5. Last reboot logs
journalctl -b -1 -u docker-graceful-shutdown
```

## Problem Categories

- [Hook Not Running](#hook-not-running)
- [Containers Not Restarting](#containers-not-restarting)
- [Timeout Issues](#timeout-issues)
- [Permission Errors](#permission-errors)
- [Data Corruption](#data-corruption)
- [Service Won't Start](#service-wont-start)

---

## Hook Not Running

### Symptom

No graceful shutdown logs after reboot:

```bash
journalctl -b -1 -u docker-graceful-shutdown
# Output: No entries found
```

### Diagnosis

```bash
# Check service file
systemctl cat docker-graceful-shutdown | grep Conflicts
```

### Cause 1: Missing `Conflicts=`

**Problem**: Service file only has `Before=`, no `Conflicts=`

**Fix**:
```bash
sudo nano /etc/systemd/system/docker-graceful-shutdown.service
```

Add this line in `[Unit]` section:
```ini
Conflicts=shutdown.target reboot.target halt.target
```

Reload:
```bash
sudo systemctl daemon-reload
sudo systemctl restart docker-graceful-shutdown
```

**Why**: `Before=` only controls ordering, NOT activation. Only `Conflicts=` forces ExecStop to run.

### Cause 2: Service Not Enabled

**Problem**: Service not enabled at boot

**Check**:
```bash
systemctl is-enabled docker-graceful-shutdown
# Expected: enabled
# Bad: disabled
```

**Fix**:
```bash
sudo systemctl enable docker-graceful-shutdown
sudo systemctl start docker-graceful-shutdown
```

### Cause 3: Service Failed to Start

**Problem**: Service in failed state

**Check**:
```bash
systemctl status docker-graceful-shutdown
# Look for: Active: failed
```

**Fix**: Check logs for errors:
```bash
journalctl -u docker-graceful-shutdown -n 100
```

Common causes:
- Script path incorrect in `ExecStop=`
- Script not executable (`chmod +x`)
- Syntax error in script

---

## Containers Not Restarting

### Symptom

After reboot, containers are stopped:

```bash
docker ps
# Only a few containers running, expected more
```

### Cause 1: Wrong Restart Policy

**Problem**: Containers have `restart: unless-stopped`

**Check**:
```bash
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{json .HostConfig.RestartPolicy}}"
```

**Fix**: Change to `restart: always` in docker-compose.yml:

```yaml
services:
  postgres:
    restart: always  # Change from unless-stopped
```

Apply:
```bash
docker-compose up -d --force-recreate
```

**Why**: Graceful shutdown stops containers. `unless-stopped` remembers "stopped" state and won't restart after reboot.

### Cause 2: Docker Service Not Running

**Problem**: Docker daemon didn't start

**Check**:
```bash
systemctl status docker
```

**Fix**:
```bash
sudo systemctl start docker
```

If it fails to start, check logs:
```bash
journalctl -u docker -n 100
```

### Cause 3: Network Issues

**Problem**: Containers fail health checks due to network

**Check**:
```bash
docker network ls
docker exec <container> ping -c 3 8.8.8.8
```

**Fix**:
```bash
# Recreate networks
docker network prune -f
docker-compose up -d
```

---

## Timeout Issues

### Symptom

Hook killed before completing:

```bash
journalctl -u docker-graceful-shutdown | grep timeout
# Or service shows: "Stopping timed out. Killing."
```

### Cause: Too Many Containers

**Problem**: `TimeoutStopSec=` too short for container count

**Calculate required timeout**:
```
container_count * stop_timeout + buffer
Example: 30 containers * 30s + 30s = 930s
```

**Fix**:
```bash
sudo nano /etc/systemd/system/docker-graceful-shutdown.service
```

Increase timeout:
```ini
[Service]
TimeoutStopSec=930  # Adjust based on your calculation
```

Reload:
```bash
sudo systemctl daemon-reload
```

### Alternative: Parallel Shutdown

For many containers, modify script for parallel stops:

```bash
# In docker-graceful-shutdown.sh
for container in $running_containers; do
    docker stop --time 30 "$container" &
done
wait
```

**Tradeoff**: Faster but harder to debug.

---

## Permission Errors

### Symptom

```
Permission denied while trying to connect to Docker daemon socket
```

### Cause 1: User Not in docker Group

**Problem**: Service user can't access Docker socket

**Check**:
```bash
groups <service-user>
# Should include: docker
```

**Fix**:
```bash
sudo usermod -aG docker <service-user>

# Reboot required for group change to take effect
sudo reboot
```

### Cause 2: Wrong Service User

**Problem**: User specified in service doesn't exist

**Check**:
```bash
systemctl cat docker-graceful-shutdown | grep User=
id <that-user>
```

**Fix**: Change to existing user or root:
```bash
sudo nano /etc/systemd/system/docker-graceful-shutdown.service
```

```ini
[Service]
User=root  # Or existing user with docker access
```

### Cause 3: Log Directory Permissions

**Problem**: Can't write to log file

**Fix**:
```bash
sudo mkdir -p /var/log/docker-graceful-shutdown
sudo chown <service-user>:<service-user> /var/log/docker-graceful-shutdown
sudo chmod 755 /var/log/docker-graceful-shutdown
```

---

## Data Corruption

### Symptom

Database reports corruption after reboot:

```bash
docker logs postgres | grep -i corrupt
```

### Cause 1: Container Killed Before Graceful Stop

**Problem**: Hook didn't run or timeout too short

**Verify**:
```bash
journalctl -b -1 -u docker-graceful-shutdown | grep "Successfully stopped: postgres"
```

**Fix**:
1. Ensure hook runs (add `Conflicts=`)
2. Increase container timeout:
   ```bash
   Environment="GRACEFUL_SHUTDOWN_TIMEOUT=60"
   ```

### Cause 2: Filesystem Not Synced

**Problem**: Buffers not flushed before shutdown

**Verify hook includes**:
```bash
grep -A 5 "sync" /opt/linux-server-reboot-management/docker-graceful-shutdown.sh
```

**Fix**: Ensure script calls `sync` after stopping containers.

### Recovery

```bash
# 1. Stop container
docker stop postgres

# 2. Backup data
sudo cp -r /var/lib/docker/volumes/postgres_data /backup/

# 3. Try recovery
docker start postgres
docker logs postgres

# 4. If still corrupt, restore from backup
sudo rm -rf /var/lib/docker/volumes/postgres_data/_data/*
sudo cp -r /backup/postgres_data/_data/* /var/lib/docker/volumes/postgres_data/_data/
docker start postgres
```

---

## Service Won't Start

### Symptom

```bash
systemctl start docker-graceful-shutdown
# Job failed. See "systemctl status" and "journalctl -xe"
```

### Cause 1: Script Not Found

**Problem**: Path in `ExecStop=` incorrect

**Check**:
```bash
systemctl cat docker-graceful-shutdown | grep ExecStop=
ls -la <that-path>
```

**Fix**: Update path or copy script to correct location.

### Cause 2: Script Not Executable

**Problem**: Script doesn't have execute permission

**Check**:
```bash
ls -la /opt/linux-server-reboot-management/docker-graceful-shutdown.sh
# Should show: -rwxr-xr-x
```

**Fix**:
```bash
sudo chmod +x /opt/linux-server-reboot-management/docker-graceful-shutdown.sh
```

### Cause 3: Syntax Error in Script

**Problem**: Bash syntax error

**Check**:
```bash
bash -n /opt/linux-server-reboot-management/docker-graceful-shutdown.sh
```

**Fix**: Review script for syntax errors, ensure proper quoting.

### Cause 4: Invalid systemd Configuration

**Problem**: Typo in service file

**Check**:
```bash
systemd-analyze verify docker-graceful-shutdown.service
```

**Fix**: Correct syntax errors, then:
```bash
sudo systemctl daemon-reload
```

---

## Advanced Debugging

### Enable Debug Logging

Add to script:
```bash
set -x  # Print each command
# ... rest of script
set +x  # Stop printing
```

### Check systemd Manager Logs

```bash
journalctl -u systemd-shutdown -b -1
```

### Monitor Real-Time During Reboot

On another system (via SSH):
```bash
ssh user@target-system "journalctl -u docker-graceful-shutdown -f"
# Then reboot target system
```

### Inspect ExecStop Timing

```bash
systemd-analyze blame | grep docker-graceful-shutdown
```

---

## Getting Help

If you're still stuck:

1. **Gather diagnostic info**:
   ```bash
   systemctl status docker-graceful-shutdown > status.txt
   journalctl -u docker-graceful-shutdown -n 200 > logs.txt
   systemctl cat docker-graceful-shutdown > service-file.txt
   docker ps -a > containers.txt
   ```

2. **Open GitHub issue**:
   - Attach diagnostic files
   - Describe expected vs actual behavior
   - Include OS/systemd version

3. **Common mistakes checklist**:
   - [ ] `Conflicts=` is present in service file
   - [ ] Service is enabled (`systemctl is-enabled`)
   - [ ] Script path is correct in `ExecStop=`
   - [ ] Script is executable (`chmod +x`)
   - [ ] Service user has Docker access
   - [ ] `TimeoutStopSec=` is sufficient
   - [ ] Containers have `restart: always`

---

## Related Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) - Understanding `Conflicts=` pattern
- [VERIFICATION.md](VERIFICATION.md) - Post-reboot checks
- [SETUP.md](SETUP.md) - Installation guide
