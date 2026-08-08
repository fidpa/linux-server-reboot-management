---
name: Feature Request
about: Suggest a new feature or improvement
title: '[FEATURE] '
labels: enhancement
assignees: ''
---

## Problem Statement

**What problem does this feature solve?**

Describe the use case or limitation you're facing — ideally the reboot that did
not go the way you needed it to.

## Scope

Which part of the workflow would this touch?

- [ ] Phase 0 — Pre-reboot snapshot
- [ ] Phase 1 — Graceful shutdown
- [ ] Phase 2 — Autostart orchestration
- [ ] Phase 3 — Post-reboot verification
- [ ] Extension API (custom metrics, health checks, boot phases)
- [ ] Installer, systemd units, or packaging
- [ ] Documentation

## Proposed Solution

**How should this work?**

- Where it hooks into the workflow (which phase, before or after what)
- Expected behavior on success and on failure
- New configuration variables or defaults, if any

## Example Usage

```bash
# How you envision using this — a unit drop-in, an extension hook,
# or a command line.
```

## Impact on Existing Setups

**Would this change the behavior of a host that upgrades without touching its
configuration?** Timeouts, retry counts, boot phase order and failure handling
all decide whether a server comes back up, so a changed default is never a
detail here. If the answer is yes, say what an operator would have to do before
their next reboot.

## Alternatives Considered

**What alternative solutions have you considered?**

Describe other approaches you've thought about and why they might not work as
well — including doing it with a plain systemd drop-in instead.

## Benefits

- Who would benefit from this?
- How common is this use case?
- Does it fit a tool whose job is to make reboots boring?

## Additional Context

Any other context or references (e.g., similar features in other projects).
