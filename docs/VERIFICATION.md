# Post-Reboot Verification

## ⚡ TL;DR

Post-reboot verification checks graceful shutdown logs, container restart status, and system health using automated post-reboot-check.sh script.

---

Automated verification checklist after system reboot.

## Quick Verification (30 seconds)

```bash
# 1. All containers running?
docker ps --format "table {{.Names}}\t{{.Status}}"

# 2. Graceful shutdown logs present?
journalctl -b -1 -u docker-graceful-shutdown | grep "Graceful shutdown completed"

# 3. No failed containers?
docker ps -a --filter "status=exited" --format "table {{.Names}}\t{{.Status}}"
```

Expected:
- ✅ All expected containers showing "Up X minutes"
- ✅ "Graceful shutdown completed" message found
- ✅ No unexpected exited containers

## Full Verification Script

Use the included `3-verification/post-reboot-check.sh`:

```bash
cd 3-verification
sudo ./post-reboot-check.sh
```

Output example:
```
[INFO] Post-reboot verification started
[OK] Graceful shutdown hook executed (8 containers stopped)
[OK] All 8 containers running and healthy
[OK] Network connectivity verified
[INFO] Verification completed: 0 errors, 0 warnings
```

## Manual Verification Steps

### 1. Verify Graceful Shutdown Executed

```bash
# Check logs from PREVIOUS boot
journalctl -b -1 -u docker-graceful-shutdown -n 100
```

Look for:
```
[INFO] Graceful shutdown initiated
[INFO] Found N running containers
[INFO] Stopping container: postgres
[INFO] Successfully stopped: postgres
...
[INFO] Graceful shutdown completed: N stopped, 0 failed
```

**Red flags**:
- ❌ No logs found → Hook didn't run (check `Conflicts=`)
- ❌ "Failed to stop" messages → Containers died ungracefully
- ❌ Timeout errors → Increase `TimeoutStopSec=`

### 2. Verify Containers Restarted

```bash
# List all containers
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{json .HostConfig.RestartPolicy}}"
```

Expected:
- ✅ All production containers: Status = "Up X minutes"
- ✅ Restart policy: `{"Name":"always","MaximumRetryCount":0}`

**Red flags**:
- ❌ Container status = "Exited" → Check restart policy
- ❌ Restart policy = "unless-stopped" → Won't auto-restart after graceful stop

### 3. Verify Container Health

For containers with healthchecks:

```bash
# Check health status
docker ps --format "table {{.Names}}\t{{.Status}}"
```

Expected: "(healthy)" suffix for health-checked containers

Detailed health check:
```bash
docker inspect <container_name> --format '{{.State.Health.Status}}'
# Expected: healthy
```

**Red flags**:
- ❌ "(unhealthy)" → Container started but failing health checks
- ❌ "(starting)" for >2 minutes → Health check may never pass

### 4. Verify Services

```bash
# Check systemd services
systemctl status docker.service
systemctl status docker-graceful-shutdown.service

# Expected:
# docker.service: Active: active (running)
# docker-graceful-shutdown.service: Active: active (exited)
```

### 5. Verify Network Connectivity

```bash
# Test container networking
docker exec <container_name> ping -c 3 8.8.8.8

# Test inter-container networking
docker exec <container1> ping -c 3 <container2>

# Test exposed ports
curl -I http://localhost:<port>
```

### 6. Verify Data Integrity

**PostgreSQL**:
```bash
docker exec <postgres_container> psql -U <user> -d <db> -c "SELECT COUNT(*) FROM <table>;"
```

**Redis**:
```bash
docker exec <redis_container> redis-cli PING
# Expected: PONG
```

**Files**:
```bash
# Check volume data
sudo ls -lah /var/lib/docker/volumes/<volume_name>/_data/
```

## Automated Verification with post-reboot-check.sh

The included verification script checks:

1. ✅ Graceful shutdown hook executed
2. ✅ All containers running
3. ✅ Container health checks passing
4. ✅ No unexpected "Exited" containers
5. ✅ Network connectivity
6. ✅ Optional: Custom health checks

### Usage

