#!/usr/bin/env bash
# ---
# SPDX-FileCopyrightText: 2026 Marc Allgeier
# SPDX-License-Identifier: MIT
# Repository: https://github.com/fidpa/linux-server-reboot-management
# ---
# Verify that every hardcoded version string in this repository agrees.
#
# The version appears in seven places across six files. Nothing generates them,
# so they can drift apart, and they did: after the 1.1.0 release most of them
# kept reporting the previous version for months, including the banner the
# installer prints on every run. This script is what makes that a failed check
# instead of a discovery.
#
# The README badge used to be an eighth site. It now reads the latest release
# from GitHub, so it cannot drift and is not checked here.
#
# Deliberately no literal version number anywhere in this file: the release
# procedure greps the tree for stale version strings, and a number quoted in a
# comment here would be a permanent false alarm in that scan.
#
# Usage:
#   .github/version-check.sh              # all strings agree with each other
#   .github/version-check.sh 1.2.0        # ... and with the given version,
#                                         #     which must have a changelog
#                                         #     section (used by release.yml)

set -euo pipefail

cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.."

# Each entry is "<file>|<sed expression printing the captured version>".
# A pattern that matches nothing is an error, not an absent version: it means
# the line was reworded and this check silently stopped covering that file.
readonly VERSION_SITES=(
    "install.sh|s/^# Version: ([0-9]+\.[0-9]+\.[0-9]+)$/\1/p"
    "install.sh|s/^.*Installer v([0-9]+\.[0-9]+\.[0-9]+)\".*$/\1/p"
    "0-pre-reboot/system-snapshot.sh|s/^# Version: ([0-9]+\.[0-9]+\.[0-9]+)$/\1/p"
    "1-graceful-shutdown/docker-graceful-shutdown.sh|s/^# Version: ([0-9]+\.[0-9]+\.[0-9]+)$/\1/p"
    "3-verification/post-reboot-check.sh|s/^# Version: ([0-9]+\.[0-9]+\.[0-9]+)$/\1/p"
    "3-verification/snapshot-compare.py|s/^# Version: ([0-9]+\.[0-9]+\.[0-9]+)$/\1/p"
    "docs/README.md|s/^\*\*Version\*\*: ([0-9]+\.[0-9]+\.[0-9]+)$/\1/p"
)

expected="${1:-}"
failed=0
declare -A seen=()

for site in "${VERSION_SITES[@]}"; do
    file="${site%%|*}"
    expression="${site#*|}"

    if [[ ! -f "$file" ]]; then
        echo "MISSING  $file (listed in version-check.sh, not in the repository)"
        failed=1
        continue
    fi

    mapfile -t found < <(sed -nE "$expression" "$file")

    if [[ ${#found[@]} -eq 0 ]]; then
        echo "NO MATCH $file (version line reworded? this file is now unchecked)"
        failed=1
        continue
    fi

    for version in "${found[@]}"; do
        printf '%-48s %s\n' "$file" "$version"
        seen["$version"]+="$file "
    done
done

if [[ ${#seen[@]} -gt 1 ]]; then
    echo
    echo "Version strings disagree:"
    for version in "${!seen[@]}"; do
        echo "  $version <- ${seen[$version]}"
    done
    failed=1
fi

if [[ -n "$expected" ]]; then
    echo
    if [[ -n "${seen[$expected]:-}" && ${#seen[@]} -eq 1 ]]; then
        echo "OK: all version strings match the requested version $expected"
    else
        echo "Requested version $expected is not what the files say"
        failed=1
    fi

    if grep -qE "^## \[${expected//./\\.}\]" CHANGELOG.md; then
        echo "OK: CHANGELOG.md has a section for $expected"
    else
        echo "CHANGELOG.md has no '## [$expected]' section"
        failed=1
    fi
fi

if [[ $failed -ne 0 ]]; then
    echo
    echo "Bump every site listed above together, then re-run this check."
    exit 1
fi

echo
echo "OK: all version strings agree"
