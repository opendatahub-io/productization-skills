#!/bin/bash
# Run a CloudWatch Logs Insights query and wait for results
# Usage: ./run_insights_query.sh <log-group> <hours-back> <query-string>

set -euo pipefail

if [ $# -lt 3 ]; then
  echo "Usage: $0 <log-group> <hours-back> <query-string>"
  echo ""
  echo "Example:"
  echo "  $0 /aws/application/myapp 24 'fields @timestamp | filter @message like /(?i)error/ | stats count()'"
  exit 1
fi

LOG_GROUP="$1"
HOURS="$2"
QUERY="$3"

START_TIME=$(date -d "$HOURS hours ago" +%s)
END_TIME=$(date +%s)

echo "Log Group: $LOG_GROUP"
echo "Time Range: $(date -d @$START_TIME) to $(date -d @$END_TIME)"
echo "Query: $QUERY"
echo ""

QUERY_ID=$(aws logs start-query \
  --log-group-name "$LOG_GROUP" \
  --start-time $START_TIME \
  --end-time $END_TIME \
  --query-string "$QUERY" \
  --query 'queryId' --output text)

echo "Query ID: $QUERY_ID"
echo "Waiting for results..."

# Wait with progress indicator
for i in {1..10}; do
  sleep 1
  echo -n "."
done
echo ""
echo ""

aws logs get-query-results --query-id $QUERY_ID
