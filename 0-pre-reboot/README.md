# Phase 0: Pre-Reboot Snapshot (Optional)

Captures complete system state before reboot for baseline comparison and recovery verification.

## The Problem

Without pre-reboot snapshots, you cannot:
- Verify what changed after reboot (configuration drift)
- Prove system recovery for compliance/audits
- Compare service states (which failed to restart?)
- Debug complex boot failures (no baseline)

## The Solution

Capture complete system state as JSON before reboot:
- 20+ system metrics (services, Docker, network, storage)
- Baseline for automated comparison
- Extension API for custom metrics
- Machine-readable audit trail

## Quick Start

```bash
# Run as root (required for complete metrics)
sudo ./system-snapshot.sh pre-reboot

# Output: /var/log/snapshots/pre-reboot-YYYYMMDD-HHMMSS.json
```

## Features

| Feature | Description |
|---------|-------------|
| **JSON Output** | Machine-readable format for automated comparison |
| **System Info** | Kernel, OS, uptime, load, memory, disk usage |
| **Services** | Running + failed systemd services with counts |
| **Docker** | Container names, status, state (gracefully escaped) |
| **Network** | Interfaces (JSON), routes, default gateway |
| **Storage** | All mounts with usage statistics |
| **Extension API** | Add custom metrics without modifying core script |

## Output Format

```json
{
  "timestamp": "20260117-114110",
  "type": "pre-reboot",
  "hostname": "server",
  "system": {
    "kernel": "6.12.47+rpt-rpi-2712",
    "os_release": "Debian GNU/Linux 12 (bookworm)",
    "uptime_seconds": 49478.93,
    "load_average": [3.24, 3.24, 3.0],
    "memory_total_kb": 16608368,
    "memory_free_kb": 6775936,
    "disk_usage_percent": 19
  },
  "services": {
    "running": ["docker.service", "ssh.service", "..."],
    "failed": [],
    "running_count": 60,
    "failed_count": 0
  },
  "docker": {
    "service_active": true,
    "containers": [
      {"name": "postgres", "status": "Up 14 hours (healthy)", "state": "running"},
      {"name": "redis", "status": "Up 14 hours", "state": "running"}
    ],
    "running_count": 9,
    "total_count": 9
  },
  "network": {
    "interfaces": [...],
    "routes": [...],
    "default_gateway": "192.168.1.1"
  },
  "storage": {
    "mounts": [
      {"filesystem": "/dev/sda1", "size": "100G", "used": "45G", "available": "55G", "use_percent": "45%", "mount": "/"}
    ]
  }
}
```

## Configuration

| Environment Variable | Default | Description |
|---------------------|---------|-------------|
| `SNAPSHOT_DIR` | `/var/log/snapshots` | Output directory |
| `ENABLE_EXTENSIONS` | `false` | Enable custom metrics collection |

```bash
# Custom output directory
sudo SNAPSHOT_DIR=/var/backups/snapshots ./system-snapshot.sh pre-reboot

# Enable extensions
sudo ENABLE_EXTENSIONS=true ./system-snapshot.sh pre-reboot
```

## Extension API

Add custom metrics by implementing `collect_custom_metrics()`:

```bash
#!/bin/bash
# my-custom-snapshot.sh

# Source the main script (provides all functions)
source ./system-snapshot.sh

# Override the custom metrics function
collect_custom_metrics() {
    append_buffer '  "custom": {'

    # Example: CPU temperature
    local cpu_temp
    cpu_temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo "0")
    cpu_temp=$((cpu_temp / 1000))
    append_buffer "    \"cpu_temp_celsius\": $cpu_temp,"

    # Example: GPU memory (Raspberry Pi)
    if command -v vcgencmd >/dev/null 2>&1; then
        local gpu_mem
        gpu_mem=$(vcgencmd get_mem gpu | cut -d= -f2 | tr -d 'M')
        append_buffer "    \"gpu_memory_mb\": $gpu_mem"
    else
        append_buffer "    \"gpu_memory_mb\": 0"
    fi

    append_buffer '  }'
}

# Run with extensions enabled
ENABLE_EXTENSIONS=true
main "$@"
```

See `examples/` directory for more extension examples.

## Security

| Feature | Implementation |
|---------|----------------|
| **Root Required** | Script validates `EUID == 0` |
| **Restrictive Permissions** | `umask 077` for snapshot files |
| **Input Validation** | Only `pre-reboot` or `post-reboot` allowed |
| **JSON Escaping** | All strings escaped (quotes, newlines, tabs, backslashes) |

## Robustness

| Pattern | Purpose |
|---------|---------|
| **json_escape()** | Prevents JSON injection from special characters |
| **FIRST-Flag** | Proper comma handling in arrays (no trailing commas) |
| **Tab-separated Docker** | Robust parsing even with special chars in container names |
| **Defensive defaults** | Empty values get safe defaults |

## Integration

### With Phase 3: Verification

```bash
# Before reboot
sudo ./system-snapshot.sh pre-reboot

# After reboot
sudo ./system-snapshot.sh post-reboot

# Compare snapshots
cd ../3-verification
./snapshot-compare.py --auto-latest
```

### With CI/CD

```bash
# JSON output + exit codes for automation
sudo ./system-snapshot.sh pre-reboot
if [ $? -eq 0 ]; then
    echo "Snapshot created successfully"
    # Get the latest snapshot file (named pre-reboot-YYYYMMDD-HHMMSS.json)
    LATEST=$(ls -t /var/log/snapshots/pre-reboot-*.json 2>/dev/null | head -1)
    # Parse JSON with jq
    jq '.services.running_count' "$LATEST"
fi
```

### With Monitoring

```bash
# Get the latest pre-reboot snapshot
LATEST=$(ls -t /var/log/snapshots/pre-reboot-*.json 2>/dev/null | head -1)
# Export to Prometheus via textfile collector
SNAPSHOT=$(cat "$LATEST")
echo "system_services_running $(echo $SNAPSHOT | jq '.services.running_count')" > /var/lib/node_exporter/textfile_collector/snapshot.prom
echo "system_docker_containers $(echo $SNAPSHOT | jq '.docker.running_count')" >> /var/lib/node_exporter/textfile_collector/snapshot.prom
```

## Troubleshooting

### Permission Denied

```bash
# Must run as root
sudo ./system-snapshot.sh pre-reboot
```

### Invalid Snapshot Type

```bash
# Only pre-reboot or post-reboot allowed
./system-snapshot.sh pre-reboot   # OK
./system-snapshot.sh post-reboot  # OK
./system-snapshot.sh custom       # ERROR: Invalid snapshot type
```

### JSON Validation Failed

```bash
# Check JSON syntax (get latest snapshot first)
LATEST=$(ls -t /var/log/snapshots/pre-reboot-*.json 2>/dev/null | head -1)
python3 -m json.tool "$LATEST"

# Common causes:
# - Docker container with special characters in name/status
# - Service name with quotes
```

### Empty Arrays

```bash
# Check if Docker is running
systemctl is-active docker

# Check if services are accessible
systemctl list-units --type=service --state=running
```

## Files

| File | Purpose |
|------|---------|
| `system-snapshot.sh` | Main snapshot script |
| `examples/` | Extension examples |

## See Also

- [../docs/WORKFLOW.md](../docs/WORKFLOW.md) - Complete reboot workflow
- [../docs/VERIFICATION.md](../docs/VERIFICATION.md) - Snapshot comparison guide
- [../3-verification/](../3-verification/) - Post-reboot verification tools

---

**License**: MIT | **Author**: Marc Allgeier ([@fidpa](https://github.com/fidpa))
