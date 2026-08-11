#!/usr/bin/env bash
#
# Create a link between two Jira issues.
#
# Usage:
#   ./link_issues.sh <inward_key> <outward_key> [--link-type TYPE]
#
# Arguments:
#   inward_key    Source issue key (e.g., PROJ-123)
#   outward_key   Target issue key (e.g., PROJ-456)
#
# Options:
#   --link-type TYPE   Relationship type (default: "Relates")
#                      Common types: Blocks, Duplicates, Relates, Clones
#                      Run: acli jira workitem link type  — to list all available types
#
# Examples:
#   ./link_issues.sh PROJ-123 PROJ-456
#   ./link_issues.sh PROJ-123 PROJ-456 --link-type Blocks
#   ./link_issues.sh PROJ-789 PROJ-123 --link-type Duplicates
#
# Output: JSON {"linked": ["PROJ-123", "PROJ-456"], "type": "Blocks"}
# Exit codes: 0=success, 1=invalid params, 2=API error, 4=auth error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

LINK_TYPE="Relates"

if [[ $# -lt 2 ]]; then
    echo "Usage: $(basename "$0") <inward_key> <outward_key> [--link-type TYPE]" >&2
    exit 1
fi

INWARD_KEY="$1"; shift
OUTWARD_KEY="$1"; shift

while [[ $# -gt 0 ]]; do
    case "$1" in
        --link-type) LINK_TYPE="$2"; shift 2 ;;
        *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    esac
done

# Validate key format
for key in "$INWARD_KEY" "$OUTWARD_KEY"; do
    if [[ ! "$key" =~ ^[A-Z][A-Z0-9_]+-[0-9]+$ ]]; then
        echo "ERROR: Invalid issue key format: '$key' (expected e.g. PROJ-123)" >&2
        exit 1
    fi
done

ensure_auth

echo "Linking $INWARD_KEY -> $OUTWARD_KEY ($LINK_TYPE)..." >&2

acli jira workitem link create \
    --out "$INWARD_KEY" \
    --in "$OUTWARD_KEY" \
    --type "$LINK_TYPE" \
    --yes

echo "Linked $INWARD_KEY and $OUTWARD_KEY" >&2
echo "{\"linked\": [\"$INWARD_KEY\", \"$OUTWARD_KEY\"], \"type\": \"$LINK_TYPE\"}"
