#!/bin/bash
# Analyze errors in a CloudWatch log group
# Usage: ./analyze_errors.sh <log-group-name> <hours-back> [--human] [--exclude-noise] [--compare-previous]
# Example: ./analyze_errors.sh aipcc-large-aarch64 24
# Example: ./analyze_errors.sh aipcc-large-aarch64 24 --exclude-noise --compare-previous

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libraries
source "$SCRIPT_DIR/lib/query_helpers.sh"
source "$SCRIPT_DIR/lib/normalize_errors.sh"

# Parse flags
HUMAN_OUTPUT=false
EXCLUDE_NOISE=false
COMPARE_PREVIOUS=false

for arg in "$@"; do
    case $arg in
        --human)
            HUMAN_OUTPUT=true
            ;;
        --exclude-noise)
            EXCLUDE_NOISE=true
            ;;
        --compare-previous)
            COMPARE_PREVIOUS=true
            ;;
    esac
done

# Remove flags from arguments
set -- "${@/--human/}"
set -- "${@/--exclude-noise/}"
set -- "${@/--compare-previous/}"

if [ $# -lt 2 ]; then
    echo '{"error": "Missing required arguments", "usage": "analyze_errors.sh <log-group-name> <hours-back> [--human] [--exclude-noise] [--compare-previous]"}' >&2
    exit 1
fi

LOG_GROUP="$1"
HOURS="$2"

START_TIME=$(date -d "$HOURS hours ago" +%s)
END_TIME=$(date +%s)

# Build noise filter from patterns file
build_noise_filter() {
    local noise_file="$SCRIPT_DIR/noise-patterns.txt"
    local filter=""

    if [ "$EXCLUDE_NOISE" = true ] && [ -f "$noise_file" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            # Skip empty lines and comments
            [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

            # Trim whitespace
            pattern=$(echo "$line" | xargs)
            [ -z "$pattern" ] && continue

            # Add to filter
            if [ -z "$filter" ]; then
                filter="and @message not like /${pattern}/"
            else
                filter="${filter} and @message not like /${pattern}/"
            fi
        done < "$noise_file"
    fi

    echo "$filter"
}

NOISE_FILTER=$(build_noise_filter)

# Progress to stderr if JSON output
if [ "$HUMAN_OUTPUT" = false ]; then
    exec 3>&1  # Save stdout
    exec 1>&2  # Redirect stdout to stderr for progress messages
fi

echo "=== Error Analysis for $LOG_GROUP (last ${HOURS}h) ==="
echo "Time range: $(date -d @$START_TIME) to $(date -d @$END_TIME)"
echo ""

# Query 1: Total error count
echo "Step 1/5: Counting total errors" >&2
QUERY_ID=$(aws logs start-query \
  --log-group-name "$LOG_GROUP" \
  --start-time $START_TIME \
  --end-time $END_TIME \
  --query-string 'fields @timestamp | filter @message like /(?i)(error|fail|exception|critical)/ | stats count() as total_errors' \
  --query 'queryId' --output text)
TOTAL_RESULT=$(wait_for_query "$QUERY_ID" "  Counting")
TOTAL=$(echo "$TOTAL_RESULT" | jq -r '.results[0][0].value // "0"')
echo "Total errors: $TOTAL" >&2
echo "" >&2

# Query 2: Top error messages
echo "Step 2/5: Finding top error messages" >&2
QUERY_ID=$(aws logs start-query \
  --log-group-name "$LOG_GROUP" \
  --start-time $START_TIME \
  --end-time $END_TIME \
  --query-string 'fields @timestamp, @message | filter @message like /(?i)(error|fail|exception|critical)/ | stats count() as error_count by @message | sort error_count desc | limit 20' \
  --query 'queryId' --output text)
TOP_ERRORS_RESULT=$(wait_for_query "$QUERY_ID" "  Grouping by message")
TOP_ERROR_COUNT=$(echo "$TOP_ERRORS_RESULT" | jq -r '.results | length')
echo "Found $TOP_ERROR_COUNT distinct error types" >&2
echo "" >&2

# Query 3: Critical errors (excluding common warnings/noise)
echo "Step 3/5: Finding critical/unique errors" >&2
if [ "$EXCLUDE_NOISE" = true ] && [ -n "$NOISE_FILTER" ]; then
    echo "Applying noise filter: excluding $(echo "$NOISE_FILTER" | grep -o "not like" | wc -l) pattern(s)" >&2
fi
CRITICAL_QUERY="fields @timestamp, @message | filter @message like /(?i)(error|fail|exception|critical)/ ${NOISE_FILTER} | stats count() as error_count by @message | sort error_count desc | limit 15"
QUERY_ID=$(aws logs start-query \
  --log-group-name "$LOG_GROUP" \
  --start-time $START_TIME \
  --end-time $END_TIME \
  --query-string "$CRITICAL_QUERY" \
  --query 'queryId' --output text)
CRITICAL_ERRORS_RESULT=$(wait_for_query "$QUERY_ID" "  Finding critical errors")
CRITICAL_COUNT=$(echo "$CRITICAL_ERRORS_RESULT" | jq -r '.results | length')
echo "Found $CRITICAL_COUNT critical error types" >&2
echo "" >&2

# Query 4: Hourly distribution
echo "Step 4/5: Analyzing hourly distribution" >&2
QUERY_ID=$(aws logs start-query \
  --log-group-name "$LOG_GROUP" \
  --start-time $START_TIME \
  --end-time $END_TIME \
  --query-string 'fields @timestamp | filter @message like /(?i)(error|fail|exception|critical)/ | stats count() as error_count by bin(1h)' \
  --query 'queryId' --output text)
HOURLY_DIST_RESULT=$(wait_for_query "$QUERY_ID" "  Computing distribution")
HOURS_WITH_ERRORS=$(echo "$HOURLY_DIST_RESULT" | jq -r '.results | length')
echo "Errors distributed across $HOURS_WITH_ERRORS time buckets" >&2
echo "" >&2

# Query 5: Severity classification
echo "Step 5/5: Classifying errors by severity" >&2
SEVERITY_RESULT=$(jq -n '{
    critical: 0,
    error: 0,
    warning: 0,
    failed: 0
}')

# Count critical severity
QUERY_ID=$(aws logs start-query \
  --log-group-name "$LOG_GROUP" \
  --start-time $START_TIME \
  --end-time $END_TIME \
  --query-string 'fields @timestamp | filter @message like /(?i)(critical|fatal)/ | stats count() as count' \
  --query 'queryId' --output text)
CRITICAL_SEVERITY=$(wait_for_query "$QUERY_ID" "  Critical" | jq -r '.results[0][0].value // "0"')

# Count error severity
QUERY_ID=$(aws logs start-query \
  --log-group-name "$LOG_GROUP" \
  --start-time $START_TIME \
  --end-time $END_TIME \
  --query-string 'fields @timestamp | filter @message like /(?i)error/ and @message not like /(?i)(critical|fatal|warn|warning)/ | stats count() as count' \
  --query 'queryId' --output text)
ERROR_SEVERITY=$(wait_for_query "$QUERY_ID" "  Error" | jq -r '.results[0][0].value // "0"')

# Count warning severity
QUERY_ID=$(aws logs start-query \
  --log-group-name "$LOG_GROUP" \
  --start-time $START_TIME \
  --end-time $END_TIME \
  --query-string 'fields @timestamp | filter @message like /(?i)(warn|warning)/ | stats count() as count' \
  --query 'queryId' --output text)
WARNING_SEVERITY=$(wait_for_query "$QUERY_ID" "  Warning" | jq -r '.results[0][0].value // "0"')

# Count failed/exception severity
QUERY_ID=$(aws logs start-query \
  --log-group-name "$LOG_GROUP" \
  --start-time $START_TIME \
  --end-time $END_TIME \
  --query-string 'fields @timestamp | filter (@message like /(?i)(fail|exception)/) and @message not like /(?i)(error|critical|fatal|warn|warning)/ | stats count() as count' \
  --query 'queryId' --output text)
FAILED_SEVERITY=$(wait_for_query "$QUERY_ID" "  Failed" | jq -r '.results[0][0].value // "0"')

SEVERITY_RESULT=$(jq -n \
    --argjson critical "$CRITICAL_SEVERITY" \
    --argjson error "$ERROR_SEVERITY" \
    --argjson warning "$WARNING_SEVERITY" \
    --argjson failed "$FAILED_SEVERITY" \
    '{
        critical: $critical,
        error: $error,
        warning: $warning,
        failed: $failed
    }')

echo "Severity classification: Critical=$CRITICAL_SEVERITY, Error=$ERROR_SEVERITY, Warning=$WARNING_SEVERITY, Failed=$FAILED_SEVERITY"
echo ""

# Comparison with previous period (if requested)
COMPARISON_DATA=null
if [ "$COMPARE_PREVIOUS" = true ]; then
    echo "=== Comparison with Previous Period ==="
    PREV_START_TIME=$(date -d "$((HOURS * 2)) hours ago" +%s)
    PREV_END_TIME=$START_TIME
    echo "Previous period: $(date -d @$PREV_START_TIME) to $(date -d @$PREV_END_TIME)"

    # Query previous period total errors
    QUERY_ID=$(aws logs start-query \
      --log-group-name "$LOG_GROUP" \
      --start-time $PREV_START_TIME \
      --end-time $PREV_END_TIME \
      --query-string 'fields @timestamp | filter @message like /(?i)(error|fail|exception|critical)/ | stats count() as total_errors' \
      --query 'queryId' --output text)
    sleep 5
    PREV_TOTAL=$(aws logs get-query-results --query-id $QUERY_ID | jq -r '.results[0][0].value // "0"')

    # Calculate comparison metrics
    CURRENT_TOTAL_NUM=$(echo "$TOTAL" | bc 2>/dev/null || echo "$TOTAL")
    PREV_TOTAL_NUM=$(echo "$PREV_TOTAL" | bc 2>/dev/null || echo "$PREV_TOTAL")

    if [ "$PREV_TOTAL_NUM" -gt 0 ]; then
        CHANGE=$(awk "BEGIN {printf \"%.2f\", (($CURRENT_TOTAL_NUM - $PREV_TOTAL_NUM) / $PREV_TOTAL_NUM) * 100}")
        if (( $(echo "$CHANGE > 0" | bc -l) )); then
            TREND="increasing"
            CHANGE_STR="+${CHANGE}%"
        elif (( $(echo "$CHANGE < 0" | bc -l) )); then
            TREND="decreasing"
            CHANGE_STR="${CHANGE}%"
        else
            TREND="stable"
            CHANGE_STR="0%"
        fi
    else
        CHANGE=0
        TREND="new"
        CHANGE_STR="N/A"
    fi

    echo "Current: $CURRENT_TOTAL_NUM errors, Previous: $PREV_TOTAL_NUM errors, Change: $CHANGE_STR, Trend: $TREND"
    echo ""

    COMPARISON_DATA=$(jq -n \
        --argjson current "$CURRENT_TOTAL_NUM" \
        --argjson previous "$PREV_TOTAL_NUM" \
        --argjson hours "$HOURS" \
        --arg change "$CHANGE_STR" \
        --arg trend "$TREND" \
        '{
            current_period: {
                total_errors: $current,
                hours: $hours
            },
            previous_period: {
                total_errors: $previous,
                hours: $hours
            },
            change: $change,
            trend: $trend
        }')
fi

# Prepare output data with flattened CloudWatch Insights results
# First flatten the results
TOP_ERRORS_FLAT=$(echo "$TOP_ERRORS_RESULT" | jq '[
    .results[] | {
        message: (.[0].value // ""),
        count: (.[1].value | tonumber)
    }
]')

CRITICAL_ERRORS_FLAT=$(echo "$CRITICAL_ERRORS_RESULT" | jq '[
    .results[] | {
        message: (.[0].value // ""),
        count: (.[1].value | tonumber)
    }
]')

# Add pattern normalization and percentages
TOP_ERRORS_NORMALIZED=$(normalize_insights_errors "$TOP_ERRORS_FLAT" | jq --arg total "$TOTAL" '[
    .[] | . + {
        percentage: (if ($total | tonumber) > 0 then ((.count / ($total | tonumber)) * 100 | . * 100 | round / 100) else 0 end)
    }
]')

CRITICAL_ERRORS_NORMALIZED=$(normalize_insights_errors "$CRITICAL_ERRORS_FLAT" | jq --arg total "$TOTAL" '[
    .[] | . + {
        percentage: (if ($total | tonumber) > 0 then ((.count / ($total | tonumber)) * 100 | . * 100 | round / 100) else 0 end)
    }
]')

# Group by pattern for pattern-based analysis
TOP_ERRORS_BY_PATTERN=$(echo "$TOP_ERRORS_NORMALIZED" | jq '
    group_by(.pattern) | map({
        pattern: .[0].pattern,
        total_count: (map(.count) | add),
        occurrences: length,
        examples: [.[0:3][] | {message: .message, count: .count}]
    }) | sort_by(-.total_count) | .[0:10]
')

FULL_DATA=$(jq -n \
    --arg log_group "$LOG_GROUP" \
    --argjson hours "$HOURS" \
    --argjson start_time "$START_TIME" \
    --argjson end_time "$END_TIME" \
    --arg total "$TOTAL" \
    --argjson top_errors "$TOP_ERRORS_NORMALIZED" \
    --argjson critical_errors "$CRITICAL_ERRORS_NORMALIZED" \
    --argjson top_errors_by_pattern "$TOP_ERRORS_BY_PATTERN" \
    --argjson hourly_dist "$HOURLY_DIST_RESULT" \
    --argjson severity "$SEVERITY_RESULT" \
    --argjson comparison "$COMPARISON_DATA" \
    '{
        log_group: $log_group,
        hours_analyzed: $hours,
        start_time: $start_time,
        end_time: $end_time,
        total_errors: $total,
        by_severity: $severity,
        comparison: $comparison,
        top_errors: $top_errors,
        critical_errors: $critical_errors,
        top_errors_by_pattern: $top_errors_by_pattern,
        hourly_distribution: [
            $hourly_dist.results[] | {
                time_bucket: (.[0].value // ""),
                error_count: (.[1].value | tonumber)
            }
        ]
    }')

# Output results
if [ "$HUMAN_OUTPUT" = false ]; then
    exec 1>&3  # Restore stdout

    # Output full data as JSON
    echo "$FULL_DATA"
else
    # Human-readable output
    exec 1>&3  # Restore stdout

    echo "=== Error Analysis Results ==="
    echo "Log Group: $LOG_GROUP"
    echo "Time Range: Last $HOURS hours"
    echo "Total Errors: $TOTAL"
    echo ""

    # Show comparison if available
    if [ "$COMPARE_PREVIOUS" = true ]; then
        echo "Comparison with Previous Period:"
        echo "$FULL_DATA" | jq -r '.comparison | if . != null then "  Current: \(.current_period.total_errors) errors\n  Previous: \(.previous_period.total_errors) errors\n  Change: \(.change)\n  Trend: \(.trend)" else "  No comparison data" end'
        echo ""
    fi

    echo "By Severity:"
    echo "$FULL_DATA" | jq -r '.by_severity | "  Critical: \(.critical)\n  Error: \(.error)\n  Warning: \(.warning)\n  Failed: \(.failed)"'
    echo ""

    echo "Top Errors by Frequency:"
    echo "$FULL_DATA" | jq -r '.top_errors[0:10][] | "  \(.count)x (\(.percentage)%): \(.message | .[0:100])"'
    echo ""

    echo "Top Error Patterns (grouped by similarity):"
    echo "$FULL_DATA" | jq -r '.top_errors_by_pattern[] | "  \(.total_count)x: \(.pattern | .[0:100])\n    (\(.occurrences) unique variations)"'
    echo ""

    echo "Critical Errors:"
    echo "$FULL_DATA" | jq -r '.critical_errors[] | "  \(.count)x (\(.percentage)%): \(.message)"'
    echo ""

    echo "Hourly Distribution:"
    echo "$FULL_DATA" | jq -r '.hourly_distribution[] | "  \(.time_bucket): \(.error_count) errors"'
fi
