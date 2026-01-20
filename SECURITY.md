# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Linux Server Reboot Management, please report it responsibly:

**Email**: security@fidpa.dev (or open a [GitHub Security Advisory](https://github.com/fidpa/linux-server-reboot-management/security/advisories/new))

We will respond within 72 hours and provide a timeline for fixes.

**Please do NOT open a public issue for security vulnerabilities.**

## What to Include

When reporting a vulnerability, please provide:

- **Description**: What is the vulnerability?
- **Impact**: What can an attacker do with this vulnerability?
- **Reproduction Steps**: How can we reproduce the issue?
- **Affected Versions**: Which versions are impacted?
- **Suggested Fix** (optional): Your proposed solution

## Response Process

1. We confirm receipt of your report within 72 hours
2. We assess severity (Low/Medium/High/Critical)
3. We develop and test a fix
4. We notify you when the fix is ready
5. We coordinate public disclosure after fix is deployed
6. We credit you in the release notes (unless you prefer anonymity)

## Supported Versions

| Version | Supported | Notes |
|---------|-----------|-------|
| 1.x     | ✅ Yes    | Active development |
| < 1.0   | ❌ No     | Please upgrade to 1.x |

## Out of Scope

The following are **NOT** considered security vulnerabilities:

- Issues requiring root/sudo access (this project is designed for system administrators with root access)
- Misconfiguration of systemd services by the user
- Docker container vulnerabilities (report to container maintainers)
- Physical access attacks

## Security Best Practices

When using this project:

- ✅ Review all scripts before installation (`shellcheck`, manual audit)
- ✅ Test in a non-production environment first
- ✅ Use principle of least privilege (dedicated service users when possible)
- ✅ Monitor systemd logs: `journalctl -u docker-graceful-shutdown`
- ✅ Keep Docker and systemd up to date

---

Thank you for helping keep Linux Server Reboot Management secure!
