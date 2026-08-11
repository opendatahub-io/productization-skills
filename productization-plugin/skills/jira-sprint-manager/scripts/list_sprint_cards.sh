#!/usr/bin/env bash
#
# List work items in a sprint on a Jira Software board.
#
# Usage:
#   ./list_sprint_cards.sh [--board-id ID] [--sprint-id ID] [options]
#
# Options:
#   --board-id ID           Jira Software board ID (optional — falls back to
#                           JIRA_BOARD_ID env var, then auto-discovery via
#                           JIRA_PROJECT env var, then boardless JQL)
#   --sprint-id ID          Sprint ID to use directly (skips board/sprint resolution)
#   --state active|future   Sprint state for resolution (default: active)
#   --assignee EMAIL        Filter by assignee email
#   --status STATUS         Filter by status name (e.g. "In Progress")
#
# Environment variables (used when --board-id is omitted):
#   JIRA_BOARD_ID   Board ID to use without passing --board-id
#   JIRA_PROJECT    Project key used to auto-discover the first scrum board
#
# Output: table of KEY | TYPE | SUMMARY | STATUS | ASSIGNEE
# Exit codes: 0=success, 1=invalid params, 4=auth error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JIRA_UTILS="$(cd "$SCRIPT_DIR/../../jira-utilities/scripts" && pwd)"
source "$JIRA_UTILS/_common.sh"

BOARD_ID="${JIRA_BOARD_ID:-}"
SPRINT_ID_DIRECT=""
STATE="active"
ASSIGNEE_FILTER=""
STATUS_FILTER=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --board-id)  BOARD_ID="$2";         shift 2 ;;
        --sprint-id) SPRINT_ID_DIRECT="$2"; shift 2 ;;
        --state)     STATE="$2";            shift 2 ;;
        --assignee)  ASSIGNEE_FILTER="$2";  shift 2 ;;
        --status)    STATUS_FILTER="$2";    shift 2 ;;
        *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    esac
done

ensure_auth

if [[ -n "$SPRINT_ID_DIRECT" ]]; then
    # Sprint ID supplied directly — skip all board/sprint resolution
    echo "Using sprint ID: $SPRINT_ID_DIRECT" >&2
    JQL="sprint = $SPRINT_ID_DIRECT"
else
    # Auto-discover board from JIRA_PROJECT if still no board ID
    if [[ -z "$BOARD_ID" && -n "${JIRA_PROJECT:-}" ]]; then
        echo "No board ID provided — discovering board for project '$JIRA_PROJECT'..." >&2
        BOARD_ID=$("$SCRIPT_DIR/../../jira-utilities/scripts/get_board.sh" "$JIRA_PROJECT" --type scrum --first 2>/dev/null \
            | jq -r '.id // empty') || true
        [[ -n "$BOARD_ID" ]] && echo "Auto-discovered board ID: $BOARD_ID" >&2
    fi

    if [[ -n "$BOARD_ID" ]]; then
        SPRINTS_ERR=$(mktemp)
        SPRINTS_JSON=$(acli jira board list-sprints --id "$BOARD_ID" --state "$STATE" --json 2>"$SPRINTS_ERR") || {
            echo "WARNING: acli failed to list sprints on board $BOARD_ID: $(cat "$SPRINTS_ERR")" >&2
            echo "Falling back to openSprints() JQL" >&2
            rm -f "$SPRINTS_ERR"
            SPRINTS_JSON=""
        }
        rm -f "$SPRINTS_ERR"

        if [[ -n "$SPRINTS_JSON" ]]; then
            SPRINT_ID=$(echo "$SPRINTS_JSON" | jq -r 'if type == "array" then .[0].id else (.values // [])[0].id end')
            SPRINT_NAME=$(echo "$SPRINTS_JSON" | jq -r 'if type == "array" then .[0].name else (.values // [])[0].name end')
        fi

        if [[ -z "${SPRINT_ID:-}" || "${SPRINT_ID:-}" == "null" ]]; then
            echo "WARNING: No $STATE sprint found on board $BOARD_ID — falling back to openSprints() JQL" >&2
            JQL="sprint in openSprints()"
        else
            echo "Sprint: $SPRINT_NAME (ID: $SPRINT_ID)" >&2
            JQL="sprint = $SPRINT_ID"
        fi
    else
        # No board available — use openSprints() JQL (works across all projects/boards)
        echo "No board ID — querying open sprints across all projects" >&2
        JQL="sprint in openSprints()"
    fi
fi

[[ -n "$ASSIGNEE_FILTER" ]] && JQL="$JQL AND assignee = \"$(jql_escape "$ASSIGNEE_FILTER")\""
[[ -n "$STATUS_FILTER" ]]   && JQL="$JQL AND status = \"$(jql_escape "$STATUS_FILTER")\""
JQL="$JQL ORDER BY issuetype ASC, status ASC, summary ASC"

"$JIRA_UTILS/search_issues.sh" "$JQL" --format table
