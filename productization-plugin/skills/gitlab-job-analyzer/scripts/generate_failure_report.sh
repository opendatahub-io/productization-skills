#!/usr/bin/env bash
#
# Generate comprehensive failure report for a GitLab CI pipeline
#
# Usage:
#   generate_failure_report.sh <owner/repo> <pipeline-id>
#   generate_failure_report.sh --help

set -euo pipefail

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] <owner/repo> <pipeline-id>

Generate comprehensive failure report for a GitLab CI pipeline.

ARGUMENTS:
    owner/repo             GitLab repository (e.g., gitlab-org/gitlab)
    pipeline-id            Pipeline ID to analyze

OUTPUT:
    Markdown-formatted report with:
    - Pipeline metadata
    - Job summary (pass/fail counts)
    - Failed job details
    - Error excerpts from logs
    - Common error patterns
    - Recommendations

EXAMPLES:
    # Generate report for pipeline 12345
    $(basename "$0") owner/repo 12345

    # Save report to file
    $(basename "$0") owner/repo 12345 > failure-report.md

OPTIONS:
    -h, --help              Show this help message
    --log-lines N           Number of log lines to show per failed job (default: 50)
    --all-jobs              Include successful jobs in report

EOF
}

# Parse arguments
LOG_LINES=50
INCLUDE_ALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        --log-lines)
            LOG_LINES="$2"
            shift 2
            ;;
        --all-jobs)
            INCLUDE_ALL=true
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

# Check if jq is available (optional but recommended)
HAS_JQ=false
if command -v jq &> /dev/null; then
    HAS_JQ=true
fi

# Temporary directory for storing data
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

PIPELINE_JSON="$TEMP_DIR/pipeline.json"
JOBS_JSON="$TEMP_DIR/jobs.json"

# Fetch pipeline details
glab api --method GET "projects/$ENCODED_REPO/pipelines/$PIPELINE_ID" > "$PIPELINE_JSON"

# Fetch all jobs in the pipeline
glab api --method GET "projects/$ENCODED_REPO/pipelines/$PIPELINE_ID/jobs" > "$JOBS_JSON"

# Extract pipeline metadata
if $HAS_JQ; then
    PIPELINE_STATUS=$(jq -r '.status' < "$PIPELINE_JSON")
    PIPELINE_REF=$(jq -r '.ref' < "$PIPELINE_JSON")
    PIPELINE_SHA=$(jq -r '.sha' < "$PIPELINE_JSON")
    PIPELINE_CREATED=$(jq -r '.created_at' < "$PIPELINE_JSON")
    PIPELINE_DURATION=$(jq -r '.duration // 0' < "$PIPELINE_JSON")
    PIPELINE_USER=$(jq -r '.user.username // "unknown"' < "$PIPELINE_JSON")
else
    PIPELINE_STATUS="unknown"
    PIPELINE_REF="unknown"
    PIPELINE_SHA="unknown"
    PIPELINE_CREATED="unknown"
    PIPELINE_DURATION="0"
    PIPELINE_USER="unknown"
fi

# Calculate job statistics
if $HAS_JQ; then
    TOTAL_JOBS=$(jq 'length' < "$JOBS_JSON")
    PASSED_JOBS=$(jq '[.[] | select(.status == "success")] | length' < "$JOBS_JSON")
    FAILED_JOBS=$(jq '[.[] | select(.status == "failed")] | length' < "$JOBS_JSON")
    SKIPPED_JOBS=$(jq '[.[] | select(.status == "skipped" or .status == "canceled")] | length' < "$JOBS_JSON")
    RUNNING_JOBS=$(jq '[.[] | select(.status == "running" or .status == "pending")] | length' < "$JOBS_JSON")
else
    TOTAL_JOBS=0
    PASSED_JOBS=0
    FAILED_JOBS=0
    SKIPPED_JOBS=0
    RUNNING_JOBS=0
fi

