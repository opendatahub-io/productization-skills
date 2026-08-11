#!/usr/bin/env bash
#
# Resolve a sprint ID from a Jira Software board.
#
# Usage:
#   ./get_sprint_id.sh --board-id ID <sprint-number>
#   ./get_sprint_id.sh --board-id ID --active
#   ./get_sprint_id.sh --board-id ID --next
#
# Options:
#   --board-id ID   Jira Software board ID (required)
#
# Output: sprint ID integer on stdout — suitable for $() capture.
# Exit codes: 0=success, 1=not found or invalid params

set -euo pipefail

JIRA_UTILS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../jira-utilities/scripts" && pwd)"
source "$JIRA_UTILS/_common.sh"

BOARD_ID="${JIRA_BOARD_ID:-}"
POSITIONAL=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --board-id) [[ $# -lt 2 || -z "$2" ]] && { echo "ERROR: --board-id requires a value" >&2; exit 1; }
                    BOARD_ID="$2"; shift 2 ;;
        *)          POSITIONAL+=("$1"); shift ;;
    esac
done

if [[ -z "$BOARD_ID" ]]; then
    echo "Usage: $(basename "$0") --board-id ID <sprint-number> | --active | --next" >&2
    echo "       Or set JIRA_BOARD_ID env var to avoid passing --board-id each time." >&2
    exit 1
fi

set -- "${POSITIONAL[@]+"${POSITIONAL[@]}"}"

case "${1:-}" in
    --active) MODE="active" ;;
    --next)   MODE="next" ;;
    "")
        echo "Usage: $(basename "$0") --board-id ID <sprint-number> | --active | --next" >&2
        exit 1
        ;;
    *)
        MODE="number"
        SPRINT_NUM="$1"
        ;;
esac

ensure_auth

if [[ "$MODE" == "active" || "$MODE" == "next" ]]; then
    [[ "$MODE" == "active" ]] && STATE_ARG="active" || STATE_ARG="future"
    SPRINTS_ERR=$(mktemp)
    SPRINTS_JSON=$(acli jira board list-sprints --id "$BOARD_ID" --state "$STATE_ARG" --json 2>"$SPRINTS_ERR") || {
        echo "ERROR: acli failed: $(cat "$SPRINTS_ERR")" >&2
        rm -f "$SPRINTS_ERR"
        exit 1
    }
    rm -f "$SPRINTS_ERR"
    RESULT=$(echo "$SPRINTS_JSON" | jq -r 'if type == "array" then .[0].id else (.values // [])[0].id end')
    if [[ -z "$RESULT" || "$RESULT" == "null" ]]; then
        echo "ERROR: No $STATE_ARG sprint found on board $BOARD_ID" >&2
        exit 1
    fi
    echo "$RESULT"
    exit 0
fi

# Numeric mode: search active → future → closed
for state in active future closed; do
    RESULT=$(acli jira board list-sprints --id "$BOARD_ID" --state "$state" --json 2>/dev/null \
        | jq -r --arg num "$SPRINT_NUM" \
          '(if type == "array" then . else (.values // []) end)
           | .[] | select(.name | test("Sprint " + $num + "([^0-9]|$)"))
           | .id' \
        | head -1 || true)
    if [[ -n "$RESULT" ]]; then
        echo "$RESULT"
        exit 0
    fi
done

echo "ERROR: Sprint '$SPRINT_NUM' not found on board $BOARD_ID" >&2
exit 1
