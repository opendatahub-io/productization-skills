#!/bin/bash
# CloudWatch Logs Insights query helper functions
# Provides polling-based query execution with progress feedback
#
# Usage:
#   source "$SCRIPT_DIR/lib/query_helpers.sh"
#   RESULT=$(wait_for_query "$QUERY_ID" "  Progress label")

# wait_for_query - Poll CloudWatch Logs Insights query until completion
#
# Arguments:
#   $1 - Query ID returned by aws logs start-query
#   $2 - Progress label for status messages (sent to stderr)
#
# Returns:
#   Full JSON result from aws logs get-query-results on stdout
#
# Exit codes:
#   0 - Query completed successfully
#   1 - Query failed, was cancelled, or timed out after max attempts
wait_for_query() {
    local query_id="$1"
    local label="${2:-  Waiting}"
    local max_attempts=30
    local sleep_interval=2

    for ((attempt=1; attempt<=max_attempts; attempt++)); do
        local result
        result=$(aws logs get-query-results --query-id "$query_id" 2>/dev/null) || {
            echo "${label}: failed to get query results" >&2
            return 1
        }

        local status
        status=$(echo "$result" | jq -r '.status // "Unknown"')

        case "$status" in
            Complete)
                echo "$result"
                return 0
                ;;
            Failed|Cancelled)
                echo "${label}: query ${status}" >&2
                return 1
                ;;
            Running|Scheduled)
                echo -n "." >&2
                sleep "$sleep_interval"
                ;;
            *)
                echo "${label}: unknown status '${status}'" >&2
                sleep "$sleep_interval"
                ;;
        esac
    done

    echo "${label}: timed out after $((max_attempts * sleep_interval)) seconds" >&2
    return 1
}
