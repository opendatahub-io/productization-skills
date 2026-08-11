#!/usr/bin/env bash
#
# Calculate the next version string from a given version.
#
# Rules:
#   "3.4 GA"  → "3.4.1"    (first Z-stream patch after GA)
#   "3.3.2"   → "3.3.3"    (increment Z)
#   "3.4 EA1" → "3.4 EA2"  (increment EA number)
#
# Usage:
#   ./_next_version.sh "3.3.2"
#
# Output: next version string on stdout
# Exit codes: 0=success, 1=unrecognized format

set -euo pipefail

VERSION="${1:?Usage: _next_version.sh VERSION}"

if [[ "$VERSION" =~ ^([0-9]+\.[0-9]+)[[:space:]]EA([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]} EA$(( BASH_REMATCH[2] + 1 ))"
elif [[ "$VERSION" =~ ^([0-9]+\.[0-9]+)[[:space:]]GA$ ]]; then
    echo "${BASH_REMATCH[1]}.1"
elif [[ "$VERSION" =~ ^([0-9]+\.[0-9]+)\.([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]}.$(( BASH_REMATCH[2] + 1 ))"
else
    echo "ERROR: Unrecognized version format: '$VERSION'" >&2
    echo "Expected: '3.4 GA', '3.4 EA1', or '3.3.2'" >&2
    exit 1
fi
