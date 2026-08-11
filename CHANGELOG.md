# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.2] - 2026-08-11

### Added
- `.github/version-check.sh`: verifies that the seven hardcoded version strings
  across six files agree with each other, and, when given a version, that they
  match it and that the changelog has a section for it. Wired into the lint
  workflow as a third job and into the release workflow as a step before the
  release is cut, so a tag whose version the files do not carry fails instead
  of publishing. This is the check that was missing when every version string
  kept reporting 1.0.0 for the seven months after the 1.1.0 release. A reworded
  version line fails the check as loudly as a wrong number: a pattern that
  matches nothing means that file silently stopped being covered
- A `Releasing` section in `CONTRIBUTING.md` describing the version sites and
  how to verify them before tagging

### Changed
- **The README version badge now reads the latest release from GitHub** instead
  of carrying a hardcoded number. It was the eighth place the version had to be
  maintained by hand; it is now the only one that cannot go stale, and it is
  deliberately not covered by `version-check.sh`
- `.shellcheckrc` declared `severity=warning` while the lint workflow passes
  `--severity=error` on the command line, which wins. The file documented a
  standard nothing enforced, and now states the one that is enforced, along with
  the three known findings a manual `warning` run produces

### Fixed
- **Seven of the twelve scripts were not executable**, among them `install.sh`,
  `system-snapshot.sh`, `post-reboot-check.sh` and `snapshot-compare.py`. Every
  one of those is invoked as `./name` in the documentation, including step 5 of
  the README quick start, so a fresh clone answered the first command after the
  reboot with "Permission denied". The mode is now `100755` in the index for all
  of them
- `docs/README.md` claimed a last-updated date from before the 1.1.1 release

## [1.1.1] - 2026-08-08

### Added
- Issue templates for bug reports and feature requests, tailored to the
  three-phase reboot workflow (affected phase, journal commands, unit
  configuration, impact on existing setups)
- Pull request template with a testing and documentation checklist

### Changed
- Release notes are now extracted from this changelog instead of being
  generated from commit messages. The v1.1.0 release page carried a single
  "Full Changelog" link and none of the actual changes, because the commit
  history consists of bare version numbers
- `.shellcheckrc` header now describes this repository instead of an unrelated
  multi-device setup

### Fixed
- Version strings across `install.sh`, all four phase scripts,
  `snapshot-compare.py` and `docs/README.md` were still reporting 1.0.0 after
  the 1.1.0 release. The installer greeted users with "Installer v1.0.0"
- Template listing in `install.sh` pointed to `2-autostart/autostart-minimal.sh`
  instead of `2-autostart/examples/autostart-minimal.sh`
- Removed a "Question or Discussion" contact link from the issue chooser that
  pointed to GitHub Discussions, which is not enabled for this repository

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

[Unreleased]: https://github.com/fidpa/linux-server-reboot-management/compare/v1.1.2...HEAD
[1.1.2]: https://github.com/fidpa/linux-server-reboot-management/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/fidpa/linux-server-reboot-management/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/fidpa/linux-server-reboot-management/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/fidpa/linux-server-reboot-management/releases/tag/v1.0.0
