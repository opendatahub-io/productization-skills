#!/bin/bash
# List CloudWatch Log Groups
# Usage: ./list_log_groups.sh [prefix] [--human]
# Examples:
#   ./list_log_groups.sh                    # List all log groups (JSON)
#   ./list_log_groups.sh /aws/lambda/       # List Lambda log groups (JSON)
#   ./list_log_groups.sh /aws/app --human   # List with human-readable format

set -euo pipefail

# Parse flags
HUMAN_OUTPUT=false
PREFIX=""

for arg in "$@"; do
    case $arg in
        --human)
            HUMAN_OUTPUT=true
            ;;
        *)
            if [ -z "$PREFIX" ] && [[ "$arg" != --* ]]; then
                PREFIX="$arg"
            fi
            ;;
    esac
done

# Progress to stderr if JSON output
if [ "$HUMAN_OUTPUT" = false ]; then
    exec 3>&1  # Save stdout
    exec 1>&2  # Redirect stdout to stderr for progress messages
fi

if [ -z "$PREFIX" ]; then
    echo "Listing all log groups..."
    RESULT=$(aws logs describe-log-groups)
else
    echo "Listing log groups with prefix: $PREFIX"
    RESULT=$(aws logs describe-log-groups --log-group-name-prefix "$PREFIX")
fi

LOG_GROUP_COUNT=$(echo "$RESULT" | jq -r '.logGroups | length')
echo "Found $LOG_GROUP_COUNT log group(s)"

# Output results
if [ "$HUMAN_OUTPUT" = false ]; then
    exec 1>&3  # Restore stdout

    # Output as JSON
    echo "$RESULT" | jq '{
        operation: "list_log_groups",
        prefix: "'"${PREFIX:-all}"'",
        count: (.logGroups | length),
        log_groups: [.logGroups[] | {
            name: .logGroupName,
            size_bytes: .storedBytes,
            retention_days: .retentionInDays,
            creation_time: .creationTime
        }]
    }'
else
    exec 1>&3  # Restore stdout

    # Human-readable table output
    echo "$RESULT" | jq -r '.logGroups[] | "\(.logGroupName)\t\(.storedBytes // 0) bytes"' | column -t
fi
