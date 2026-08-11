#!/bin/bash
# Find recent errors in a log group
# Usage: ./find_recent_errors.sh <log-group-name> <hours-back> [limit] [--human]
# Examples:
#   ./find_recent_errors.sh /aws/application/myapp 1
#   ./find_recent_errors.sh /aws/application/myapp 1 50 --human

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
    echo '{"error": "Missing required arguments", "usage": "find_recent_errors.sh <log-group-name> <hours-back> [limit] [--human]"}' >&2
    exit 1
fi

LOG_GROUP="$1"
HOURS="$2"
LIMIT="${3:-100}"

START_TIME=$(date -d "$HOURS hours ago" +%s)
END_TIME=$(date +%s)

# Progress to stderr if JSON output
if [ "$HUMAN_OUTPUT" = false ]; then
    exec 3>&1  # Save stdout
    exec 1>&2  # Redirect stdout to stderr for progress messages
fi

echo "=== Finding Recent Errors ==="
echo "Log Group: $LOG_GROUP"
echo "Time Range: $(date -d @$START_TIME) to $(date -d @$END_TIME)"
echo "Limit: $LIMIT"
echo ""

QUERY_ID=$(aws logs start-query \
  --log-group-name "$LOG_GROUP" \
  --start-time $START_TIME \
  --end-time $END_TIME \
  --query-string "fields @timestamp, @message | filter @message like /(?i)(error|fail|exception|critical)/ | sort @timestamp desc | limit $LIMIT" \
  --query 'queryId' --output text)

echo "Query ID: $QUERY_ID"
echo "Waiting for results..."

# Wait for query to complete
for i in {1..10}; do
  sleep 1
  echo -n "."
done
echo ""
echo ""

RESULT=$(aws logs get-query-results --query-id $QUERY_ID)
ERROR_COUNT=$(echo "$RESULT" | jq -r '.results | length')
echo "Found $ERROR_COUNT errors"

# Output results
if [ "$HUMAN_OUTPUT" = false ]; then
    exec 1>&3  # Restore stdout

    # Output as JSON
    jq -n \
        --arg log_group "$LOG_GROUP" \
        --argjson hours "$HOURS" \
        --argjson limit "$LIMIT" \
        --argjson result "$RESULT" \
        '{
            operation: "find_recent_errors",
            log_group: $log_group,
            hours_back: $hours,
            limit: $limit,
            count: ($result.results | length),
            errors: [
                $result.results[] | {
                    timestamp: .[0].value,
                    message: .[1].value
                }
            ]
        }'
else
    exec 1>&3  # Restore stdout

    # Human-readable output
    echo "=== Recent Errors ==="
    echo "$RESULT" | jq -r '.results[] | "\(.[0].value) \(.[1].value)"'
fi
