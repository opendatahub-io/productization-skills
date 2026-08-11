#!/usr/bin/env bash
#
# Discover Jira Software boards for a project key.
#
# Usage:
#   ./get_board.sh <project> [options]
#
# Arguments:
#   project     Jira project key (e.g., MYPROJ)
#
# Options:
#   --name SUBSTR    Filter boards whose name contains this string (case-insensitive)
#   --type TYPE      Filter by board type: scrum or kanban
#   --first          Return only the first match as a single JSON object
#
# Examples:
#   ./get_board.sh MYPROJ
#   ./get_board.sh MYPROJ --name "My Team"
#   ./get_board.sh MYPROJ --name "My Team" --type scrum --first
#
# Output: JSON array of board objects [{id, name, type}] or single object with --first
# Exit codes: 0=success, 1=invalid params, 3=no boards found, 4=auth error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

NAME_FILTER=""
BOARD_TYPE=""
FIRST=false

if [[ $# -lt 1 ]]; then
    echo "Usage: $(basename "$0") <project> [--name SUBSTR] [--type scrum|kanban] [--first]" >&2
    exit 1
fi

PROJECT="$1"; shift

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)  NAME_FILTER="$2"; shift 2 ;;
        --type)  BOARD_TYPE="$2";  shift 2 ;;
        --first) FIRST=true;       shift ;;
        *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ -n "$BOARD_TYPE" && "$BOARD_TYPE" != "scrum" && "$BOARD_TYPE" != "kanban" ]]; then
    echo "ERROR: --type must be 'scrum' or 'kanban'" >&2
    exit 1
fi

ensure_auth

echo "Discovering boards for project '$PROJECT'..." >&2

CMD=(acli jira board search --project "$PROJECT" --json --paginate)
[[ -n "$NAME_FILTER" ]] && CMD+=(--name "$NAME_FILTER")
[[ -n "$BOARD_TYPE" ]]  && CMD+=(--type "$BOARD_TYPE")

RESULT=$("${CMD[@]}")

# Normalise to array — acli may return a wrapped object or a bare array
BOARDS=$(echo "$RESULT" | jq 'if type == "array" then . else .values // [.] end')

COUNT=$(echo "$BOARDS" | jq 'length')
echo "Found $COUNT board(s)" >&2

if [[ "$COUNT" -eq 0 ]]; then
    echo "ERROR: No boards found for project '$PROJECT'" >&2
    exit 3
fi

if [[ "$FIRST" == "true" ]]; then
    echo "$BOARDS" | jq '.[0] | {id, name, type}'
else
    echo "$BOARDS" | jq '[.[] | {id, name, type}]'
fi
