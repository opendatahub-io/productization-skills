#!/usr/bin/env bash
#
# Analyze all failed jobs in a GitLab CI pipeline
#
# Usage:
#   analyze_job_failures.sh <owner/repo> <pipeline-id>
#   analyze_job_failures.sh --help

set -euo pipefail

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] <owner/repo> <pipeline-id>

Analyze all failed jobs in a GitLab CI pipeline.

ARGUMENTS:
    owner/repo             GitLab repository (e.g., gitlab-org/gitlab)
    pipeline-id            Pipeline ID to analyze

OUTPUT:
    - List of failed jobs
    - Error summary for each job
    - Common error patterns
    - Recommended actions

EXAMPLES:
    # Analyze failures in pipeline 12345
    $(basename "$0") owner/repo 12345

OPTIONS:
    -h, --help              Show this help message
    --verbose               Show full error details

EOF
}

# Parse arguments
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        *)
            break
            ;;
    esac
done

if [[ $# -lt 2 ]]; then
    echo "Error: Missing required arguments" >&2
    show_usage
    exit 1
fi

REPO="$1"
PIPELINE_ID="$2"

# URL-encode repo for API calls
ENCODED_REPO="${REPO//\//%2F}"

# Check if glab is available
if ! command -v glab &> /dev/null; then
    echo "Error: glab command not found" >&2
    exit 1
fi

# Check if jq is available
HAS_JQ=false
if command -v jq &> /dev/null; then
    HAS_JQ=true
fi

# Temporary directory
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

JOBS_JSON="$TEMP_DIR/jobs.json"

# Fetch all jobs in the pipeline
glab api --method GET "projects/$ENCODED_REPO/pipelines/$PIPELINE_ID/jobs" > "$JOBS_JSON"

# Extract failed job IDs
if $HAS_JQ; then
    FAILED_JOBS=$(jq -r '.[] | select(.status == "failed") | .id' < "$JOBS_JSON")
    FAILED_COUNT=$(echo "$FAILED_JOBS" | grep -c "^" || echo "0")
else
    echo "Error: jq is required for this script" >&2
    exit 1
fi

# Output header
cat << EOF
╔════════════════════════════════════════════════════════════════╗
║               Pipeline Failure Analysis                        ║
╚════════════════════════════════════════════════════════════════╝

Repository: $REPO
Pipeline: #$PIPELINE_ID
Failed Jobs: $FAILED_COUNT

EOF

# If no failed jobs, exit
if [[ $FAILED_COUNT -eq 0 ]]; then
    echo "✅ No failed jobs found in this pipeline"
    exit 0
fi

echo "────────────────────────────────────────────────────────────────"
echo ""

# Analyze each failed job
JOB_NUM=1
while read -r JOB_ID; do
    [[ -z "$JOB_ID" ]] && continue

    # Get job metadata
    JOB_DATA=$(jq --arg id "$JOB_ID" '.[] | select(.id == ($id | tonumber))' < "$JOBS_JSON")

    JOB_NAME=$(echo "$JOB_DATA" | jq -r '.name')
    JOB_STAGE=$(echo "$JOB_DATA" | jq -r '.stage')
    JOB_FAILURE_REASON=$(echo "$JOB_DATA" | jq -r '.failure_reason // "unknown"')
    JOB_DURATION=$(echo "$JOB_DATA" | jq -r '.duration // 0')

    # Format duration
    if [[ $JOB_DURATION -lt 60 ]]; then
        JOB_DURATION_FMT="${JOB_DURATION}s"
    else
        minutes=$((JOB_DURATION / 60))
        secs=$((JOB_DURATION % 60))
        JOB_DURATION_FMT="${minutes}m ${secs}s"
    fi

    echo "[$JOB_NUM/$FAILED_COUNT] Job #$JOB_ID: $JOB_NAME"
    echo "  Stage:          $JOB_STAGE"
    echo "  Duration:       $JOB_DURATION_FMT"
    echo "  Failure Reason: $JOB_FAILURE_REASON"
    echo ""

    # Fetch job log (last 50 lines)
    LOG_FILE="$TEMP_DIR/job_${JOB_ID}.log"
    glab ci trace "$JOB_ID" -R "$REPO" 2>/dev/null | tail -100 > "$LOG_FILE" || echo "Could not fetch logs" > "$LOG_FILE"

    # Extract key errors
    ERROR_SUMMARY=$(grep -i -E "(error|failed|exception|fatal)" "$LOG_FILE" | head -5 || echo "No obvious errors found")

    echo "  Key Errors:"
    while IFS= read -r line; do
        echo "    - ${line:0:100}"
    done <<< "$ERROR_SUMMARY"
    echo ""

    # Recommendations based on failure reason
    case "$JOB_FAILURE_REASON" in
        script_failure)
            echo "  💡 Recommendation: Review script errors and fix the failing command"
            ;;
        stuck_or_timeout_failure)
            echo "  💡 Recommendation: Job timed out - consider optimizing or increasing timeout"
            ;;
        runner_system_failure)
            echo "  💡 Recommendation: Runner infrastructure issue - retry or check runner status"
            ;;
        missing_dependency_failure)
            echo "  💡 Recommendation: Required service not available - verify service dependencies"
            ;;
        unmet_prerequisites)
            echo "  💡 Recommendation: Check dependent jobs - they may have failed first"
            ;;
        *)
            echo "  💡 Recommendation: Review error logs for specific details"
            ;;
    esac

    echo ""
    echo "────────────────────────────────────────────────────────────────"
    echo ""

    JOB_NUM=$((JOB_NUM + 1))
