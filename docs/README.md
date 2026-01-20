# Documentation

Complete documentation for Linux Server Reboot Management.

## 📚 Reading Order

**For first-time users**:

1. [SETUP.md](SETUP.md) - Installation and configuration
2. [WORKFLOW.md](WORKFLOW.md) - Understanding the 3-phase reboot workflow
3. [ARCHITECTURE.md](ARCHITECTURE.md) - How systemd shutdown hooks work
4. [TEMPLATES.md](TEMPLATES.md) - Customizing scripts for your environment
5. [VERIFICATION.md](VERIFICATION.md) - Post-reboot health checks
6. [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues and solutions
7. [INDUSTRY_COMPARISON.md](INDUSTRY_COMPARISON.md) - How this compares to enterprise solutions

**Quick reference**:
- Problem? → [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- Installation? → [SETUP.md](SETUP.md)
- Customization? → [TEMPLATES.md](TEMPLATES.md)

---

## 📖 Documentation Index

### [SETUP.md](SETUP.md)

**Installation and configuration guide**

Complete step-by-step installation instructions including prerequisites, systemd service configuration, and verification steps.

**Key topics**:
- Prerequisites (Linux, Docker, systemd, Bash)
- Installation steps
- systemd service configuration
- Environment variables
- Verification

---

### [WORKFLOW.md](WORKFLOW.md)

**3-phase reboot workflow explained**

Comprehensive guide to the production reboot management workflow covering all four phases.

**Key topics**:
- Optional Phase 0: Pre-reboot snapshots
- Phase 1: Graceful shutdown
- Phase 2: Autostart orchestration
- Phase 3: Post-reboot verification
- Timeline diagrams

---

### [ARCHITECTURE.md](ARCHITECTURE.md)

**Deep dive into systemd shutdown hooks**

Technical explanation of how graceful shutdown hooks work with systemd, including the critical `Conflicts=` pattern.

**Key topics**:
- The core problem with Docker and reboots
- The `Conflicts=` pattern (and why `Before=` alone doesn't work)
- systemd timeline visualization
- Alternative approaches

---

### [TEMPLATES.md](TEMPLATES.md)

**Template customization guide**

How to adapt the provided templates for your specific environment and use case.

**Key topics**:
- System snapshot customization
- Extension API for custom metrics
- Autostart template selection (minimal vs full)
- Helper functions reference
- Example customizations

---

### [VERIFICATION.md](VERIFICATION.md)

**Post-reboot verification checklist**

Automated and manual verification steps to ensure successful reboot.

**Key topics**:
- Quick verification (30 seconds)
- Full verification script
- Manual verification steps
- Container health checks
- Network connectivity verification
- Snapshot comparison

---

### [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

**Common issues and solutions**

Diagnostic commands and fixes for common problems with graceful shutdown and reboot management.

**Key topics**:
- Hook not running (missing `Conflicts=`)
- Containers not restarting
- Timeout issues
- Permission errors
- Data corruption
- Service won't start

---

### [INDUSTRY_COMPARISON.md](INDUSTRY_COMPARISON.md)

**How this compares to industry standard approaches**

Analysis of different reboot management strategies used by enterprises, cloud providers, and DevOps teams.

**Key topics**:
- Enterprise cloud providers (Google, AWS, Meta)
- Kubernetes orchestration
- Configuration management (Ansible, Terraform)
- Managed hosting providers
- When to use this system vs alternatives
- Complexity vs. benefit trade-offs

---

## 🔗 Related Documentation

- [← Back to Root README](../README.md) - Project overview, quick start, features
- [LICENSE](../LICENSE) - MIT License
- [CONTRIBUTING.md](../CONTRIBUTING.md) - How to contribute
- [SECURITY.md](../SECURITY.md) - Security policy and vulnerability disclosure

---

## 📝 Documentation Standards

This documentation follows these principles:

- **TL;DR sections**: 20-word summaries at the top of each document
- **Code examples**: Real, tested examples (no placeholders)
- **Progressive disclosure**: Essential info upfront, details on demand
- **Cross-references**: Bidirectional links between related topics
- **Verification steps**: Always include "how to test this works"

---

**Version**: 1.0.0
**Last Updated**: 2026-01-20
**Maintainer**: Marc Allgeier ([@fidpa](https://github.com/fidpa))
