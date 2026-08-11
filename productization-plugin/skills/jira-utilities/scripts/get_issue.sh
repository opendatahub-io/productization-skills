#!/usr/bin/env bash
#
# Fetch a Jira issue by key.
#
# Usage:
#   ./get_issue.sh <issue_key>
#
# Example:
#   ./get_issue.sh PROJ-123
#
# Output: JSON issue object
# Exit codes: 0=success, 1=invalid params, 4=auth error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

if [[ $# -lt 1 ]]; then
    echo "Usage: $(basename "$0") <issue_key>" >&2
    echo "Example: $(basename "$0") PROJ-123" >&2
    exit 1
fi

KEY="$1"

if [[ ! "$KEY" =~ ^[A-Z][A-Z0-9_]+-[0-9]+$ ]]; then
    echo "ERROR: Invalid issue key format: '$KEY' (expected e.g. PROJ-123)" >&2
    exit 1
fi

ensure_auth

echo "Fetching issue $KEY..." >&2
TMPOUT=$(mktemp)
trap 'rm -f "$TMPOUT"' EXIT
acli jira workitem view "$KEY" --json > "$TMPOUT"
CLEAN=$(sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g; s/\r//g' "$TMPOUT")
jq '.' <<< "$CLEAN" 2>/dev/null \
    || sed -n '/^{/,/^}/p' <<< "$CLEAN" | jq '.'
