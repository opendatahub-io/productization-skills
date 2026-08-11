#!/usr/bin/env bash
#
# Fetch sprint information from a Jira Software board.
#
# Accepts either an explicit board ID or a project key with automatic board discovery.
# When --project is used, get_board.sh is called to resolve the board ID.
#
# Usage:
#   ./get_sprint.sh <board_id> [--state STATE]
#   ./get_sprint.sh --project KEY [--board-name NAME] [--board-type TYPE] [--state STATE]
#
# Arguments:
#   board_id        Jira Software board ID (optional if --project is given)
#
# Options:
#   --state STATE       Sprint state: active, future, or closed (default: active)
#   --project KEY       Project key — triggers board discovery (e.g., MYPROJ)
#   --board-name NAME   Name substring filter for board discovery
#   --board-type TYPE   Board type filter for discovery: scrum or kanban (default: scrum)
#
# Examples:
#   ./get_sprint.sh 42
#   ./get_sprint.sh 42 --state future
#   ./get_sprint.sh --project MYPROJ
#   ./get_sprint.sh --project MYPROJ --board-name "My Team" --state active
#
# Output: JSON array of sprint objects
# Exit codes: 0=success, 1=invalid params/ambiguous board, 3=not found, 4=auth error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

BOARD_ID=""
STATE="active"
PROJECT=""
BOARD_NAME=""
BOARD_TYPE="scrum"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --state)      STATE="$2";      shift 2 ;;
        --project)    PROJECT="$2";    shift 2 ;;
        --board-name) BOARD_NAME="$2"; shift 2 ;;
        --board-type) BOARD_TYPE="$2"; shift 2 ;;
        --*)          echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
        *)            BOARD_ID="$1";   shift ;;
    esac
done

if [[ -z "$BOARD_ID" && -z "$PROJECT" ]]; then
    echo "Usage: $(basename "$0") <board_id> [--state STATE]" >&2
    echo "       $(basename "$0") --project KEY [--board-name NAME] [--board-type TYPE] [--state STATE]" >&2
    exit 1
fi

if [[ "$STATE" != "active" && "$STATE" != "future" && "$STATE" != "closed" ]]; then
    echo "ERROR: --state must be 'active', 'future', or 'closed'" >&2
    exit 1
fi

ensure_auth

# Board discovery when --project is provided
if [[ -n "$PROJECT" ]]; then
    echo "Discovering boards for project '$PROJECT'..." >&2

    BOARD_CMD=("$SCRIPT_DIR/get_board.sh" "$PROJECT")
    [[ -n "$BOARD_NAME" ]] && BOARD_CMD+=(--name "$BOARD_NAME")
    [[ -n "$BOARD_TYPE" ]] && BOARD_CMD+=(--type "$BOARD_TYPE")

    BOARDS=$("${BOARD_CMD[@]}")
    COUNT=$(echo "$BOARDS" | jq 'length')

    if [[ "$COUNT" -eq 0 ]]; then
        NAME_HINT=""
        [[ -n "$BOARD_NAME" ]] && NAME_HINT=" with name containing '$BOARD_NAME'"
        echo "ERROR: No boards found for project '$PROJECT'${NAME_HINT}" >&2
        exit 3
    fi

    if [[ "$COUNT" -gt 1 ]]; then
        echo "ERROR: Ambiguous — $COUNT boards found for project '$PROJECT'." >&2
        echo "Re-run with --board-name to disambiguate:" >&2
        echo "$BOARDS" | jq '.' >&2
        exit 1
    fi

    BOARD_ID=$(echo "$BOARDS" | jq -r '.[0].id')
    BOARD_NAME_RESOLVED=$(echo "$BOARDS" | jq -r '.[0].name')
    echo "Resolved board: $BOARD_NAME_RESOLVED (ID: $BOARD_ID)" >&2
fi

echo "Fetching '$STATE' sprints for board $BOARD_ID..." >&2

acli jira board list-sprints --id "$BOARD_ID" --state "$STATE" --json
