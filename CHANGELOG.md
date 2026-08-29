# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.3.4] - 2026-08-30: The README describes the scripts that are in the repository

A full pass over `README.md`, facts first and language second. Three claims did not
survive the comparison with the code. The worst was a mechanism, not a number: the
README advertised "<5s (8 containers, parallel stops)", while
`1-graceful-shutdown/docker-graceful-shutdown.sh` stops containers in a `while read`
loop, one after another. A reader sizing a shutdown window from that line would have
budgeted for the slowest container instead of the sum of all of them. Alongside the
corrections, the two surfaces an operator configures were missing from the README
entirely: the environment variables and the command-line interfaces.

### Changed

- **The shutdown timing statement describes the loop that exists.** The stops are
  sequential, so a stack of slow containers adds up rather than overlapping, and a
  container that ignores SIGTERM costs up to `GRACEFUL_SHUTDOWN_TIMEOUT` seconds on
  its own. The "parallel stops" wording is gone from `README.md` and the limitation is
  named in the new Known-limitations block.
- **The line counts name their counting rule.** The five template sizes lost their
  approximation tilde and now say what was counted: `wc -l` on the file, licence header
  and comments included. All five values were measured and were already correct.
- **The sibling-project reference states the right number.** `bash-production-toolkit`
  ships ten libraries; the See Also entry claimed eight.
- **The README documents the configuration surface.** A table of all sixteen
  environment variables, each with the script that reads it and its default, from
  `GRACEFUL_SHUTDOWN_TIMEOUT` and `INSTALL_DIR` through the four `ENABLE_*` flags of
  `2-autostart/autostart-template.sh` to `SNAPSHOT_DIR` and `DOCKER_SERVICE_NAME`.
- **The README documents the command-line interfaces.** The `--help` output of
  `3-verification/snapshot-compare.py` verbatim as argparse prints it, the options and
  the five exit codes of `3-verification/post-reboot-check.sh`, and the argument
  validation of `0-pre-reboot/system-snapshot.sh`, which accepts `pre-reboot` and
  `post-reboot` and nothing else.
- **`install.sh` appears in the Quick Start.** The installer has existed since 1.1.0,
  but the Quick Start still walked through the `mkdir`, `cp`, `daemon-reload` and
  `enable` steps that it performs, so the shorter and checked path was invisible to
  anyone reading only the README.
- **Limits stand next to the features.** A Known-limitations block after the feature
  list names the `TEMPLATE_UNCONFIGURED` refusal of `autostart-template.sh` (exit 78,
  `EX_CONFIG`), the single-node scope, the absence of a rollback when a boot phase
  fails halfway, and the fact that the hook reaches Docker containers only.
- **Compatibility separates what was tested from what should work.** The previous
  "Fully supported" list named seven distributions, and nothing in the repository
  records a reboot cycle on any of them beyond the two machines the project runs on.
  Those two are now the tested tier; Ubuntu, Debian 11 and 12, RHEL, Rocky and Fedora
  moved to "Should work, untested".
- **The production numbers carry their measurement conditions.** They come from two
  private machines rather than a test suite, and the section says so. The 120s figure
  is tied to `MAX_BOOT_TIME` in the template, which is where it comes from.
- **The production-setup note in `2-autostart/README.md` describes a device class, not
  the operator's inventory.** The Pi 5 router line named a "Pi Zero fleet integration",
  which inventories one particular installation the same way the passages corrected in
  `docs/ARCHITECTURE.md` for 1.2.0 did; that pass did not reach this file. It now reads
  "single-board device fleet integration".
- **The prose was rewritten against the workbench README standard.** The
  `**The Problem**:` template opening, the feature bullets that asserted a stance
  ("Zero Data Loss", "Production-Proven", "CI/CD Ready") rather than naming a fact, and
  the threefold retelling of the `Conflicts=` discovery across Key Concepts, Author and
  Background. The `Background` section is dissolved into the two places that already
  told the story. `CHANGELOG.md`, `SECURITY.md`, `CONTRIBUTING.md` and
  `CODE_OF_CONDUCT.md` are linked from the documentation section instead of going
  unmentioned.

## [1.3.3] - 2026-08-28: GitHub identifies the project as MIT-licensed

### Changed

- **The repository page shows the MIT licence, and licence-filtered searches
  find the project.** `LICENSE` carried the repository URL on its own line
  under the copyright notice. GitHub reads a licence text with an extra line as
  modified and reports `NOASSERTION`, which leaves the licence field on the
  repository page empty. The line is gone; the MIT text and the copyright
  notice are byte-for-byte unchanged, and the URL is still in `README.md`.

## [1.3.1] - 2026-08-27: Release notes match the tag they are published under

