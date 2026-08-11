#!/bin/bash
# Generic view stored state from previous script executions
#
# Location: productization-plugin/tools/memory/scripts/view_state.sh
#
# Usage:
#   Before running this script, set SKILL_STATE_DIR:
#
#   SKILL_STATE_DIR="$HOME/.my-skill/state" ./view_state.sh [state_id|operation_name]
#
# Or from within a skill, create a wrapper script that sets the variable.

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# If SKILL_STATE_DIR is not set, show error
if [[ -z "${SKILL_STATE_DIR:-}" ]]; then
    echo "Error: SKILL_STATE_DIR must be set before running view_state.sh" >&2
    echo "" >&2
    echo "This is a generic state viewer. Skills should create a wrapper script like:" >&2
    echo "" >&2
    echo '#!/bin/bash' >&2
    echo 'SKILL_STATE_DIR="${MY_SKILL_STATE_DIR:-$HOME/.my-skill/state}"' >&2
    echo 'source "$(dirname "$0")/../../../tools/memory/scripts/state.sh"' >&2
    echo '"$(dirname "$0")/../../../tools/memory/scripts/view_state.sh" "$@"' >&2
    exit 1
fi

# Source the state library
source "$SCRIPT_DIR/state.sh"

if [ $# -eq 0 ]; then
    # List all states
    list_states
    exit 0
fi

STATE_REF="$1"

# Check if it's a state_id or operation name
if [[ "$STATE_REF" == *"_"* ]]; then
    # Looks like a state_id
    SESSION_ID=$(get_session_id)
    STATE_FILE="$STATE_DIR/$SESSION_ID/${STATE_REF}.json"

    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE" | jq .
    else
        echo "Error: State not found: $STATE_REF" >&2
        exit 1
    fi
else
    # Treat as operation name
    get_state_by_operation "$STATE_REF"
fi
