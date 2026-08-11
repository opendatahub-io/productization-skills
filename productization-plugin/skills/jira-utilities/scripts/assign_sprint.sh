#!/usr/bin/env bash
#
# Add one or more Jira issues to a sprint.
#
# acli jira sprint has no "add issues" subcommand (create/delete/update/view/
# list-workitems only), so this script uses the Jira Agile REST API directly.
#
# Usage:
#   ./assign_sprint.sh <sprint_id> ISSUE-KEY [ISSUE-KEY ...]
#
# Example:
#   ./assign_sprint.sh 65352 PROJ-1 PROJ-2 PROJ-3
#
# Output: JSON confirmation or empty on success (204 No Content)
# Exit codes: 0=success, 1=invalid params, 4=auth error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

if [[ $# -lt 2 ]]; then
    echo "Usage: $(basename "$0") <sprint_id> ISSUE-KEY [ISSUE-KEY ...]" >&2
    echo "Example: $(basename "$0") 65352 PROJ-123 PROJ-124" >&2
    exit 1
fi

SPRINT_ID="$1"; shift
ISSUES=("$@")

if [[ ! "$SPRINT_ID" =~ ^[0-9]+$ ]]; then
    echo "ERROR: sprint_id must be a positive integer, got: '$SPRINT_ID'" >&2
    exit 1
fi

require_env

BODY=$(jq -n --argjson issues "$(printf '%s\n' "${ISSUES[@]}" | jq -R . | jq -s .)" \
    '{issues: $issues}')

echo "Adding ${#ISSUES[@]} issue(s) to sprint $SPRINT_ID..." >&2

RESPONSE=$(jira_rest POST "/rest/agile/1.0/sprint/${SPRINT_ID}/issue" "$BODY")

# 204 No Content → empty response; report success explicitly
if [[ -z "$RESPONSE" ]]; then
    KEYS_JSON=$(printf '%s\n' "${ISSUES[@]}" | jq -R . | jq -s .)
    echo "{\"sprint_id\": $SPRINT_ID, \"added\": $KEYS_JSON}"
else
    echo "$RESPONSE" | jq '.'
fi
