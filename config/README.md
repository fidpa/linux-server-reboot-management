# Configuration Files

systemd service templates for Linux Server Reboot Management.

## Directory Structure

```
config/
├── systemd/      # Production-ready templates (copy & use as-is)
└── examples/     # Customization examples (copy, customize, then use)
```

## Quick Guide

### Use systemd/ Templates (Recommended)

**For most users - production-ready, minimal configuration:**

| File | Purpose | Customization |
|------|---------|---------------|
| `systemd/docker-graceful-shutdown.service` | Graceful container shutdown hook | ✅ Copy as-is (update path if needed) |

This is the only unit that can be used as-is, because `install.sh` installs the
script it points at. Boot orchestration is **not** in this category: the script
it runs is a per-machine one, so its unit lives in `examples/` below.

**Installation**:
```bash
# Graceful shutdown hook
sudo cp config/systemd/docker-graceful-shutdown.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable docker-graceful-shutdown
```

See [1-graceful-shutdown/README.md](../1-graceful-shutdown/README.md) and [2-autostart/README.md](../2-autostart/README.md) for detailed setup.

---

### Use examples/ Templates (Advanced)

**For custom setups - requires environment-specific modifications:**

| File | Use Case | Customization |
|------|----------|---------------|
| `examples/autostart.service` | 13-phase boot orchestration | ⚠️ Update: `ExecStart` path, `User`; adapt the template it points at first |
| `examples/docker-host.service` | Docker host (simple) | ⚠️ Update: `User`, `ExecStop` path, security settings |
| `examples/gateway-server.service` | Network gateway (complex) | ⚠️ Update: `User`, `ExecStop` path, `ReadOnlyPaths`, `Environment` |

**`examples/autostart.service` in particular**: its `ExecStart` is the
placeholder `/opt/yourdevice/autostart.sh` and no installer creates it. Point
it at your own adapted copy of `2-autostart/autostart-template.sh`. That
template refuses to run while its `TEMPLATE_UNCONFIGURED` marker is present, so
enabling this unit against an unedited copy fails at boot with exit code 78
instead of running generic phases as root.

**Differences from systemd/ templates**:
- Placeholder values (`youruser`, `/opt/yourdevice/`)
- Security hardening enabled (`ProtectSystem=strict`, `ReadWritePaths`)
- Environment variables for customization
- Device-specific paths

**When to use examples/**:
- ✅ You need security hardening (production environments)
- ✅ You use custom paths (not `/opt/linux-server-reboot-management/`)
- ✅ You run as non-root user
- ✅ You need custom environment variables

**Installation**:
```bash
# Copy and customize
cp config/examples/gateway-server.service /tmp/docker-graceful-shutdown.service
nano /tmp/docker-graceful-shutdown.service  # Update User, ExecStop, paths
sudo cp /tmp/docker-graceful-shutdown.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable docker-graceful-shutdown
```

See [docs/TEMPLATES.md](../docs/TEMPLATES.md) for customization guide.

---

## Troubleshooting

**"ExecStop script not found"**:
- Verify script path matches `ExecStop=` in service file
- Default: `/opt/linux-server-reboot-management/docker-graceful-shutdown.sh`
- Check with: `ls -la /opt/linux-server-reboot-management/`

**"Permission denied"**:
- Ensure script is executable: `sudo chmod +x /opt/linux-server-reboot-management/*.sh`
- Check `User=` setting matches script owner

See [docs/TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md) for more issues.

---

## See Also

- [docs/SETUP.md](../docs/SETUP.md) - Complete installation guide
- [docs/TEMPLATES.md](../docs/TEMPLATES.md) - Customization guide
- [1-graceful-shutdown/README.md](../1-graceful-shutdown/README.md) - Graceful shutdown hook
- [2-autostart/README.md](../2-autostart/README.md) - Autostart orchestration