An editorial pass over the whole changelog. The older sections were checked against the
tags they describe and corrected where the tree contradicted them; the corrections are
listed below, each as its own entry. No shipped behaviour changed: the scripts, the units
and the documentation are the same as in 1.3.0, and every measured value, path and
function name in the older sections was kept.

### Changed

- **Release titles no longer repeat the version number.** `release.yml` reads the
  headline from the changelog heading (`## [X.Y.Z] - YYYY-MM-DD: <headline>`) and passes
  it to `softprops/action-gh-release` as `name`. Without it the action falls back to the
  tag, which is what the five published releases showed. A heading without a headline
  logs a warning in the workflow instead of silently falling back
- **The release body no longer starts with a blank line.** The extraction step strips
  leading blank lines (`sed -e '/./,$!d'`), so the published body is a byte-for-byte copy
  of its changelog section
- **The compare links for the two January sections resolve.** They referenced a `v1.0.0`
  tag that was never pushed, so both answered with 404. `[1.0.0]` now points at the
  initial commit and `[1.1.0]` compares that commit against its tag. No tag was created
  or moved
- **The 1.1.0 section lists what that release actually shipped.** `install.sh`,
  `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md` and `docs/README.md` arrived
  with that tag and were named nowhere; `install.sh` was credited to the initial release,
  whose tree does not contain it
- **The 1.1.1 section names the three scripts whose version line moved.** It claimed four
  phase scripts; `2-autostart/autostart-template.sh` carries no `# Version:` line and was
  not touched by that release
- **The 1.1.2 section says which version strings were stale and for how long.** The seven
  places covered by `.github/version-check.sh` reported 1.0.0; the README badge, which
  that section counts separately as the eighth site, reported 1.1.0. The gap between the
  1.1.0 and 1.1.1 releases was six months, not seven
- **Every entry now opens with what the release changes for the operator**, and the
  implementation follows in the paragraph. Each section also opens with the incident it
  belongs to. Em dashes and the arrow character were replaced by the punctuation or the
  word they stood for

## [1.3.0] - 2026-08-11: The autostart template refuses to boot unadapted

`config/systemd/autostart.service` was documented as a copy-and-enable unit while its
`ExecStart` pointed at `/opt/linux-server-reboot-management/2-autostart/autostart-template.sh`,
a path no installer creates. Anyone who followed that recipe got a unit that failed at
every boot. The template itself is a 13-phase reference implementation meant to be
adapted, so the failure mode on the other side is worse: a unit that does start, running
generic reference phases as root.

### Added
- **`autostart-template.sh` refuses to run while it is unadapted.** The
  `CONFIGURATION` block carries a `TEMPLATE_UNCONFIGURED=true` marker; while it
  is present the script exits 78 (`EX_CONFIG`) with an explanation on stderr and
  in the journal, before touching the system. Delete the line once the phases
  match the machine

### Changed
- **The autostart unit is now an example, not a recipe.**
  `config/systemd/autostart.service` moved to `config/examples/autostart.service`. Boot
  orchestration is a per-machine script by design, so its unit belongs with the other
  units that must be adapted before use
- **The unit no longer looks installed.** `ExecStart` is the placeholder
  `/opt/yourdevice/autostart.sh`, matching the convention the `examples/` units already
  use. The previous value read as a working default
- **`config/README.md` no longer offers boot orchestration as production-ready** and
  drops the copy-and-enable recipe for it. The `systemd/` table now holds only
  the graceful shutdown hook, which is the one unit whose target `install.sh`
  actually installs
- **The quick start in `2-autostart/README.md` deploys to a path the operator owns.** It
  tests the script by hand before enabling the unit and names the marker step; it
  previously created the mismatched `/opt/.../2-autostart/` path and enabled the unit
  before any manual run
- **Sourcing the template no longer runs the whole orchestration.** `main` runs behind a
  `${BASH_SOURCE[0]} == ${0}` guard, so `source autostart-template.sh`, the documented
  way to test individual phases, no longer executes all 13 phases in the caller's shell
- Deployment examples in `docs/ARCHITECTURE.md` and `docs/TEMPLATES.md` cover
  the marker and the manual verification run
- Line counts for `autostart-template.sh` in `README.md` and
  `2-autostart/README.md` corrected to 864

### Upgrade notes

- **Existing deployments are unaffected and need no action.** The marker lives
  in the repository template, not in your adapted copy: a script you already
  customized has no `TEMPLATE_UNCONFIGURED` line and keeps running unchanged.
  Only a fresh copy of the template carries it
- **If you copy the template again**, delete the `TEMPLATE_UNCONFIGURED` line
  after adapting the phases, or the next boot logs `exit 78` and starts nothing
- **If you script the unit installation**, the copy source changed from
  `config/systemd/autostart.service` to `config/examples/autostart.service`. The
  unit is no longer usable unedited; set `ExecStart` to your own script path