```bash
# Basic check
./src/post-reboot-check.sh

# Verbose mode
./src/post-reboot-check.sh --verbose

# Machine-readable output
./src/post-reboot-check.sh --json
```

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All checks passed ✅ |
| 1 | Hook didn't run ❌ |
| 2 | Containers not running ❌ |
| 3 | Health checks failing ⚠️ |
| 4 | Network issues ⚠️ |

### Integration with Monitoring

#### Systemd Timer

Run verification automatically after boot:

```ini
# /etc/systemd/system/post-reboot-check.timer
[Unit]
Description=Post-Reboot Verification Timer
After=docker.service

[Timer]
OnBootSec=2min
Unit=post-reboot-check.service

[Install]
WantedBy=timers.target
```

```ini
# /etc/systemd/system/post-reboot-check.service
[Unit]
Description=Post-Reboot Verification
After=docker.service

[Service]
Type=oneshot
ExecStart=/opt/linux-server-reboot-management/post-reboot-check.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

#### Prometheus Metrics

Export verification results:

```bash
# In post-reboot-check.sh, add:
cat > /var/lib/node_exporter/textfile_collector/post_reboot_check.prom <<EOF
# HELP post_reboot_check_success Last post-reboot check success status
# TYPE post_reboot_check_success gauge
post_reboot_check_success $exit_code

# HELP post_reboot_check_containers_running Containers running after reboot
# TYPE post_reboot_check_containers_running gauge
post_reboot_check_containers_running $running_count
EOF
```

#### Telegram Alert

Send alert on failure:

```bash
# In post-reboot-check.sh, add:
if [[ $exit_code -ne 0 ]]; then
    send_telegram_alert "⚠️ Post-reboot check FAILED: $error_message"
fi
```

## Common Issues

### Issue 1: Hook Didn't Run

**Symptom**: No graceful shutdown logs

**Verification**:
```bash
journalctl -b -1 -u docker-graceful-shutdown
# Output: No entries found
```

**Fix**: Add `Conflicts=shutdown.target` to service file (see [ARCHITECTURE.md](ARCHITECTURE.md))

### Issue 2: Containers Didn't Restart

**Symptom**: Containers in "Exited" state

**Verification**:
```bash
docker ps -a --filter "status=exited"
```

**Fix**: Change restart policy to `always`:
```yaml
services:
  myapp:
    restart: always
```

### Issue 3: Data Corruption

**Symptom**: Database reports corruption on startup

**Verification**:
```bash
docker logs <postgres_container> | grep -i corrupt
```

**Fix**:
1. Restore from backup
2. Increase container stop timeout in shutdown script
3. Verify graceful shutdown logs show successful stops

### Issue 4: Network Issues After Reboot

**Symptom**: Containers can't communicate

**Verification**:
```bash
docker network ls
docker exec <container> ping <other_container>
```

**Fix**:
```bash
# Recreate networks
docker network prune -f
docker-compose up -d --force-recreate
```

## Rollback Procedure

If verification fails critically:

```bash
# 1. Stop all containers
docker stop $(docker ps -q)

# 2. Restore from backup
# (Your backup procedure here)

# 3. Restart containers
docker-compose up -d

# 4. Re-run verification
./src/post-reboot-check.sh
```

## Best Practices

1. **Always verify graceful shutdown logs first** - This confirms hook ran
2. **Check restart policies** - `always` is safest for production
3. **Monitor health checks** - Don't just check "running", check "healthy"
4. **Automate verification** - Use systemd timer or monitoring integration
5. **Document baseline** - Know what "normal" looks like

## Verification Checklist

Use this checklist after every reboot:

```
□ Graceful shutdown logs present (journalctl -b -1)
□ All containers running (docker ps)
□ Container health checks passing
□ No unexpected "Exited" containers
□ Network connectivity working
□ Database queries successful
□ Application endpoints responding
□ No error logs (journalctl -p err -b)
□ Disk space adequate (df -h)
□ Load average normal (uptime)
```

## Related Documentation

- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues and fixes
- [SETUP.md](SETUP.md#testing) - Initial testing procedures
- [ARCHITECTURE.md](ARCHITECTURE.md) - Understanding how it works
