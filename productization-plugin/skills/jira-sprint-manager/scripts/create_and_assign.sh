#!/usr/bin/env bash
#
# Create a Jira issue and assign it to a sprint in a single step.
#
# Usage:
#   ./create_and_assign.sh --project KEY <sprint_id> <summary> [create_issue.sh options...]
#
# Options:
#   --project KEY   Jira project key (required)
#
# Examples:
#   ./create_and_assign.sh --project MYPROJ 44147 "Test transient gateway"
#   ./create_and_assign.sh --project MYPROJ 44147 "Fix auth timeout" --assignee user@example.com
#   ./create_and_assign.sh --project MYPROJ 44147 "Update docs" --priority High --labels "docs,backend"
#
# Any extra options after <summary> are forwarded to create_issue.sh
# (e.g. --issuetype, --component, --team, --epic, --activity-type, etc.)
#
# Output: created issue key on stdout
# Exit codes: 0=success, 1=invalid params/creation failed, 4=auth error

set -euo pipefail

JIRA_UTILS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../jira-utilities/scripts" && pwd)"
source "$JIRA_UTILS/_common.sh"

PROJECT=""
POSITIONAL=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project) PROJECT="$2"; shift 2 ;;
        *)         POSITIONAL+=("$1"); shift ;;
    esac
done

if [[ -z "$PROJECT" || ${#POSITIONAL[@]} -lt 2 ]]; then
    echo "Usage: $(basename "$0") --project KEY <sprint_id> <summary> [create_issue.sh options...]" >&2
    exit 1
fi

SPRINT_ID="${POSITIONAL[0]}"
SUMMARY="${POSITIONAL[1]}"
EXTRA_ARGS=("${POSITIONAL[@]:2}")

if [[ ! "$SPRINT_ID" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: sprint_id must be a positive integer, got: '$SPRINT_ID'" >&2
    exit 1
fi

ensure_auth

KEY=$("$JIRA_UTILS/create_issue.sh" "$PROJECT" "$SUMMARY" \
    "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}" 2>/dev/null | jq -r '.key')

if [[ -z "$KEY" || "$KEY" == "null" ]]; then
    echo "ERROR: Issue creation failed or returned no key" >&2
    exit 1
fi

echo "Created: $KEY" >&2
"$JIRA_UTILS/assign_sprint.sh" "$SPRINT_ID" "$KEY" >/dev/null
echo "Assigned $KEY to sprint $SPRINT_ID" >&2
echo "$KEY"