- **If you enabled the unit as shipped**, it pointed at a path that does not
  exist and the service has been failing at boot. Check with
  `systemctl status autostart` and set `ExecStart` to your adapted script

## [1.2.0] - 2026-08-11: Emergency recovery no longer claims an unconfigured address

`minimal_recovery_mode()` is what runs when the boot orchestration has already failed. It
assigned a hardcoded `192.168.1.100`, a value from the most common home subnet that the
operator had no way of setting without editing the function, and it printed that address
as the one to connect to. On a host
whose subnet differs, that is an address nobody can reach, announced at the moment the
operator is least able to check.

### Added
- **The recovery interface and address are configurable without editing the script.**
  `RECOVERY_INTERFACE` and `RECOVERY_IP` are configuration variables in the autostart
  template, overridable from the environment like the existing feature flags. Both
  previously had to be edited inside `minimal_recovery_mode()`

### Changed
- **Emergency recovery no longer assigns an unconfigured address.** `RECOVERY_IP`
  ships as `192.0.2.100`, an RFC 5737 documentation address. While it is
  unchanged, recovery mode logs it as unconfigured and skips the `ip addr add`
  instead of claiming the address. SSH is still started, so a DHCP lease on the
  interface remains usable, and the recovery log names the interface to check
  rather than printing an address nobody can reach
- **Documentation addresses can no longer be mistaken for working values.** The snapshot
  example gateway in `0-pre-reboot/README.md` and the NAT subnet in
  `autostart-network-gateway.sh` were RFC 1918 addresses from the most common home
  subnet; the examples use RFC 5737 addresses throughout
- **The architecture comparison describes the production stack by function**
  (file-sync service, secrets manager, VPN tunnel) rather than by product name
- **`docs/TEMPLATES.md` survives edits to the template.** It points at the
  `CONFIGURATION` block by name instead of a line range, which the added variables
  would have invalidated

### Upgrade notes

- **Set `RECOVERY_IP` before the next reboot if you rely on emergency recovery.**
  Hosts that used the previous hardcoded `192.168.1.100`, whether as-is or
  because it happened to fit their subnet, will no longer get that address
  assigned when recovery mode triggers. Export `RECOVERY_IP` (and
  `RECOVERY_INTERFACE` if not `eth0`) in the unit drop-in, or edit the
  `CONFIGURATION` block in your copy of the template. Recovery mode logs loudly
  when the placeholder is still in place, but it logs at the moment you are
  least able to read it
- Copies of `autostart-network-gateway.sh` keep their own `lan_subnet`; the
  changed example does not reach an already-customized script

## [1.1.2] - 2026-08-11: A failed check instead of a discovery for stale version strings

The version appears in seven hardcoded places across six files, and nothing generates
them. After the 1.1.0 release all seven kept reporting 1.0.0, including the banner
`install.sh` prints on every run, and stayed that way for the six months until 1.1.1.
Nothing was watching for it. The same pass found that seven of the twelve scripts in the
tree had never been marked executable, although the documentation invokes them as
`./name`.

### Added
- **A wrong version number now fails the build instead of shipping.**
  `.github/version-check.sh` verifies that the seven hardcoded version strings
  across six files agree with each other, and, when given a version, that they
  match it and that the changelog has a section for it. It runs as a third job in the
  lint workflow and as a step in the release workflow before the release is cut, so a
  tag whose version the files do not carry fails instead of publishing. A reworded
  version line fails the check as loudly as a wrong number: a pattern that
  matches nothing means that file silently stopped being covered
- **`CONTRIBUTING.md` documents the release check.** A `Releasing` section describes the
  version sites and how to verify them before tagging

### Changed
- **The README version badge cannot go stale.** It reads the latest release from GitHub
  instead of carrying a hardcoded number. It was the eighth place the version had to be
  maintained by hand, and it is deliberately not covered by `version-check.sh`
- **`.shellcheckrc` now states the severity that is actually enforced.** It declared
  `severity=warning` while the lint workflow passes `--severity=error` on the command
  line, which wins, so the file documented a standard nothing enforced. It also lists the
  three known SC2034 findings a manual `warning` run produces

### Fixed
- **A fresh clone answered the first command after the reboot with "Permission denied".**
  Seven of the twelve scripts were not executable, among them `install.sh`,
  `system-snapshot.sh`, `post-reboot-check.sh` and `snapshot-compare.py`. Every
  one of those is invoked as `./name` in the documentation, including step 5 of
  the README quick start. The mode is now `100755` in the index for all of them
- **`docs/README.md` no longer claims a last-updated date from before the 1.1.1 release**

## [1.1.1] - 2026-08-08: Release pages carry the changelog instead of a bare link

