---
name: Bug Report
about: Report a bug to help us improve
title: '[BUG] '
labels: bug
assignees: ''
---

## Bug Description

**Clear and concise description of the bug**

## Affected Phase

- [ ] Phase 0 — Pre-reboot snapshot (`0-pre-reboot/system-snapshot.sh`)
- [ ] Phase 1 — Graceful shutdown (`1-graceful-shutdown/docker-graceful-shutdown.sh`)
- [ ] Phase 2 — Autostart orchestration (`2-autostart/autostart-template.sh`)
- [ ] Phase 3 — Post-reboot verification (`3-verification/post-reboot-check.sh`)
- [ ] Snapshot comparison (`3-verification/snapshot-compare.py`)
- [ ] Installer (`install.sh`) or systemd units (`config/`)
- [ ] Documentation

## Steps to Reproduce

1. Install with: `./install.sh`
2. Run the script or trigger the reboot: `sudo systemctl reboot`
3. Observe the error

## Expected Behavior

What you expected to happen.

## Actual Behavior

What actually happened. **If a host failed to come back up or a container did
not restart, say so explicitly** — those are the failures we care about most.

## Environment

- **Version**: (see `CHANGELOG.md` or the tag you installed, e.g. v1.1.0)
- **OS**: (e.g., Ubuntu 24.04, Debian 12)
- **Bash Version**: (run `bash --version`)
- **systemd Version**: (run `systemctl --version`)
- **Docker Version**: (run `docker --version`, if applicable)
- **Architecture**: (e.g., x86_64, ARM64)
- **Install path**: (default `/opt/linux-server-reboot-management`)

## Logs

Journal output is usually the most useful thing you can attach. Please redact
hostnames, IP addresses and container names you do not want to publish.

```bash
# For the shutdown hook:
journalctl -u docker-graceful-shutdown.service -b -1 --no-pager

# For the autostart orchestration:
journalctl -u autostart.service -b --no-pager
```

```text
# Paste the relevant output here
```

## Unit Configuration

If a systemd unit is involved, paste the unit or drop-in you are running
(`systemctl cat <unit>`), with any custom timeouts or environment overrides.

```ini
# Paste unit configuration here
```

## Additional Context

Any other context about the problem (e.g., related issues, workarounds tried,
whether the host recovered on a second reboot).
