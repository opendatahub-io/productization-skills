#!/bin/bash
# View stored state from previous gitlab-job-analyzer script executions
# Usage: ./view_state.sh [state_id|operation_name]

set -euo pipefail

# Set state directory for this skill
SKILL_STATE_DIR="${GITLAB_JOB_ANALYZER_STATE_DIR:-$HOME/.gitlab-job-analyzer/state}"

# Source shared state library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../tools/memory/scripts/state.sh"

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
