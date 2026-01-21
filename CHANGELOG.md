# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0] - 2026-01-20

### Added
- CI/CD pipeline with GitHub Actions
- ShellCheck linting on push and pull requests
- Automatic GitHub releases for version tags
- `.shellcheckrc` configuration for consistent linting

## [1.0.0] - 2026-01-17

### Added
- Initial release with 3-phase reboot workflow
- Phase 0: Optional pre-reboot system snapshots (system-snapshot.sh)
- Phase 1: Graceful Docker shutdown (docker-graceful-shutdown.sh)
- Phase 2: Automated service startup orchestration (autostart-template.sh with 13 phases)
- Phase 3: Post-reboot verification (post-reboot-check.sh)
- Extension API for custom metrics, health checks, and boot phases
- Production documentation with 4 example configurations
- One-line installer (install.sh)
- systemd integration with drop-in configurations
- JSON output for CI/CD integration
- Proper escaping for special characters in container names/status

[Unreleased]: https://github.com/fidpa/linux-server-reboot-management/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/fidpa/linux-server-reboot-management/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/fidpa/linux-server-reboot-management/releases/tag/v1.0.0