# Calculate percentages
if [[ $TOTAL_JOBS -gt 0 ]]; then
    PASS_PCT=$((PASSED_JOBS * 100 / TOTAL_JOBS))
    FAIL_PCT=$((FAILED_JOBS * 100 / TOTAL_JOBS))
else
    PASS_PCT=0
    FAIL_PCT=0
fi

# Format duration
format_duration() {
    local seconds=$1
    if [[ $seconds -lt 60 ]]; then
        echo "${seconds}s"
    else
        local minutes=$((seconds / 60))
        local secs=$((seconds % 60))
        echo "${minutes}m ${secs}s"
    fi
}

DURATION_FORMATTED=$(format_duration "$PIPELINE_DURATION")

# Output report header
cat << EOF
# Pipeline Failure Report

**Repository:** $REPO
**Pipeline:** [#$PIPELINE_ID](https://gitlab.com/$REPO/-/pipelines/$PIPELINE_ID)
**Ref:** \`$PIPELINE_REF\`
**SHA:** \`${PIPELINE_SHA:0:8}\`
**Status:** **$PIPELINE_STATUS**
**Duration:** $DURATION_FORMATTED
**Created:** $PIPELINE_CREATED
**Triggered by:** @$PIPELINE_USER

---

## Summary

- **Total Jobs:** $TOTAL_JOBS
- **Passed:** $PASSED_JOBS ($PASS_PCT%)
- **Failed:** $FAILED_JOBS ($FAIL_PCT%)
- **Skipped/Canceled:** $SKIPPED_JOBS
- **Running/Pending:** $RUNNING_JOBS

EOF

# If pipeline succeeded, note it
if [[ "$PIPELINE_STATUS" == "success" ]]; then
    echo "> ✅ Pipeline succeeded - no failures to report"
    echo ""
    exit 0
fi

# Extract failed jobs
if $HAS_JQ; then
    jq -r '.[] | select(.status == "failed") | .id' < "$JOBS_JSON" > "$TEMP_DIR/failed_job_ids.txt"
else
    echo "Warning: jq not available, limited analysis" >&2
    exit 1
fi

# Check if there are failed jobs
if [[ ! -s "$TEMP_DIR/failed_job_ids.txt" ]]; then
    echo "> ℹ️ No failed jobs found (pipeline may have been canceled or is still running)"
    echo ""
    exit 0
fi

# Failed jobs table
cat << EOF
---

## Failed Jobs

| Job ID | Name | Stage | Duration | Failure Reason |
|--------|------|-------|----------|----------------|
EOF

while read -r JOB_ID; do
    JOB_DATA=$(jq --arg id "$JOB_ID" '.[] | select(.id == ($id | tonumber))' < "$JOBS_JSON")

    JOB_NAME=$(echo "$JOB_DATA" | jq -r '.name')
    JOB_STAGE=$(echo "$JOB_DATA" | jq -r '.stage')
    JOB_DURATION=$(echo "$JOB_DATA" | jq -r '.duration // 0')
    JOB_FAILURE_REASON=$(echo "$JOB_DATA" | jq -r '.failure_reason // "unknown"')

    JOB_DURATION_FMT=$(format_duration "$JOB_DURATION")

    echo "| [$JOB_ID](https://gitlab.com/$REPO/-/jobs/$JOB_ID) | \`$JOB_NAME\` | $JOB_STAGE | $JOB_DURATION_FMT | $JOB_FAILURE_REASON |"
done < "$TEMP_DIR/failed_job_ids.txt"

echo ""
echo "---"
echo ""

# Error details section
cat << EOF
## Error Details

EOF

# For each failed job, extract log excerpts
while read -r JOB_ID; do
    JOB_DATA=$(jq --arg id "$JOB_ID" '.[] | select(.id == ($id | tonumber))' < "$JOBS_JSON")

    JOB_NAME=$(echo "$JOB_DATA" | jq -r '.name')
    JOB_STAGE=$(echo "$JOB_DATA" | jq -r '.stage')
    JOB_FAILURE_REASON=$(echo "$JOB_DATA" | jq -r '.failure_reason // "unknown"')

    echo "### Job $JOB_ID: $JOB_NAME"
    echo ""
    echo "**Stage:** $JOB_STAGE  "
    echo "**Failure Reason:** $JOB_FAILURE_REASON"
    echo ""

    # Fetch job log (last N lines)
    LOG_FILE="$TEMP_DIR/job_${JOB_ID}.log"
    glab ci trace "$JOB_ID" -R "$REPO" 2>/dev/null | tail -n "$LOG_LINES" > "$LOG_FILE" || echo "Could not fetch logs" > "$LOG_FILE"

    # Extract errors
    ERROR_LINES=$(grep -i -n -E "(error|failed|exception|fatal)" "$LOG_FILE" | head -20 || echo "")

    if [[ -n "$ERROR_LINES" ]]; then
        echo "**Key Error Lines:**"
        echo ""
        echo '```'
        echo "$ERROR_LINES"
        echo '```'
    else
        echo "**Log Excerpt (last $LOG_LINES lines):**"
        echo ""
        echo '```'
        cat "$LOG_FILE"
        echo '```'
    fi

    echo ""

    # Generate recommendations based on failure reason
    case "$JOB_FAILURE_REASON" in
        script_failure)
            echo "**Recommendation:** Review script errors above and fix the failing command"
            ;;
        stuck_or_timeout_failure)
            echo "**Recommendation:** Job timed out - consider optimizing or increasing timeout"
            ;;
        runner_system_failure)
            echo "**Recommendation:** Runner infrastructure issue - retry or check runner availability"
            ;;
        missing_dependency_failure)
            echo "**Recommendation:** Required service not available - check service dependencies"
            ;;
        unmet_prerequisites)
            echo "**Recommendation:** Job prerequisites not met - check dependent jobs"
            ;;
        *)
            echo "**Recommendation:** Review error logs above for specific failure details"
            ;;
    esac

    echo ""
    echo "---"
    echo ""
