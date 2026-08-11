#!/usr/bin/env bash
#
# Add a comment to a Jira issue.
#
# Usage:
#   ./comment_issue.sh <issue_key> "comment text"
#   ./comment_issue.sh <issue_key> --file comment.txt
#
# Examples:
#   ./comment_issue.sh PROJ-123 "Deployed to staging. Waiting for QA sign-off."
#   ./comment_issue.sh PROJ-123 --file release-notes.txt
#
# Output: JSON response from acli
# Exit codes: 0=success, 1=invalid params, 4=auth error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

if [[ $# -lt 2 ]]; then
    echo "Usage: $(basename "$0") <issue_key> COMMENT_TEXT" >&2
    echo "       $(basename "$0") <issue_key> --file FILE" >&2
    exit 1
fi

KEY="$1"; shift

if [[ ! "$KEY" =~ ^[A-Z][A-Z0-9_]+-[0-9]+$ ]]; then
    echo "ERROR: Invalid issue key format: '$KEY' (expected e.g. PROJ-123)" >&2
    exit 1
fi

BODY_TEXT=""
if [[ "${1:-}" == "--file" ]]; then
    [[ -z "${2:-}" ]] && { echo "ERROR: --file requires a path argument" >&2; exit 1; }
    BODY_TEXT=$(cat "$2")
else
    BODY_TEXT="$*"
fi

[[ -z "$BODY_TEXT" ]] && { echo "ERROR: comment body is required" >&2; exit 1; }

ensure_auth

echo "Adding comment to $KEY..." >&2
acli jira workitem comment create --key "$KEY" --body "$BODY_TEXT" --json
