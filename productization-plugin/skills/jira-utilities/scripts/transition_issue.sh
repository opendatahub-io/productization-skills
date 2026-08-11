#!/usr/bin/env bash
#
# List available transitions or apply a transition to a Jira issue.
#
# Transitions are applied via acli (acli jira workitem transition --status NAME).
# Listing available transitions has no acli equivalent and uses the REST API.
#
# Usage:
#   ./transition_issue.sh <issue_key> --list
#   ./transition_issue.sh <issue_key> --to <status_name>   # case-sensitive
#
# Examples:
#   ./transition_issue.sh PROJ-123 --list
#   ./transition_issue.sh PROJ-123 --to Closed
#   ./transition_issue.sh PROJ-123 --to "In Progress"
#
# Exit codes: 0=success, 1=invalid params, 4=auth error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

if [[ $# -lt 2 ]]; then
    echo "Usage: $(basename "$0") <issue_key> --list | --to STATUS_NAME" >&2
    exit 1
fi

KEY="$1"; shift

if [[ ! "$KEY" =~ ^[A-Z][A-Z0-9_]+-[0-9]+$ ]]; then
    echo "ERROR: Invalid issue key format: '$KEY' (expected e.g. PROJ-123)" >&2
    exit 1
fi

MODE=""
STATUS_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --list) MODE="list"; shift ;;
        --to)   [[ $# -lt 2 || -z "$2" ]] && { echo "ERROR: --to requires a status name" >&2; exit 1; }
                MODE="apply"; STATUS_NAME="$2"; shift 2 ;;
        *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$MODE" ]]; then
    echo "ERROR: must specify --list or --to STATUS_NAME" >&2
    exit 1
fi

# --list has no acli equivalent; use the REST API directly.
if [[ "$MODE" == "list" ]]; then
    require_env
    echo "Available transitions for $KEY:" >&2
    jira_rest GET "/rest/api/3/issue/${KEY}/transitions" \
        | jq '[.transitions[] | {id, name, to: .to.name}]'
    exit 0
fi

# --to: apply transition via acli
ensure_auth
echo "Transitioning $KEY to '$STATUS_NAME'..." >&2
acli jira workitem transition --key "$KEY" --status "$STATUS_NAME" --yes --json
