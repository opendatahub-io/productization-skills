#!/bin/bash
# Tail CloudWatch Logs in real-time
# Usage: ./tail_logs.sh <log-group-name> [filter-pattern] [since]
# Examples:
#   ./tail_logs.sh /aws/application/myapp
#   ./tail_logs.sh /aws/application/myapp "ERROR"
#   ./tail_logs.sh /aws/application/myapp "ERROR" 1h

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <log-group-name> [filter-pattern] [since]"
  echo ""
  echo "Examples:"
  echo "  $0 /aws/application/myapp"
  echo "  $0 /aws/application/myapp 'ERROR'"
  echo "  $0 /aws/application/myapp 'ERROR' 1h"
  echo ""
  echo "Time formats: 1h, 30m, 2d, 5s"
  exit 1
fi

LOG_GROUP="$1"
FILTER="${2:-}"
SINCE="${3:-1h}"

echo "Tailing logs from: $LOG_GROUP"

if [ -z "$FILTER" ]; then
  echo "Since: $SINCE"
  aws logs tail "$LOG_GROUP" --since "$SINCE" --follow
else
  echo "Filter: $FILTER"
  echo "Since: $SINCE"
  aws logs tail "$LOG_GROUP" --since "$SINCE" --follow --filter-pattern "$FILTER"
fi