The 1.1.0 release page showed a single "Full Changelog" link and none of the actual
changes, because the notes were generated from commit messages and this repository's
commit messages are bare version numbers. The same release had left the version strings
behind: the installer greeted users with "Installer v1.0.0" months after 1.1.0 shipped.

### Added
- **Issue reports arrive with the context this workflow needs.** Templates for bug
  reports and feature requests ask for the affected phase, journal commands, unit
  configuration and the impact on existing setups
- **Pull requests carry a testing and documentation checklist**

### Changed
- **Release notes are extracted from this changelog** instead of being generated from
  commit messages, so a release page shows what changed rather than a link to the diff
- **`.shellcheckrc` header describes this repository** instead of an unrelated
  multi-device setup

### Fixed
- **The installer no longer announces a version it is not.** The version strings in
  `install.sh`, `0-pre-reboot/system-snapshot.sh`,
  `1-graceful-shutdown/docker-graceful-shutdown.sh`,
  `3-verification/post-reboot-check.sh`, `3-verification/snapshot-compare.py` and
  `docs/README.md` were still reporting 1.0.0 after the 1.1.0 release
- **The template listing in `install.sh` pointed at a path that does not exist**,
  `2-autostart/autostart-minimal.sh` instead of
  `2-autostart/examples/autostart-minimal.sh`
- **The issue chooser no longer offers a dead link.** A "Question or Discussion" contact
  pointed at GitHub Discussions, which is not enabled for this repository

## [1.1.0] - 2026-01-20: Installer, contribution policy and CI

The initial release shipped the scripts and the documentation, but nothing to put them on
a machine with and no gate on what got committed. This release adds both, plus the
repository policy files a public project needs.

### Added
- **The graceful shutdown hook can be installed with one command.** `install.sh` copies
  `docker-graceful-shutdown.sh` to `/opt/linux-server-reboot-management`, installs and
  enables its systemd unit, and checks for systemd 240 or later first. The other three
  phases stay manual, because they are adapted per machine
- **Contributions have a documented process.** `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`
  and `SECURITY.md` state how to contribute, what is expected and where to report a
  vulnerability
- **The documentation has an entry point.** `docs/README.md` indexes the seven documents
  under `docs/`
- **Shell scripts are linted on every push and pull request.** A GitHub Actions workflow
  runs ShellCheck, with `.shellcheckrc` holding the settings so a local run matches CI
- **Version tags publish a GitHub release automatically**

## [1.0.0] - 2026-01-17: Three-phase reboot workflow

A planned reboot of a service host is three problems, not one: knowing what ran before,
shutting it down without corrupting state, and proving afterwards that everything came
back. This release covers all three as separate, individually usable scripts.

### Added
- **Phase 1 shuts Docker down gracefully.** `docker-graceful-shutdown.sh` stops every
  running container with `docker stop --time` (`CONTAINER_TIMEOUT`, default 30 s) and
  calls `sync` afterwards, instead of leaving the containers to the system shutdown
  timeout. It warns for each container with `restart=unless-stopped`, which will not come
  back on its own after the reboot
- **Phase 2 orchestrates service startup.** `autostart-template.sh` is a 13-phase
  reference implementation to be adapted per machine, with four focused example scripts
  for common setups
- **Phase 3 verifies the machine came back.** `post-reboot-check.sh` compares the running
  state against expectations and reports per check
- **Phase 0 records the state to compare against.** `system-snapshot.sh` takes an
  optional pre-reboot snapshot, and `snapshot-compare.py` diffs it against the state
  after the reboot
- **Custom metrics, health checks and boot phases can be added without forking.** An
  extension API loads operator-supplied functions; `snapshot-extensions-example.sh` shows
  the shape
- **Results can be consumed by CI.** The verification scripts emit JSON alongside their
  human-readable output and set exit codes accordingly, with escaping for special
  characters in container names and status strings
- **systemd integration ships with the scripts**, including drop-in configurations
- **The documentation covers deployment, not just usage:** setup, architecture,
  templates, workflow, verification and troubleshooting

[Unreleased]: https://github.com/fidpa/linux-server-reboot-management/compare/v1.3.4...HEAD
[1.3.4]: https://github.com/fidpa/linux-server-reboot-management/compare/v1.3.3...v1.3.4
[1.3.3]: https://github.com/fidpa/linux-server-reboot-management/compare/v1.3.1...v1.3.3
[1.3.1]: https://github.com/fidpa/linux-server-reboot-management/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/fidpa/linux-server-reboot-management/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/fidpa/linux-server-reboot-management/compare/v1.1.2...v1.2.0
[1.1.2]: https://github.com/fidpa/linux-server-reboot-management/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/fidpa/linux-server-reboot-management/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/fidpa/linux-server-reboot-management/compare/141baef...v1.1.0
[1.0.0]: https://github.com/fidpa/linux-server-reboot-management/commit/141baef