done < "$TEMP_DIR/failed_job_ids.txt"

# Analyze common patterns
cat << EOF
## Common Error Patterns

EOF

# Aggregate error patterns from all failed jobs
PATTERN_FILE="$TEMP_DIR/patterns.txt"
while read -r JOB_ID; do
    LOG_FILE="$TEMP_DIR/job_${JOB_ID}.log"
    if [[ -f "$LOG_FILE" ]]; then
        grep -i -o -E "(error|exception|failed|fatal).*" "$LOG_FILE" >> "$PATTERN_FILE" || true
    fi
done < "$TEMP_DIR/failed_job_ids.txt"

if [[ -f "$PATTERN_FILE" && -s "$PATTERN_FILE" ]]; then
    # Count unique patterns (first 5)
    sort "$PATTERN_FILE" | uniq -c | sort -rn | head -5 | while read -r count pattern; do
        echo "- **$pattern** ($count occurrences)"
    done
else
    echo "No common error patterns detected."
fi

echo ""
echo "---"
echo ""

# Next steps section
cat << EOF
## Next Steps

1. Review failed job logs for specific error messages
2. Check if errors are related to recent code changes
3. Verify CI/CD environment variables and secrets
4. Re-run failed jobs to check for flakiness
5. Consider debugging locally with the same job configuration

EOF

# Additional context section
if [[ $SKIPPED_JOBS -gt 0 || $RUNNING_JOBS -gt 0 ]]; then
    cat << EOF
## Additional Context

EOF

    if [[ $SKIPPED_JOBS -gt 0 ]]; then
        echo "- **Skipped/Canceled Jobs:** $SKIPPED_JOBS jobs were skipped or canceled"
    fi

    if [[ $RUNNING_JOBS -gt 0 ]]; then
        echo "- **Running/Pending Jobs:** $RUNNING_JOBS jobs are still running or pending"
    fi

    echo ""
fi

# Footer
cat << EOF
---

*Report generated on $(date -u '+%Y-%m-%d %H:%M:%S UTC')*
EOF
