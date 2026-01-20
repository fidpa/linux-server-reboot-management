# Contributing to Linux Server Reboot Management

Thank you for your interest in contributing to Linux Server Reboot Management!

## How to Contribute

1. **Bug Reports**: Open an issue with steps to reproduce
2. **Feature Requests**: Open an issue describing the feature and use case
3. **Pull Requests**: Fork the repository, make changes, and submit a PR

## Development Setup

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/linux-server-reboot-management.git
cd linux-server-reboot-management

# Review documentation
cat README.md
cat docs/SETUP.md
```

## Code Style

### Bash Scripts

- Follow `set -uo pipefail` pattern (error handling)
- Use lowercase for variables, UPPERCASE for constants
- Quote variables: `"$var"` not `$var`
- Run `shellcheck` before submitting

Example:
```bash
#!/bin/bash
# SPDX-License-Identifier: MIT
set -uo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

### Python Scripts

- Follow PEP 8
- Use type hints (Python 3.10+): `dict[str, Any]`, `list[str]`, `str | None`
- Use `main() -> int` pattern with explicit exit codes
- Run `pylint` before submitting

Example:
```python
#!/usr/bin/env python3
# SPDX-License-Identifier: MIT

def main() -> int:
    """Main entry point."""
    # Your code here
    return 0

if __name__ == "__main__":
    sys.exit(main())
```

## Testing Your Changes

### Bash Scripts

```bash
# Syntax check
bash -n your-script.sh

# ShellCheck validation
shellcheck your-script.sh

# Manual test (dry-run if available)
./your-script.sh --dry-run
```

### systemd Services

```bash
# Validate service file
systemd-analyze verify your-service.service

# Test installation
sudo cp your-service.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl start your-service
```

## Pull Request Guidelines

- **One change per PR**: Keep PRs focused (bug fix OR feature, not both)
- **Tests**: Verify your changes work on a test system
- **Documentation**: Update relevant docs/ files if behavior changes
- **Commit messages**: Use clear, descriptive messages

Example commit:
```
fix: graceful-shutdown script timeout calculation

- Changed timeout from seconds to milliseconds
- Added validation for TIMEOUT_SECONDS variable
- Fixes #42
```

## Code of Conduct

This project adheres to the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md).
By participating, you are expected to uphold this code.

## Questions?

- Open an issue for questions about usage
- Check existing [documentation](docs/) first
- Email: [INSERT_EMAIL] for security issues (see [SECURITY.md](SECURITY.md))

---

Thank you for contributing to Linux Server Reboot Management!
