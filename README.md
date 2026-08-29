# Linux Server Reboot Management

![Version](https://img.shields.io/github/v/release/fidpa/linux-server-reboot-management?label=Version)
![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)
![Platform](https://img.shields.io/badge/Platform-Linux-blue?logo=linux)
![Bash](https://img.shields.io/badge/Bash-4.0%2B-blue?logo=gnubash)
![Python](https://img.shields.io/badge/Python-3.10%2B-blue?logo=python)
![systemd](https://img.shields.io/badge/systemd-240%2B-blue)
![Docker](https://img.shields.io/badge/Docker-19.03%2B-blue?logo=docker)
![CI](https://github.com/fidpa/linux-server-reboot-management/actions/workflows/lint.yml/badge.svg)

A plain `sudo reboot` on a Docker host kills containers where they stand: no SIGTERM,
no PostgreSQL checkpoint, no ordered restart, and nothing that tells you afterwards
whether the machine came back the way it went down. This repository packages the three
pieces that fix that on a single machine: a systemd hook that stops containers before
the shutdown target pulls the floor away, a boot script that brings services back in
dependency order, and a verification pass that compares the result against the state
before the reboot.

## Core Components (1-3)

| Phase | Component | Description |
|-------|-----------|-------------|
| **[1-graceful-shutdown/](1-graceful-shutdown/)** | docker-graceful-shutdown.sh | systemd hook that stops containers with `docker stop --time 30` before the Docker daemon goes down |
| **[2-autostart/](2-autostart/)** | autostart-template.sh | 13-phase boot orchestration with dependency ordering, per-service retries and a recovery mode |
| **[3-verification/](3-verification/)** | post-reboot-check.sh | Health checks after boot, plus snapshot comparison via `snapshot-compare.py` |

## Optional: Pre-Reboot Snapshots

| Phase | Component | Description |
|-------|-----------|-------------|
| **[0-pre-reboot/](0-pre-reboot/)** (Optional) | system-snapshot.sh | JSON snapshots of services, containers, network and storage, as a baseline for the comparison after boot |

## Features

- **Container shutdown before the daemon stops**: `docker stop --time` sends SIGTERM
  and waits (30s by default, `GRACEFUL_SHUTDOWN_TIMEOUT`) before Docker itself is stopped
- **Restart-policy warning**: the hook logs every container running with
  `restart=unless-stopped`, because those do not come back after a reboot
- **13-phase boot orchestration**: SSH and networking before VPN, Docker after storage
  validation, verification and metrics last
- **JSON snapshots and exit codes**: `system-snapshot.sh` writes JSON,
  `post-reboot-check.sh --json` and `snapshot-compare.py --json` read and emit it,
  and both return distinct exit codes per failure class
- **Extension API**: custom metrics enter snapshots and health checks through
  `collect_custom_metrics()`, without editing the shipped scripts
- **JSON escaping for hostile input**: container names and status strings containing
  quotes, backslashes or control characters are escaped rather than breaking the file

> [!IMPORTANT]
> **Known limitations.** `autostart-template.sh` refuses to run as shipped: it exits
> with `EX_CONFIG` (78) while the `TEMPLATE_UNCONFIGURED` line is present, because the
> 13 phases describe one particular machine and starting the wrong services in the wrong
> order is worse than starting none. The same holds for `system-snapshot.sh`, whose
> value depends on the metrics you add for your environment. This is a single-node
> system: nothing here coordinates two machines, and there is no rollback if a boot
> phase fails halfway. The graceful shutdown hook covers Docker containers only, and it
> stops them one after another, not in parallel.

## Quick Start (Core Workflow)

```bash
# 1. Clone repository
git clone https://github.com/fidpa/linux-server-reboot-management.git
cd linux-server-reboot-management

# 2. Install the graceful shutdown hook
#    Checks prerequisites (Bash 4.0+, systemd 240+, Docker), copies the script to
#    /opt/linux-server-reboot-management, installs and enables the systemd unit.
sudo ./install.sh

# 3. Test the hook without rebooting
#    For oneshot+RemainAfterExit units, ExecStop only runs if the unit was started.
sudo systemctl start docker-graceful-shutdown
sudo systemctl stop docker-graceful-shutdown
journalctl -u docker-graceful-shutdown -n 50

# 4. Reboot (the hook runs on its own)
sudo reboot

# 5. After boot, verify
./3-verification/post-reboot-check.sh
```

The installer sets up phase 1 only. Phases 2 and 3 are templates you adapt: see
[2-autostart/README.md](2-autostart/README.md) and
[3-verification/README.md](3-verification/README.md).

**Optional**: pre-reboot snapshots for an audit trail, see
[0-pre-reboot/README.md](0-pre-reboot/README.md).

**Full guides**: each component has its own README; the end-to-end path is in
[docs/WORKFLOW.md](docs/WORKFLOW.md).

## Configuration

Every setting is an environment variable with a default in the script that reads it.

| Variable | Read by | Default | Description |
|----------|---------|---------|-------------|
| `GRACEFUL_SHUTDOWN_TIMEOUT` | `docker-graceful-shutdown.sh` | `30` | Seconds `docker stop` waits per container between SIGTERM and SIGKILL |
| `GRACEFUL_SHUTDOWN_LOG_FILE` | `docker-graceful-shutdown.sh` | `/var/log/docker-graceful-shutdown.log` | Log file of the shutdown hook |
| `INSTALL_DIR` | `install.sh` | `/opt/linux-server-reboot-management` | Target directory of the installation |
| `LOG_FILE` | `autostart-template.sh` | `/var/log/autostart.log` | Log file of the boot orchestration |
| `LOCK_FILE` | `autostart-template.sh` | `/var/run/autostart.lock` | Lock against a second concurrent run |
| `PID_FILE` | `autostart-template.sh` | `/var/run/autostart.pid` | PID file of the running orchestration |
| `ENABLE_PROMETHEUS_METRICS` | `autostart-template.sh` | `true` | Write boot metrics for the node_exporter textfile collector |
| `ENABLE_RECOVERY_MODE` | `autostart-template.sh` | `true` | Fall back to `minimal_recovery_mode` when a phase fails hard |
| `ENABLE_DOCKER_STACK` | `autostart-template.sh` | `true` | Run phase 9 (Docker stack) |
| `ENABLE_PHASE_TIMING` | `autostart-template.sh` | `true` | Measure and log the duration of each phase |
| `RECOVERY_INTERFACE` | `autostart-template.sh` | `eth0` | Interface the recovery mode configures |
| `RECOVERY_IP` | `autostart-template.sh` | `192.0.2.100` | Address for the recovery mode. The default is an RFC 5737 documentation address and deliberately unroutable, so an unset value announces itself instead of half working |
| `SNAPSHOT_DIR` | `system-snapshot.sh`, `snapshot-compare.py` | `/var/log/snapshots` | Directory the JSON snapshots are written to and read from |
| `ENABLE_EXTENSIONS` | `system-snapshot.sh` | `false` | Call `collect_custom_metrics()` for device-specific metrics |
| `LOG_DIR` | `post-reboot-check.sh` | `/var/log` | Directory for the verification report |
| `DOCKER_SERVICE_NAME` | `post-reboot-check.sh` | `docker-graceful-shutdown` | Unit name the check looks for in the journal |

## CLI Reference

`snapshot-compare.py --help`:

```
usage: snapshot-compare.py [-h] [--auto-latest] [--json] [--verbose]
                           [pre_snapshot] [post_snapshot]

Compare pre/post reboot system snapshots

positional arguments:
  pre_snapshot   Pre-reboot snapshot file
  post_snapshot  Post-reboot snapshot file

options:
  -h, --help     show this help message and exit
  --auto-latest  Auto-find latest snapshots
  --json         Output in JSON format
  --verbose, -v  Verbose output

Examples:
  snapshot-compare.py --auto-latest
  snapshot-compare.py --auto-latest --json
  snapshot-compare.py pre-reboot.json post-reboot.json
  snapshot-compare.py --auto-latest --verbose
```

Exit codes: `0` success, `1` critical issues found, `2` usage error.

`post-reboot-check.sh [--verbose] [--json] [--help]`. Its exit codes name the failure:
`0` all checks passed, `1` the graceful shutdown hook did not run, `2` containers not
running, `3` health checks failing, `4` network issues.

`system-snapshot.sh [pre-reboot|post-reboot]` takes no options; any other argument is
rejected so the snapshot type cannot become an arbitrary filename. It requires root and
sets `umask 077`, because a snapshot contains addresses, routes and the service list.

`install.sh` takes no options; `INSTALL_DIR` is its only knob.

## Component Overview

### 3-Phase Core Workflow

| Phase | Trigger | Purpose | Output |
|-------|---------|---------|--------|
| **1. Graceful Shutdown** | Automatic (systemd hook) | Stop containers cleanly | journalctl logs |
| **2. Autostart** | Automatic (systemd service) | Restore services (13 phases) | Boot metrics |
| **3. Verification** | Manual (after boot) | Health checks + comparison | Pass/fail status |

**Optional Phase 0**: pre-reboot snapshots, run manually before the reboot, for an audit
trail and as the baseline of the comparison.

### Key Patterns

| Pattern | Component | Impact |
|---------|-----------|--------|
| **`Conflicts=shutdown.target`** | Graceful Shutdown | Makes `ExecStop` run at all (see below) |
| **`restart: always`** | Docker Compose | Brings containers back after a reboot, which `unless-stopped` does not |
| **13-phase boot model** | Autostart | Dependency ordering (SSH → VPN → Docker) |
| **Extension API** | Snapshots + Health Checks | Custom metrics without touching the shipped scripts |

### Templates

Line counts are `wc -l` on the file, including licence header and comments.

| File | Use Case | Size |
|------|----------|------|
| `autostart-minimal.sh` | Simple setups (<10 services) | 3 phases, 66 lines |
| `autostart-template.sh` | Production (dependency chains) | 13 phases, 864 lines, 5 helper functions, 4 feature flags, 2 recovery settings |
| `autostart-docker-stack.sh` | Multi-tier Docker startup | 5-tier container startup, 167 lines |
| `autostart-network-gateway.sh` | Network gateway/router | NAT/firewall/VPN setup, 209 lines |
| `autostart-database-server.sh` | Database-centric servers | Database priority startup, 200 lines |
| `snapshot-extensions-example.sh` | Custom metrics (vcgencmd, network stats) | Extension API example, 144 lines |
| `03-custom-healthchecks.sh` | Container-specific validation | Database connectivity, endpoint checks, 282 lines |

See [docs/TEMPLATES.md](docs/TEMPLATES.md) for the customization guide.

## 🎯 When to Use This System

**Perfect for:**
- 🏠 **Home routers/gateways** with custom network configurations (NAT, failover, VPN)
- 🔧 **Single-node systems** with complex service dependencies (order matters)
- 📊 **Systems requiring detailed boot verification** (compliance, audit trails)
- 🎓 **Learning DevOps/SRE practices** (observability, service orchestration)

**NOT recommended for:**
- ☁️ **Cloud VMs** → use infrastructure-as-code (Terraform, CloudFormation) instead
- 🐳 **Kubernetes nodes** → use kured + systemd, K8s handles pod rescheduling
- 📦 **Standard LAMP stacks** → systemd dependency management is enough
- 🏢 **Enterprise with change management** → Ansible Tower, ServiceNow integration

**Alternative solutions**: Ansible playbooks (multi-node), systemd units (simple setups),
kured (Kubernetes), cloud-init (cloud VMs). See
[docs/INDUSTRY_COMPARISON.md](docs/INDUSTRY_COMPARISON.md) for the comparison in detail.

## Key Concepts

### The `Conflicts=` Discovery

The finding this repository exists for:

```ini
[Unit]
Conflicts=shutdown.target reboot.target halt.target
Before=shutdown.target reboot.target halt.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStop=/path/to/shutdown-script.sh
```

`Before=` alone orders the unit against the shutdown target but never stops it, so
`ExecStop` does not run and the containers are killed with the daemon. `Conflicts=`
makes systemd stop the unit when `shutdown.target` activates, which is what triggers
`ExecStop`. Both lines are needed: `Conflicts=` for the stop, `Before=` for the order.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the technical deep dive.

### 3-Phase Core Rationale

| Why Three Core Phases? | Benefit |
|------------------------|---------|
| **Phase 1: Graceful Shutdown** | Databases get their SIGTERM (PostgreSQL checkpoints, Redis saves) |
| **Phase 2: Autostart** | Dependency ordering (SSH before VPN, Docker last) |
| **Phase 3: Verification** | Health checks run without someone remembering to run them |
| **Optional Phase 0: Pre-Reboot** | Baseline the verification can compare against |

## Architecture Decisions: Modular vs. Monolithic

### What We Provide

This repository ships **modular examples**, one per use case:

| Example | Lines | Focus | Use Case |
|---------|-------|-------|----------|
| `autostart-minimal.sh` | 66 | Learning | Understanding the basics |
| `autostart-docker-stack.sh` | 167 | Containers | Docker-heavy setups |
| `autostart-network-gateway.sh` | 209 | Networking | Routers/gateways |
| `autostart-database-server.sh` | 200 | Databases | DB-centric servers |

### What We Use in Production

**A single monolithic script per device**, not published here because both are
device-specific throughout: a 1443-line script on the Pi 5 router and a 1139-line one on
the NAS, each covering all 13 phases.

### Which Approach Should You Use?

#### ✅ Use Modular (Multiple Scripts)
- **Learning**: you are new to boot orchestration
- **Simple setups**: fewer than 10 services, 1-3 phases needed
- **Experimentation**: testing different approaches
- **Mix and match**: combining phases from different examples

#### ✅ Use Monolithic (Single Script)
- **Production**: mission-critical boot orchestration
- **Complex setups**: 10+ services, dependencies, recovery logic
- **Atomic updates**: one file to version, deploy and roll back
- **Debugging**: one log, one trace, no jumping between files

### Migration Path

1. **Start**: use `autostart-minimal.sh` for learning
2. **Grow**: copy the phases you need from the other examples
3. **Mature**: merge them into one production script, like `autostart-template.sh`
4. **Customize**: adapt to the machine it runs on

### Trade-offs

| Aspect | Modular | Monolithic |
|--------|---------|------------|
| **Complexity** | Low per file | High overall |
| **Maintainability** | Harder (multiple files) | Easier (single source) |
| **Debugging** | Context switches | Single trace |
| **Deployment** | Multiple files | One file |
| **Learning Curve** | Gentle | Steep |
| **Production Ready** | Assembly required | ✅ Ready |

## Requirements

**Minimum**:
- Linux with systemd 240+ (Debian 10+, Ubuntu 18.04+, RHEL 8+)
- Bash 4.0+
- Root/sudo access

`install.sh` checks all three and refuses to continue if one is missing.

**Component-specific**:
- Docker 19.03+ (for phase 1, graceful shutdown)
- Python 3.10+ (for `snapshot-compare.py`)
- jq 1.5+ (only if your own scripts process the JSON)

**Optional**:
- Prometheus + node_exporter (for the boot metrics of phase 13)
- Telegram bot (for reboot notifications, wired up in your own phase)

## Compatibility

**Tested**: the two machines under [Measured Results](#measured-results), a Raspberry
Pi 5 (Raspberry Pi OS, ARM64) and an AMD Ryzen 9 host (x86_64). Both are Debian-based
and run systemd and Docker.

**Should work, untested**: Ubuntu 22.04 and 24.04 LTS, Debian 11 and 12, RHEL 8+, Rocky
Linux 8+, Fedora 33+. The scripts use nothing Debian-specific beyond systemd and Docker,
but nobody has run a full reboot cycle there.

**Partially supported** (no Docker graceful shutdown):
- Alpine Linux (busybox limitations)
- Non-systemd distros (the `Conflicts=` hook has no equivalent, requires custom init integration)

## Use Cases

- **Docker hosts**: containers get their SIGTERM before the daemon stops
- **Network gateways**: 13-phase boot orchestration (network → VPN → routing → Docker)
- **Compliance**: audit trail from pre/post snapshots and the comparison between them
- **CI/CD pipelines**: JSON output and per-class exit codes for automated testing

## Measured Results

Numbers from the author's own two machines, not from a test suite. They describe what
these two setups do, and they are here as an order of magnitude, not as a promise.

| Machine | Hardware | Boot time |
|---------|----------|-----------|
| Network gateway | Raspberry Pi 5, ARM64, 6 containers | under 90s from power-on to all phases complete |
| Docker host | AMD Ryzen 9, x86_64 | under 120s, which is also the `MAX_BOOT_TIME` target in the template |

Across more than 50 reboots on these two machines, every container came back and no
manual recovery was needed. Shutdown takes under 5 seconds for 8 containers
that shut down on their first SIGTERM; a container that ignores SIGTERM adds up to
`GRACEFUL_SHUTDOWN_TIMEOUT` seconds, and the stops are sequential, so a stack of slow
containers adds up.

## Documentation

**Phase-specific**:

| Phase | Key Docs |
|-------|----------|
| Pre-Reboot | [0-pre-reboot/README.md](0-pre-reboot/README.md) - snapshot format, extension API |
| Graceful Shutdown | [1-graceful-shutdown/README.md](1-graceful-shutdown/README.md) - systemd hook setup |
| Autostart | [2-autostart/README.md](2-autostart/README.md) - 13-phase model, customization |
| Verification | [3-verification/README.md](3-verification/README.md) - health checks, snapshot comparison |

**Repository-level docs**:

📚 **Recommended reading order**: SETUP → WORKFLOW → INDUSTRY_COMPARISON → ARCHITECTURE → TEMPLATES → VERIFICATION

| Document | Description |
|----------|-------------|
| [docs/SETUP.md](docs/SETUP.md) | Installation and configuration |
| [docs/WORKFLOW.md](docs/WORKFLOW.md) | Complete workflow guide |
| [docs/INDUSTRY_COMPARISON.md](docs/INDUSTRY_COMPARISON.md) | When to use this system vs. alternatives (Kubernetes, Ansible, systemd) |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | `Conflicts=` pattern + 13-phase boot model |
| [docs/TEMPLATES.md](docs/TEMPLATES.md) | Customization guide (autostart, snapshots, health checks) |
| [docs/VERIFICATION.md](docs/VERIFICATION.md) | Post-reboot verification checklist |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Common issues (hook not running, containers not restarting) |

**Project files**: [CHANGELOG.md](CHANGELOG.md) for what changed per release,
[SECURITY.md](SECURITY.md) for reporting a vulnerability,
[CONTRIBUTING.md](CONTRIBUTING.md) and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for
working on the repository.

## See Also

- [bash-production-toolkit](https://github.com/fidpa/bash-production-toolkit) - 10 production-ready Bash libraries
- [ubuntu-server-security](https://github.com/fidpa/ubuntu-server-security) - 14-component security hardening
- [linux-monitoring-templates](https://github.com/fidpa/linux-monitoring-templates) - Bash/Python monitoring templates

## License

MIT License - see [LICENSE](LICENSE) for details.

## Author

Marc Allgeier ([@fidpa](https://github.com/fidpa))

This started with a corrupted PostgreSQL database after an ungraceful reboot, and with
weeks of asking why an `ExecStop` hook that looked correct never ran. The answer was one
missing `Conflicts=` line. The three phases around it grew out of the same machines,
Docker hosts running PostgreSQL and Redis.

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for how the
repository is set up.

Help is most useful on:
- Additional autostart templates for specific stacks (LAMP, LEMP, Kubernetes)
- Health check examples for databases (MySQL, MongoDB, Elasticsearch)
- Snapshot extensions for hardware monitoring (temperature, disk I/O, network stats)
- Reports from the untested distributions listed under Compatibility
- Grafana dashboard examples for boot metrics