done <<< "$FAILED_JOBS"

# Analyze common patterns across all failed jobs
echo "## Common Error Patterns"
echo ""

ALL_ERRORS="$TEMP_DIR/all_errors.txt"
cat "$TEMP_DIR"/job_*.log | grep -i -E "(error|failed|exception|fatal)" > "$ALL_ERRORS" 2>/dev/null || true

if [[ -s "$ALL_ERRORS" ]]; then
    # Extract most common error types
    COMMON_PATTERNS=$(grep -o -i -E "(compilation error|test.*failed|timeout|connection refused|no space left|segmentation fault|nullpointerexception|modulenotfounderror|importerror)" "$ALL_ERRORS" | sort | uniq -c | sort -rn | head -5)

    if [[ -n "$COMMON_PATTERNS" ]]; then
        echo "Most frequent error patterns:"
        echo ""
        while IFS= read -r pattern; do
            echo "  $pattern"
        done <<< "$COMMON_PATTERNS"
    else
        echo "No common patterns detected across jobs"
    fi
else
    echo "No errors extracted from logs"
fi

echo ""
echo "────────────────────────────────────────────────────────────────"
echo ""

# Stage-level analysis
echo "## Failure by Stage"
echo ""

STAGE_FAILURES=$(jq -r '.[] | select(.status == "failed") | .stage' < "$JOBS_JSON" | sort | uniq -c)

if [[ -n "$STAGE_FAILURES" ]]; then
    echo "Failed jobs per stage:"
    echo ""
    while IFS= read -r stage_info; do
        echo "  $stage_info"
    done <<< "$STAGE_FAILURES"
else
    echo "No stage information available"
fi

echo ""
echo "────────────────────────────────────────────────────────────────"
echo ""

# Next steps
cat << EOF
## Next Steps

1. Review detailed error logs for each failed job
2. Check recent commits for breaking changes
3. Verify CI/CD environment variables and configuration
4. Consider re-running jobs to check for flakiness
5. Fix jobs in dependency order (earlier stages first)

EOF

# Verbose output
if $VERBOSE; then
    echo "════════════════════════════════════════════════════════════════"
    echo "VERBOSE: Full job details"
    echo "════════════════════════════════════════════════════════════════"
    echo ""

    while read -r JOB_ID; do
        [[ -z "$JOB_ID" ]] && continue

        echo "Job #$JOB_ID Full Log:"
        echo "────────────────────────────────────────────────────────────────"
        cat "$TEMP_DIR/job_${JOB_ID}.log"
        echo ""
        echo "────────────────────────────────────────────────────────────────"
        echo ""
    done <<< "$FAILED_JOBS"
fi
