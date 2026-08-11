#!/bin/bash
# Trace a request ID across multiple log groups
# Usage: ./trace_request.sh <request-id> <log-group-prefix> [hours-back] [--human]
# Examples:
#   ./trace_request.sh abc-123 /aws/myapp
#   ./trace_request.sh abc-123 /aws/myapp 24 --human

set -euo pipefail

# Parse flags
HUMAN_OUTPUT=false
ARGS=()

for arg in "$@"; do
    case $arg in
        --human)
            HUMAN_OUTPUT=true
            ;;
        *)
            ARGS+=("$arg")
            ;;
    esac
done

set -- "${ARGS[@]}"

if [ $# -lt 2 ]; then
    echo '{"error": "Missing required arguments", "usage": "trace_request.sh <request-id> <log-group-prefix> [hours-back] [--human]"}' >&2
    exit 1
fi

REQUEST_ID="$1"
LOG_GROUP_PREFIX="$2"
HOURS="${3:-24}"

START_TIME=$(date -d "$HOURS hours ago" +%s)000
END_TIME=$(date +%s)000

# Progress to stderr if JSON output
if [ "$HUMAN_OUTPUT" = false ]; then
    exec 3>&1  # Save stdout
    exec 1>&2  # Redirect stdout to stderr for progress messages
fi

echo "=== Tracing Request ID: $REQUEST_ID ==="
echo "Log Group Prefix: $LOG_GROUP_PREFIX"
echo "Time Range: $(date -d @$((START_TIME/1000))) to $(date -d @$((END_TIME/1000)))"
echo ""

# Find all log groups matching the prefix
LOG_GROUPS=$(aws logs describe-log-groups \
  --log-group-name-prefix "$LOG_GROUP_PREFIX" \
  --query 'logGroups[*].logGroupName' \
  --output text)

if [ -z "$LOG_GROUPS" ]; then
    if [ "$HUMAN_OUTPUT" = false ]; then
        exec 1>&3
        echo '{"error": "No log groups found", "prefix": "'"$LOG_GROUP_PREFIX"'"}'
    else
        echo "No log groups found with prefix: $LOG_GROUP_PREFIX"
    fi
    exit 1
fi

LOG_GROUP_COUNT=$(echo "$LOG_GROUPS" | wc -w)
echo "Searching in $LOG_GROUP_COUNT log group(s):"
echo "$LOG_GROUPS" | tr '\t' '\n'
echo ""

# Collect all results
ALL_RESULTS='[]'
TOTAL_MATCHES=0

# Search each log group for the request ID
for LOG_GROUP in $LOG_GROUPS; do
    echo "=== Searching $LOG_GROUP ==="

    RESULTS=$(aws logs filter-log-events \
        --log-group-name "$LOG_GROUP" \
        --filter-pattern "$REQUEST_ID" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" 2>/dev/null || echo '{"events":[]}')

    MATCH_COUNT=$(echo "$RESULTS" | jq -r '.events | length')
    TOTAL_MATCHES=$((TOTAL_MATCHES + MATCH_COUNT))

    if [ "$MATCH_COUNT" -gt 0 ]; then
        echo "Found $MATCH_COUNT matches"

        # Append results to ALL_RESULTS
        ALL_RESULTS=$(jq -n \
            --argjson existing "$ALL_RESULTS" \
            --argjson new "$RESULTS" \
            --arg log_group "$LOG_GROUP" \
            '$existing + [$new.events[] | . + {logGroup: $log_group}]')
    else
        echo "No matches found"
    fi
    echo ""
done

echo "=== Trace Complete ==="
echo "Total matches: $TOTAL_MATCHES across $LOG_GROUP_COUNT log groups"

# Output results
if [ "$HUMAN_OUTPUT" = false ]; then
    exec 1>&3  # Restore stdout

    # Output as JSON
    jq -n \
        --arg request_id "$REQUEST_ID" \
        --arg prefix "$LOG_GROUP_PREFIX" \
        --argjson hours "$HOURS" \
        --argjson log_groups_searched "$LOG_GROUP_COUNT" \
        --argjson total_matches "$TOTAL_MATCHES" \
        --argjson events "$ALL_RESULTS" \
        '{
            operation: "trace_request",
            request_id: $request_id,
            log_group_prefix: $prefix,
            hours_back: $hours,
            log_groups_searched: $log_groups_searched,
            total_matches: $total_matches,
            events: [
                $events[] | {
                    timestamp: (.timestamp | tonumber / 1000 | strftime("%Y-%m-%d %H:%M:%S")),
                    log_group: .logGroup,
                    log_stream: .logStreamName,
                    message: .message
                }
            ] | sort_by(.timestamp)
        }'
else
    exec 1>&3  # Restore stdout

    # Human-readable output
    echo "=== Trace Results for Request ID: $REQUEST_ID ==="
    echo ""

    if [ "$TOTAL_MATCHES" -gt 0 ]; then
        echo "$ALL_RESULTS" | jq -r 'sort_by(.timestamp) | .[] |
            "\(.timestamp | tonumber / 1000 | strftime("%Y-%m-%d %H:%M:%S")) [\(.logGroup)] [\(.logStreamName)] \(.message)"'
    else
        echo "No matches found for request ID: $REQUEST_ID"
    fi
fi
