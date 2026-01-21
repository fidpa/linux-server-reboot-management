# Linux Server Reboot Management

![Version](https://img.shields.io/badge/Version-1.1.0-blue.svg)
![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)
![Platform](https://img.shields.io/badge/Platform-Linux-blue?logo=linux)
![Bash](https://img.shields.io/badge/Bash-4.0%2B-blue?logo=gnubash)
![Python](https://img.shields.io/badge/Python-3.10%2B-blue?logo=python)
![systemd](https://img.shields.io/badge/systemd-240%2B-blue)
![Docker](https://img.shields.io/badge/Docker-19.03%2B-blue?logo=docker)
![CI](https://github.com/fidpa/linux-server-reboot-management/actions/workflows/lint.yml/badge.svg)

Production-ready Linux server reboot management with 3-phase core workflow + optional pre-reboot snapshots.

**The Problem**: Standard `sudo reboot` causes immediate container termination, random service startup order, and no automated verification. Result: Downtime, data corruption, manual recovery needed.

## Core Components (1-3)

| Phase | Component | Description |
|-------|-----------|-------------|
| **[1-graceful-shutdown/](1-graceful-shutdown/)** | docker-graceful-shutdown.sh | systemd hook for graceful container shutdown (SIGTERM → SIGKILL, 30s timeout) |
| **[2-autostart/](2-autostart/)** | autostart-template.sh | 13-phase boot orchestration with dependency management and retry logic |
| **[3-verification/](3-verification/)** | post-reboot-check.sh | Automated health checks + snapshot comparison |

## Optional: Pre-Reboot Snapshots

| Phase | Component | Description |
|-------|-----------|-------------|
| **[0-pre-reboot/](0-pre-reboot/)** (Optional) | system-snapshot.sh | JSON snapshots for compliance/audit trail - requires customization for your environment |

## Features

- ✅ **Zero Data Loss** - Graceful shutdown with SIGTERM before SIGKILL (30s timeout configurable)
- ✅ **Audit Trail** - JSON snapshots for compliance and recovery verification
- ✅ **Automated Recovery** - 13-phase boot orchestration with dependency ordering
- ✅ **Production-Proven** - 50+ reboots across ARM and x86_64, 100% success rate
- ✅ **Extension API** - Custom metrics for snapshots, health checks, and boot phases
- ✅ **CI/CD Ready** - JSON output, exit codes, automated verification
- ✅ **JSON Robustness** - Proper escaping for special characters in container names/status

## Quick Start (Core Workflow)

```bash
# 1. Clone repository
git clone https://github.com/fidpa/linux-server-reboot-management.git
cd linux-server-reboot-management

# 2. Install graceful shutdown hook
cd 1-graceful-shutdown
sudo mkdir -p /opt/linux-server-reboot-management
sudo cp docker-graceful-shutdown.sh /opt/linux-server-reboot-management/
sudo cp ../config/systemd/docker-graceful-shutdown.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable docker-graceful-shutdown

# 3. Test graceful shutdown hook (does NOT reboot!)
# Note: For oneshot+RemainAfterExit services, ExecStop only runs if service was started first
sudo systemctl start docker-graceful-shutdown
sudo systemctl stop docker-graceful-shutdown
journalctl -u docker-graceful-shutdown -n 50

# 4. Reboot (hook runs automatically)
sudo reboot

# 5. After reboot (wait 5 minutes), verify
cd ../3-verification
./post-reboot-check.sh
```

**Optional**: Enable pre-reboot snapshots for compliance - see [0-pre-reboot/README.md](0-pre-reboot/README.md).

**Full guides**: See each component's README and [docs/WORKFLOW.md](docs/WORKFLOW.md).

## Component Overview

### 3-Phase Core Workflow

| Phase | Trigger | Purpose | Output |
|-------|---------|---------|--------|
| **1. Graceful Shutdown** | Automatic (systemd hook) | Stop containers cleanly | journalctl logs |
| **2. Autostart** | Automatic (systemd service) | Restore services (13 phases) | Boot metrics |
| **3. Verification** | Manual (after boot) | Health checks + comparison | Pass/fail status |

**Optional Phase 0**: Pre-reboot snapshots (manual) for compliance/audit trail - requires environment-specific customization.

### Key Patterns

| Pattern | Component | Impact |
|---------|-----------|--------|
| **`Conflicts=shutdown.target`** | Graceful Shutdown | Forces `ExecStop` to run (otherwise NEVER runs!) |
| **`restart: always`** | Docker Compose | Auto-restarts containers after reboot (NOT `unless-stopped`) |
| **13-phase boot model** | Autostart | Dependency ordering (SSH → VPN → Docker) |
| **Extension API** | Snapshots + Health Checks | Custom metrics without modifying core scripts |

### Templates

| File | Use Case | Complexity |
|------|----------|-----------|
| `autostart-minimal.sh` | Simple setups (<10 services) | 3 phases, ~66 LOC |
| `autostart-template.sh` | Production (dependency chains) | 13 phases, ~815 LOC, 5 helper functions, 4 feature flags |
| `autostart-docker-stack.sh` | Multi-tier Docker startup | 5-tier container startup, ~167 LOC |
| `autostart-network-gateway.sh` | Network gateway/router | NAT/Firewall/VPN setup, ~209 LOC |
| `autostart-database-server.sh` | Database-centric servers | Database priority startup, ~200 LOC |
| `snapshot-extensions-example.sh` | Custom metrics (vcgencmd, network stats) | Extension API example |
| `03-custom-healthchecks.sh` | Container-specific validation | Database connectivity, endpoint checks |

See [docs/TEMPLATES.md](docs/TEMPLATES.md) for customization guide.

## 🎯 When to Use This System

**Perfect for:**
- 🏠 **Home routers/gateways** with custom network configurations (NAT, failover, VPN)
- 🔧 **Single-node systems** with complex service dependencies (order matters!)
- 📊 **Systems requiring detailed boot verification** (compliance, audit trails)
- 🎓 **Learning DevOps/SRE best practices** (observability, service orchestration)

**NOT recommended for:**
- ☁️ **Cloud VMs** → Use infrastructure-as-code (Terraform, CloudFormation) instead
- 🐳 **Kubernetes nodes** → Use kured + systemd (K8s handles pod rescheduling)
- 📦 **Standard LAMP stacks** → systemd dependency management is sufficient
- 🏢 **Enterprise with change-management** → Ansible Tower, ServiceNow integration

**Alternative solutions**: Ansible playbooks (multi-node), systemd units (simple setups), kured (Kubernetes), cloud-init (cloud VMs). See [docs/INDUSTRY_COMPARISON.md](docs/INDUSTRY_COMPARISON.md) for detailed comparison with professional approaches.

## Key Concepts

### The `Conflicts=` Discovery

**Most important learning from this project**:

```ini
[Unit]
Conflicts=shutdown.target reboot.target halt.target  ← CRITICAL!
Before=shutdown.target reboot.target halt.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStop=/path/to/shutdown-script.sh
```

**Why `Conflicts=` is required**:
- `Before=` alone does NOT trigger `ExecStop` during shutdown
- `Conflicts=` forces the service to stop when shutdown.target activates
- Without it, Docker containers die ungracefully (SIGKILL, no SIGTERM)

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for technical deep dive.

### 3-Phase Core Rationale

| Why Three Core Phases? | Benefit |
|------------------------|---------|
| **Phase 1: Graceful Shutdown** | Prevents data corruption (PostgreSQL checkpoints, Redis saves) |
| **Phase 2: Autostart** | Dependency ordering (SSH before VPN, Docker last) |
| **Phase 3: Verification** | Automated health checks (no manual recovery) |
| **Optional Phase 0: Pre-Reboot** | Baseline for recovery verification (compliance, audit trail) - requires customization |

**Alternative**: Manual reboots without orchestration → Downtime, data loss, no automated verification.

## Architecture Decisions: Modular vs. Monolithic

### What We Provide

This repository showcases **modular examples** to demonstrate different use cases:

| Example | Lines | Focus | Use Case |
|---------|-------|-------|----------|
| `autostart-minimal.sh` | ~66 | Learning | Understanding the basics |
| `autostart-docker-stack.sh` | ~167 | Containers | Docker-heavy setups |
| `autostart-network-gateway.sh` | ~209 | Networking | Routers/gateways |
| `autostart-database-server.sh` | ~200 | Databases | DB-centric servers |

### What We Use in Production

**Single monolithic script per device** (not in this repo):
- Pi 5 Router: 1443 LOC monolith (all 13 phases, device-specific)
- NAS Server: 1139 LOC monolith (all 13 phases, device-specific)

### Which Approach Should You Use?

#### ✅ Use Modular (Multiple Scripts)
- **Learning**: You're new to boot orchestration
- **Simple setups**: <10 services, 1-3 phases needed
- **Experimentation**: Testing different approaches
- **Mix & Match**: Combining phases from different examples

#### ✅ Use Monolithic (Single Script)
- **Production**: Mission-critical boot orchestration (recommended)
- **Complex setups**: 10+ services, dependencies, recovery logic
- **Atomic updates**: One file to version/deploy/rollback
- **Performance**: Faster execution (no file switches)

### Migration Path

1. **Start**: Use `autostart-minimal.sh` for learning
2. **Grow**: Copy relevant phases from other examples
3. **Mature**: Merge into single production script (like `autostart-template.sh`)
4. **Customize**: Adapt to your device-specific needs

### Trade-offs

| Aspect | Modular | Monolithic |
|--------|---------|------------|
| **Complexity** | Low per file | High overall |
| **Maintainability** | Harder (multiple files) | Easier (single source) |
| **Debugging** | Context switches | Single trace |
| **Deployment** | Multiple files | One file |
| **Learning Curve** | Gentle | Steep |
| **Production Ready** | Assembly required | ✅ Ready |

**Recommendation**: Use modular examples for learning, but **deploy as a monolith** in production.

## Requirements

**Minimum**:
- Linux with systemd 240+ (Debian 10+, Ubuntu 18.04+, RHEL 8+)
- Bash 4.0+
- Root/sudo access

**Component-specific**:
- Docker 19.03+ (if using Phase 1: Graceful Shutdown)
- Python 3.10+ (if using snapshot-compare.py)
- jq 1.5+ (if using JSON processing in custom scripts)

**Optional**:
- Prometheus + node_exporter (for boot metrics export)
- Telegram Bot (for reboot notifications)

## Compatibility

**Fully supported**:
- Ubuntu 22.04 LTS, 24.04 LTS
- Debian 11 (Bullseye), 12 (Bookworm)
- Raspberry Pi OS (Debian-based, ARM64)
- RHEL 8+, Rocky Linux 8+, Fedora 33+

**Partially supported** (no Docker graceful shutdown):
- Alpine Linux (busybox limitations)
- Non-systemd distros (requires custom init integration)

**Tested architectures**:
- x86_64 (AMD Ryzen, Intel Xeon)
- ARM64 (Raspberry Pi 5, other ARM servers)

## Use Cases

- ✅ **Docker Hosts** - Graceful container shutdown for database, cache, and app servers
- ✅ **Network Gateways** - 13-phase boot orchestration (network → VPN → routing → Docker)
- ✅ **Compliance** - Audit trail with pre/post snapshots and automated verification
- ✅ **CI/CD Pipelines** - JSON output and exit codes for automated testing
- ✅ **24/7 Production** - Zero-downtime reboots with automated recovery

## Real-World Results

**Proven in Production**:
- 🚀 **Network Gateway** (ARM64, Raspberry Pi 5, 6 containers): <90s boot, 100% success rate
- 🚀 **Docker Host** (x86_64, AMD Ryzen 9, 38 containers): <120s boot, 100% success rate
- 🚀 **50+ reboots** tested across ARM and x86_64 environments

**Key Metrics**:
- Graceful shutdown time: <5s (8 containers, parallel stops)
- Container restart success: 100%
- Data corruption incidents: 0
- Manual recovery required: 0

## Documentation

**Phase-specific**:

| Phase | Key Docs |
|-------|----------|
| Pre-Reboot | [0-pre-reboot/README.md](0-pre-reboot/README.md) - Snapshot format, extension API |
| Graceful Shutdown | [1-graceful-shutdown/README.md](1-graceful-shutdown/README.md) - systemd hook setup |
| Autostart | [2-autostart/README.md](2-autostart/README.md) - 13-phase model, customization |
| Verification | [3-verification/README.md](3-verification/README.md) - Health checks, snapshot comparison |

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

## See Also

- [bash-production-toolkit](https://github.com/fidpa/bash-production-toolkit) - 8 production-ready Bash libraries
- [ubuntu-server-security](https://github.com/fidpa/ubuntu-server-security) - 14-component security hardening
- [linux-monitoring-templates](https://github.com/fidpa/linux-monitoring-templates) - Bash/Python monitoring templates

## License

MIT License - see [LICENSE](LICENSE) for details.

## Author

Marc Allgeier ([@fidpa](https://github.com/fidpa))

**Why I Built This**: After a production PostgreSQL corruption incident caused by ungraceful reboot, I spent weeks debugging systemd shutdown hooks. The `Conflicts=` discovery was the breakthrough. This repo packages the 3-phase core solution (with optional snapshots) so you don't have to debug systemd internals.

## Contributing

Contributions welcome! Please open an issue or pull request.

**Areas where help is appreciated**:
- Additional autostart templates for specific stacks (LAMP, LEMP, Kubernetes)
- Health check examples for databases (MySQL, MongoDB, Elasticsearch)
- Snapshot extensions for hardware monitoring (temperature, disk I/O, network stats)
- Testing on additional Linux distributions (Alpine, Arch, OpenSUSE)
- Grafana dashboard examples for boot metrics

## Background

This project started after debugging why `ExecStop` hooks weren't running during reboot. The key finding: `Before=shutdown.target` alone doesn't trigger service stops—you need `Conflicts=shutdown.target` to force graceful shutdown.

The 3-phase workflow (graceful shutdown → autostart → verification) evolved from solving this problem on Docker hosts running PostgreSQL and Redis.
