# Phase 3: Post-Reboot Verification

Automated health checks and pre/post snapshot comparison after reboot.

## The Problem

System reboots may succeed silently with:
- Services running but unhealthy (failed health checks)
- Configuration drift (files changed unexpectedly)
- Containers not restarted (wrong restart policy)
- Network issues (routes, DNS, VPN down)
- No audit trail (what happened during boot?)

## The Solution

Automated post-reboot verification:
1. Check graceful shutdown hook executed successfully
2. Verify all containers running + healthy
3. Compare pre/post snapshots (15 categories)
4. Validate network connectivity
5. Generate verification report

## Quick Start

```bash
# After reboot, wait 2-5 minutes for services to stabilize

# 1. Run verification checks
./post-reboot-check.sh

# 2. Compare snapshots (requires pre-reboot snapshot)
./snapshot-compare.py --auto-latest

# 3. Review results
cat /var/log/reboot-reports/reboot-check-*.txt
```

## Components

### post-reboot-check.sh

Automated verification script with multiple check categories:

```bash
# Basic check
./post-reboot-check.sh

# Verbose output
./post-reboot-check.sh --verbose

# JSON output (for CI/CD)
./post-reboot-check.sh --json
```

**Exit Codes:**

| Code | Meaning |
|------|---------|
| 0 | All checks passed |
| 1 | Graceful shutdown hook didn't run |
| 2 | Containers not running |
| 3 | Health checks failing |
| 4 | Network issues |

### snapshot-compare.py

Compares pre-reboot and post-reboot snapshots across 15 categories:

```bash
# Auto-detect latest snapshots
./snapshot-compare.py --auto-latest

# Specify files explicitly
./snapshot-compare.py pre-reboot.json post-reboot.json

# JSON output for CI/CD
./snapshot-compare.py --auto-latest --json

# Verbose output (shows detailed changes)
./snapshot-compare.py --auto-latest --verbose
```

**Exit Codes:**

| Code | Meaning |
|------|---------|
| 0 | All checks passed |
| 1 | Critical issues found |
| 2 | Usage error |

**Comparison Categories:**

| Category | Checks |
|----------|--------|
| System | Kernel version, disk usage, CPU temperature |
| Services | Running/failed/stopped service changes |
| Docker | Container state (running/stopped/missing) |
| Network | Interface state, IP/MAC changes, default route |
| USB Devices | Critical adapters (RTL8153/8156), device changes |
| Route Guardian | Service status, gateway changes, DSL/LTE routes |
| Pi Zero Fleet | Device reachability (watchdog, security, dns, gpio) |
| NetworkManager | Active connection state changes |
| WireGuard | Interface status, peer count changes |
| Hardware Throttling | Under-voltage, thermal throttling events |
| Critical Services | Service health, restart counts |
| Config Checksums | Unexpected configuration file changes |
| Memory Detail | Swap usage warnings |
| Cron Jobs | Added/removed cron entries |
| Boot Info | Boot phase completion, duration validation |

> **Note**: Sections not present in snapshots (e.g., `usb_devices`, `route_guardian`) are reported as "unchanged" by default. This means:
> - If your system doesn't collect USB device metrics, the comparator won't flag missing data
> - Use `--verbose` to see which sections were actually compared
> - Consider enabling extensions to collect device-specific metrics (see `0-pre-reboot/examples/`)

**Environment Variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `SNAPSHOT_DIR` | `/var/log/snapshots` | Directory containing snapshot files |

## Verification Checks

### 1. Graceful Shutdown Hook

```bash
# Verifies hook ran during shutdown
journalctl -b -1 -u docker-graceful-shutdown | grep "completed"
```

### 2. Container Status

```bash
# All containers running?
docker ps --format '{{.Names}}: {{.Status}}'

# Health status
docker ps --filter "health=unhealthy"
```

### 3. Service Health

```bash
# Failed services
systemctl list-units --state=failed

# Critical services active
for svc in ssh docker nginx; do
    systemctl is-active $svc
done
```

### 4. Network Connectivity

```bash
# Gateway reachable
ping -c 1 $(ip route | grep default | awk '{print $3}')

# DNS working
dig +short google.com
```

## Configuration

| Environment Variable | Default | Description |
|---------------------|---------|-------------|
| `LOG_DIR` | `/var/log` | Report output directory |
| `DOCKER_SERVICE_NAME` | `docker-graceful-shutdown` | Service name to check |

## Integration

### CI/CD Pipeline

```yaml
# GitHub Actions example
- name: Post-Reboot Verification
  run: |
    ./3-verification/post-reboot-check.sh --json > results.json
    if [ $? -ne 0 ]; then
      echo "Verification failed!"
      cat results.json
      exit 1
    fi
```

```yaml
# Snapshot comparison in CI/CD
- name: Compare Snapshots
  run: |
    ./3-verification/snapshot-compare.py --auto-latest --json > comparison.json
    if jq -e '.success == false' comparison.json > /dev/null; then
      echo "Snapshot comparison detected issues!"
      jq '.sections[] | select(.problems > 0)' comparison.json
      exit 1
    fi
```

### Monitoring Alert

```bash
# Cron job to verify daily reboot (if scheduled)
0 6 * * * /opt/verification/post-reboot-check.sh || \
    curl -X POST "https://alerts.example.com/reboot-failed"
```

### Automated Report

```bash
# Generate and email report
./post-reboot-check.sh --verbose > /tmp/report.txt
./snapshot-compare.py --auto-latest >> /tmp/report.txt
mail -s "Reboot Report $(date +%Y-%m-%d)" admin@example.com < /tmp/report.txt
```

## Troubleshooting

### "Graceful shutdown hook didn't run"

```bash
# Check service was enabled
systemctl is-enabled docker-graceful-shutdown

# Check Conflicts= is set
systemctl cat docker-graceful-shutdown | grep Conflicts

# View previous boot logs
journalctl -b -1 -u docker-graceful-shutdown
```

### "Containers not running"

```bash
# Check restart policy
docker inspect <container> --format '{{.HostConfig.RestartPolicy.Name}}'
# Should be "always"

# Manual restart
docker start <container>
```

### "Snapshot comparison failed"

```bash
# Verify snapshots exist
ls -la /var/log/snapshots/

# Check JSON validity
python3 -m json.tool /var/log/snapshots/pre-reboot-*.json

# Run with verbose for details
./snapshot-compare.py --auto-latest --verbose
```

### "Critical issues found"

```bash
# Get detailed JSON output
./snapshot-compare.py --auto-latest --json | jq '.sections[] | select(.problems > 0)'

# Review specific section
./snapshot-compare.py --auto-latest --json | jq '.sections[] | select(.section == "services")'
```

## Files

| File | Purpose |
|------|---------|
| `post-reboot-check.sh` | Automated verification script |
| `snapshot-compare.py` | Pre/post snapshot comparison (15 categories) |
| `examples/` | Custom health check examples |

## See Also

- [../0-pre-reboot/](../0-pre-reboot/) - Create pre-reboot snapshots
- [../docs/VERIFICATION.md](../docs/VERIFICATION.md) - Detailed verification guide
- [../docs/TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md) - Common issues

---

**License**: MIT | **Author**: Marc Allgeier ([@fidpa](https://github.com/fidpa))
