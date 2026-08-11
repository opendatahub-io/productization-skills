#!/bin/bash
# List CloudWatch Log Streams
# Usage: ./list_log_streams.sh <log-group-name> [limit] [stream-prefix] [--human]
# Examples:
#   ./list_log_streams.sh /aws/application/myapp
#   ./list_log_streams.sh /aws/application/myapp 10
#   ./list_log_streams.sh /aws/application/myapp 10 2024/01/15 --human

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

if [ $# -lt 1 ]; then
    echo '{"error": "Missing required arguments", "usage": "list_log_streams.sh <log-group-name> [limit] [stream-prefix] [--human]"}' >&2
    exit 1
fi

LOG_GROUP="$1"
LIMIT="${2:-10}"
STREAM_PREFIX="${3:-}"

# Progress to stderr if JSON output
if [ "$HUMAN_OUTPUT" = false ]; then
    exec 3>&1  # Save stdout
    exec 1>&2  # Redirect stdout to stderr for progress messages
fi

echo "Listing recent log streams for: $LOG_GROUP"

if [ -z "$STREAM_PREFIX" ]; then
    RESULT=$(aws logs describe-log-streams \
        --log-group-name "$LOG_GROUP" \
        --order-by LastEventTime \
        --descending \
        --max-items "$LIMIT")
else
    echo "Filtering by prefix: $STREAM_PREFIX"
    RESULT=$(aws logs describe-log-streams \
        --log-group-name "$LOG_GROUP" \
        --log-stream-name-prefix "$STREAM_PREFIX" \
        --order-by LastEventTime \
        --descending \
        --max-items "$LIMIT")
fi

STREAM_COUNT=$(echo "$RESULT" | jq -r '.logStreams | length')
echo "Found $STREAM_COUNT log stream(s)"

# Output results
if [ "$HUMAN_OUTPUT" = false ]; then
    exec 1>&3  # Restore stdout

    # Output as JSON
    echo "$RESULT" | jq --arg log_group "$LOG_GROUP" '{
        operation: "list_log_streams",
        log_group: $log_group,
        count: (.logStreams | length),
        log_streams: [.logStreams[] | {
            name: .logStreamName,
            last_event_time: .lastEventTime,
            last_event_time_human: ((.lastEventTime // 0) / 1000 | strftime("%Y-%m-%d %H:%M:%S")),
            first_event_time: .firstEventTime,
            stored_bytes: .storedBytes
        }]
    }'
else
    exec 1>&3  # Restore stdout

    # Human-readable output
    echo "=== Log Streams for $LOG_GROUP ==="
    echo "$RESULT" | jq -r '.logStreams[] |
        "\(.logStreamName)\t\((.lastEventTime // 0) / 1000 | strftime("%Y-%m-%d %H:%M:%S"))\t\(.storedBytes // 0) bytes"' | column -t
fi
