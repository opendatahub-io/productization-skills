#!/bin/bash
# Generic state management library for Productization skills
# This allows scripts to save outputs and reference them later without re-sending data to the model
#
# Location: productization-plugin/tools/memory/scripts/state.sh
#
# Usage:
#   Before sourcing this library, set SKILL_STATE_DIR to your skill's state directory:
#
#   SKILL_STATE_DIR="${MY_SKILL_STATE_DIR:-$HOME/.my-skill/state}"
#   source "$(dirname "${BASH_SOURCE[0]}")/../../../tools/memory/scripts/state.sh"
#
# This keeps each skill's state isolated while sharing the same management code.

set -euo pipefail

# Validate that SKILL_STATE_DIR is set
if [[ -z "${SKILL_STATE_DIR:-}" ]]; then
    echo "Error: SKILL_STATE_DIR must be set before sourcing state.sh" >&2
    echo "Example: SKILL_STATE_DIR=\"\$HOME/.my-skill/state\"" >&2
    exit 1
fi

# State directory - stores all script outputs
STATE_DIR="$SKILL_STATE_DIR"
STATE_METADATA="$STATE_DIR/metadata.json"

# Initialize state directory
init_state() {
    mkdir -p "$STATE_DIR"

    if [ ! -f "$STATE_METADATA" ]; then
        echo '{"sessions": {}}' > "$STATE_METADATA"
    fi
}

# Get current session ID (or create new one)
get_session_id() {
    local session_file="$STATE_DIR/.current_session"

    if [ -f "$session_file" ]; then
        cat "$session_file"
    else
        local session_id="session_$(date +%Y%m%d_%H%M%S)"
        echo "$session_id" > "$session_file"
        echo "$session_id"
    fi
}

# Start a new session
new_session() {
    local session_id="session_$(date +%Y%m%d_%H%M%S)"
    echo "$session_id" > "$STATE_DIR/.current_session"

    # Create session directory
    mkdir -p "$STATE_DIR/$session_id"

    echo "$session_id"
}

# Save state for a script execution
# Usage: save_state <operation> <data> [summary]
save_state() {
    init_state

    local operation="$1"
    local data="$2"
    local summary="${3:-}"

    local session_id=$(get_session_id)
    local timestamp=$(date +%s)
    local state_id="${operation}_${timestamp}"
    local state_file="$STATE_DIR/$session_id/${state_id}.json"

    # Create session dir if needed
    mkdir -p "$STATE_DIR/$session_id"

    # Save full data
    cat > "$state_file" <<EOF
{
  "state_id": "$state_id",
  "session_id": "$session_id",
  "operation": "$operation",
  "timestamp": $timestamp,
  "summary": $(echo "$summary" | jq -Rs .),
  "data": $data
}
EOF

    # Update metadata
    local temp_metadata=$(mktemp)
    jq --arg sid "$session_id" --arg op "$operation" --arg stid "$state_id" \
       '.sessions[$sid] += {($op): $stid}' "$STATE_METADATA" > "$temp_metadata"
    mv "$temp_metadata" "$STATE_METADATA"

    # Return state ID for reference
    echo "$state_id"
}

# Get state data by state_id
# Usage: get_state <state_id>
get_state() {
    local state_id="$1"
    local session_id=$(get_session_id)
    local state_file="$STATE_DIR/$session_id/${state_id}.json"

    if [ -f "$state_file" ]; then
        cat "$state_file"  # Return full state object
    else
        echo "Error: State not found: $state_id" >&2
        echo "Available states in session '$session_id':" >&2
        ls -1 "$STATE_DIR/$session_id"/*.json 2>/dev/null | xargs -I{} basename {} .json >&2 || echo "  (none)" >&2
        return 1
    fi
}

# Get state data by operation name (gets latest)
# Usage: get_state_by_operation <operation>
get_state_by_operation() {
    local operation="$1"
    local session_id=$(get_session_id)
    local session_dir="$STATE_DIR/$session_id"

    # Debug: show where we're looking
    echo "[DEBUG] Looking for: $session_dir/${operation}_*.json" >&2

    if [ ! -d "$session_dir" ]; then
        echo "Error: Session directory not found: $session_dir" >&2
        echo "Available sessions:" >&2
        ls -1 "$STATE_DIR" 2>/dev/null | grep "^session_" >&2 || echo "  (none)" >&2
        return 1
    fi

    # Find latest state file for this operation
    local state_file=$(ls -t "$session_dir/${operation}_"*.json 2>/dev/null | head -n1)

    if [ -n "$state_file" ] && [ -f "$state_file" ]; then
        cat "$state_file"  # Return full state object, not just .data
    else
        echo "Error: No state found for operation '$operation' in session '$session_id'" >&2
        echo "Available states in this session:" >&2
        ls -1 "$session_dir"/*.json 2>/dev/null | xargs -I{} basename {} .json >&2 || echo "  (none)" >&2
        return 1
    fi
}

# Get summary from state
# Usage: get_state_summary <state_id>
get_state_summary() {
    local state_id="$1"
    local session_id=$(get_session_id)
    local state_file="$STATE_DIR/$session_id/${state_id}.json"

    if [ -f "$state_file" ]; then
        jq -r '.summary' "$state_file"
    else
        echo "Error: State not found: $state_id" >&2
        return 1
    fi
}

# List all states in current session
list_states() {
    local session_id=$(get_session_id)
    local session_dir="$STATE_DIR/$session_id"

    if [ ! -d "$session_dir" ]; then
        echo "No states in current session"
        return 0
    fi

    echo "States in session: $session_id"
    echo ""

    for state_file in "$session_dir"/*.json; do
        if [ -f "$state_file" ]; then
            local state_id=$(jq -r '.state_id' "$state_file")
            local operation=$(jq -r '.operation' "$state_file")
            local timestamp=$(jq -r '.timestamp' "$state_file")
            local summary=$(jq -r '.summary' "$state_file")
            local date_str=$(date -d "@$timestamp" '+%Y-%m-%d %H:%M:%S')

            echo "[$state_id]"
            echo "  Operation: $operation"
            echo "  Time: $date_str"
            echo "  Summary: $summary"
            echo ""
        fi
    done
}

# Clean old sessions (keep last N sessions)
clean_old_sessions() {
    local keep_sessions="${1:-5}"

    # List sessions sorted by name (which includes timestamp)
    local sessions=$(ls -1d "$STATE_DIR"/session_* 2>/dev/null | sort -r || true)
    local session_count=$(echo "$sessions" | wc -l)

    if [ "$session_count" -gt "$keep_sessions" ]; then
        echo "$sessions" | tail -n +$((keep_sessions + 1)) | xargs rm -rf
        echo "Cleaned $((session_count - keep_sessions)) old sessions"
    fi
}

# Export functions for use in other scripts
export -f init_state
export -f get_session_id
export -f new_session
export -f save_state
export -f get_state
export -f get_state_by_operation
export -f get_state_summary
export -f list_states
export -f clean_old_sessions
