#!/usr/bin/env bash
#
# Compare two GitLab CI job runs to identify differences
#
# Usage:
#   compare_job_logs.sh <owner/repo> <job-id-1> <job-id-2>
#   compare_job_logs.sh --help

set -euo pipefail

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] <owner/repo> <job-id-1> <job-id-2>

Compare two GitLab CI job runs to identify differences.

ARGUMENTS:
    owner/repo             GitLab repository (e.g., gitlab-org/gitlab)
    job-id-1               First job ID (typically the successful/older job)
    job-id-2               Second job ID (typically the failed/newer job)

OUTPUT:
    - Job metadata comparison (duration, runner, status)
    - Log differences (new errors in job-id-2)
    - Environment differences
    - Recommendations

EXAMPLES:
    # Compare successful job 12345 with failed job 12346
    $(basename "$0") owner/repo 12345 12346

OPTIONS:
    -h, --help              Show this help message
    --context N             Lines of context for diff (default: 5)
    --json                  Output as JSON instead of text

EOF
}

# Parse arguments
CONTEXT_LINES=5
OUTPUT_FORMAT="text"

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        --context)
            CONTEXT_LINES="$2"
            shift 2
            ;;
        --json)
            OUTPUT_FORMAT="json"
            shift
            ;;
        *)
            break
            ;;
    esac
done

if [[ $# -lt 3 ]]; then
    echo "Error: Missing required arguments" >&2
    show_usage
    exit 1
fi

REPO="$1"
JOB_ID_1="$2"
JOB_ID_2="$3"

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

# Fetch job metadata
JOB1_JSON="$TEMP_DIR/job1.json"
JOB2_JSON="$TEMP_DIR/job2.json"

glab api --method GET "projects/$ENCODED_REPO/jobs/$JOB_ID_1" > "$JOB1_JSON"
glab api --method GET "projects/$ENCODED_REPO/jobs/$JOB_ID_2" > "$JOB2_JSON"

# Fetch job logs
JOB1_LOG="$TEMP_DIR/job1.log"
JOB2_LOG="$TEMP_DIR/job2.log"

glab ci trace "$JOB_ID_1" -R "$REPO" > "$JOB1_LOG" 2>/dev/null || echo "Could not fetch log for job $JOB_ID_1" > "$JOB1_LOG"
glab ci trace "$JOB_ID_2" -R "$REPO" > "$JOB2_LOG" 2>/dev/null || echo "Could not fetch log for job $JOB_ID_2" > "$JOB2_LOG"

# Extract metadata
if $HAS_JQ; then
    JOB1_NAME=$(jq -r '.name' < "$JOB1_JSON")
    JOB1_STATUS=$(jq -r '.status' < "$JOB1_JSON")
    JOB1_DURATION=$(jq -r '.duration // 0' < "$JOB1_JSON")
    JOB1_RUNNER=$(jq -r '.runner.description // "unknown"' < "$JOB1_JSON")
    JOB1_CREATED=$(jq -r '.created_at' < "$JOB1_JSON")

    JOB2_NAME=$(jq -r '.name' < "$JOB2_JSON")
    JOB2_STATUS=$(jq -r '.status' < "$JOB2_JSON")
    JOB2_DURATION=$(jq -r '.duration // 0' < "$JOB2_JSON")
    JOB2_RUNNER=$(jq -r '.runner.description // "unknown"' < "$JOB2_JSON")
    JOB2_CREATED=$(jq -r '.created_at' < "$JOB2_JSON")
else
    JOB1_NAME="unknown"
    JOB1_STATUS="unknown"
    JOB1_DURATION="0"
    JOB1_RUNNER="unknown"
    JOB1_CREATED="unknown"

    JOB2_NAME="unknown"
    JOB2_STATUS="unknown"
    JOB2_DURATION="0"
    JOB2_RUNNER="unknown"
    JOB2_CREATED="unknown"
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

JOB1_DURATION_FMT=$(format_duration "$JOB1_DURATION")
JOB2_DURATION_FMT=$(format_duration "$JOB2_DURATION")

# Output report
cat << EOF
╔════════════════════════════════════════════════════════════════╗
║                    Job Comparison Report                       ║
╚════════════════════════════════════════════════════════════════╝

Repository: $REPO

Job 1: #$JOB_ID_1
  Name:     $JOB1_NAME
  Status:   $JOB1_STATUS
  Duration: $JOB1_DURATION_FMT
  Runner:   $JOB1_RUNNER
  Created:  $JOB1_CREATED

Job 2: #$JOB_ID_2
  Name:     $JOB2_NAME
  Status:   $JOB2_STATUS
  Duration: $JOB2_DURATION_FMT
  Runner:   $JOB2_RUNNER
  Created:  $JOB2_CREATED

────────────────────────────────────────────────────────────────

EOF

# Metadata comparison
echo "## Metadata Comparison"
echo ""

# Duration comparison
if [[ $JOB2_DURATION -gt $JOB1_DURATION ]]; then
    DURATION_DIFF=$((JOB2_DURATION - JOB1_DURATION))
    DURATION_DIFF_FMT=$(format_duration "$DURATION_DIFF")
    echo "⚠️  Job 2 took $DURATION_DIFF_FMT longer than Job 1"
elif [[ $JOB2_DURATION -lt $JOB1_DURATION ]]; then
    DURATION_DIFF=$((JOB1_DURATION - JOB2_DURATION))
    DURATION_DIFF_FMT=$(format_duration "$DURATION_DIFF")
    echo "✅ Job 2 was $DURATION_DIFF_FMT faster than Job 1"
else
    echo "ℹ️  Both jobs took the same amount of time"
fi

# Runner comparison
if [[ "$JOB1_RUNNER" != "$JOB2_RUNNER" ]]; then
    echo "⚠️  Different runners: Job 1 used '$JOB1_RUNNER', Job 2 used '$JOB2_RUNNER'"
else
    echo "✅ Same runner used for both jobs"
fi

# Status comparison
if [[ "$JOB1_STATUS" != "$JOB2_STATUS" ]]; then
    echo "⚠️  Status changed: $JOB1_STATUS → $JOB2_STATUS"
fi

echo ""
echo "────────────────────────────────────────────────────────────────"
echo ""

# Log comparison
echo "## Log Differences"
echo ""

# Check if logs are identical
if diff -q "$JOB1_LOG" "$JOB2_LOG" &> /dev/null; then
    echo "✅ Logs are identical"
else
    echo "Differences found in logs:"
    echo ""

    # Show unified diff
    diff -u "$JOB1_LOG" "$JOB2_LOG" > "$TEMP_DIR/diff.txt" || true

    # Extract only added lines (new errors)
    NEW_ERRORS=$(grep "^+" "$TEMP_DIR/diff.txt" | grep -v "^+++" | grep -i -E "(error|failed|exception|fatal)" || true)

    if [[ -n "$NEW_ERRORS" ]]; then
        echo "🔴 New errors in Job 2:"
        echo ""
        echo "$NEW_ERRORS" | head -20
        echo ""
    fi

    # Extract removed lines (fixed errors)
    FIXED_ERRORS=$(grep "^-" "$TEMP_DIR/diff.txt" | grep -v "^---" | grep -i -E "(error|failed|exception|fatal)" || true)

    if [[ -n "$FIXED_ERRORS" ]]; then
        echo "🟢 Errors no longer present in Job 2:"
        echo ""
        echo "$FIXED_ERRORS" | head -20
        echo ""
    fi

    # Count total differences
    LINES_ADDED=$(grep -c "^+" "$TEMP_DIR/diff.txt" || echo "0")
    LINES_REMOVED=$(grep -c "^-" "$TEMP_DIR/diff.txt" || echo "0")

    echo "Summary: $LINES_ADDED lines added, $LINES_REMOVED lines removed"
    echo ""

    # Offer full diff
    echo "Run the following for full diff:"
    echo "  diff -u <(glab ci trace $JOB_ID_1 -R $REPO) <(glab ci trace $JOB_ID_2 -R $REPO)"
fi

echo ""
echo "────────────────────────────────────────────────────────────────"
echo ""

# Environment comparison
if $HAS_JQ; then
    echo "## Environment Comparison"
    echo ""

    # Compare commit SHAs
    JOB1_SHA=$(jq -r '.commit.id' < "$JOB1_JSON")
    JOB2_SHA=$(jq -r '.commit.id' < "$JOB2_JSON")

    if [[ "$JOB1_SHA" != "$JOB2_SHA" ]]; then
        echo "⚠️  Different commits:"
        echo "  Job 1: $JOB1_SHA"
        echo "  Job 2: $JOB2_SHA"
    else
        echo "✅ Same commit SHA"
    fi

    # Compare branches
    JOB1_REF=$(jq -r '.ref' < "$JOB1_JSON")
    JOB2_REF=$(jq -r '.ref' < "$JOB2_JSON")

    if [[ "$JOB1_REF" != "$JOB2_REF" ]]; then
        echo "⚠️  Different branches: $JOB1_REF vs $JOB2_REF"
    fi

    echo ""
fi

echo "────────────────────────────────────────────────────────────────"
echo ""

# JSON output if requested
if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    # Extract new and fixed errors for JSON
    NEW_ERRORS_JSON=$(grep "^+" "$TEMP_DIR/diff.txt" 2>/dev/null | grep -v "^+++" | grep -i -E "(error|failed|exception|fatal)" | head -20 | jq -R -s -c 'split("\n")[:-1]' || echo '[]')
    FIXED_ERRORS_JSON=$(grep "^-" "$TEMP_DIR/diff.txt" 2>/dev/null | grep -v "^---" | grep -i -E "(error|failed|exception|fatal)" | head -20 | jq -R -s -c 'split("\n")[:-1]' || echo '[]')

    # Count differences
    if diff -q "$JOB1_LOG" "$JOB2_LOG" &> /dev/null; then
        LOGS_IDENTICAL=true
        LINES_ADDED=0
        LINES_REMOVED=0
    else
        LOGS_IDENTICAL=false
        LINES_ADDED=$(grep -c "^+" "$TEMP_DIR/diff.txt" 2>/dev/null || echo "0")
        LINES_REMOVED=$(grep -c "^-" "$TEMP_DIR/diff.txt" 2>/dev/null || echo "0")
    fi

    # Determine recommendation
    if [[ "$JOB1_STATUS" == "success" && "$JOB2_STATUS" == "failed" ]]; then
        RECOMMENDATION="Job 1 succeeded but Job 2 failed - investigate new errors and environment changes"
    elif [[ "$JOB1_STATUS" == "failed" && "$JOB2_STATUS" == "success" ]]; then
        RECOMMENDATION="Job 2 succeeded while Job 1 failed - issue appears resolved"
    elif [[ "$JOB1_STATUS" == "failed" && "$JOB2_STATUS" == "failed" ]]; then
        RECOMMENDATION="Both jobs failed - check if same error persists (flaky vs deterministic)"
    else
        RECOMMENDATION="Both jobs succeeded - no issues detected"
    fi

    jq -n \
        --arg repo "$REPO" \
        --argjson job1_id "$JOB_ID_1" \
        --argjson job2_id "$JOB_ID_2" \
        --arg job1_name "$JOB1_NAME" \
        --arg job2_name "$JOB2_NAME" \
        --arg job1_status "$JOB1_STATUS" \
        --arg job2_status "$JOB2_STATUS" \
        --argjson job1_duration "$JOB1_DURATION" \
        --argjson job2_duration "$JOB2_DURATION" \
        --arg job1_runner "$JOB1_RUNNER" \
        --arg job2_runner "$JOB2_RUNNER" \
        --arg job1_created "$JOB1_CREATED" \
        --arg job2_created "$JOB2_CREATED" \
        --arg job1_sha "$JOB1_SHA" \
        --arg job2_sha "$JOB2_SHA" \
        --arg job1_ref "$JOB1_REF" \
        --arg job2_ref "$JOB2_REF" \
        --argjson logs_identical "$LOGS_IDENTICAL" \
        --argjson lines_added "$LINES_ADDED" \
        --argjson lines_removed "$LINES_REMOVED" \
        --argjson new_errors "$NEW_ERRORS_JSON" \
        --argjson fixed_errors "$FIXED_ERRORS_JSON" \
        --arg recommendation "$RECOMMENDATION" \
        '{
            repository: $repo,
            job1: {
                id: $job1_id,
                name: $job1_name,
                status: $job1_status,
                duration: $job1_duration,
                runner: $job1_runner,
                created_at: $job1_created,
                commit_sha: $job1_sha,
                ref: $job1_ref
            },
            job2: {
                id: $job2_id,
                name: $job2_name,
                status: $job2_status,
                duration: $job2_duration,
                runner: $job2_runner,
                created_at: $job2_created,
                commit_sha: $job2_sha,
                ref: $job2_ref
            },
            comparison: {
                duration_difference: ($job2_duration - $job1_duration),
                same_runner: ($job1_runner == $job2_runner),
                same_commit: ($job1_sha == $job2_sha),
                same_ref: ($job1_ref == $job2_ref),
                status_changed: ($job1_status != $job2_status)
            },
            log_analysis: {
                logs_identical: $logs_identical,
                lines_added: $lines_added,
                lines_removed: $lines_removed,
                new_errors: $new_errors,
                fixed_errors: $fixed_errors
            },
            recommendation: $recommendation
        }'

    exit 0
fi

# Recommendations
cat << EOF
## Recommendations

EOF

if [[ "$JOB1_STATUS" == "success" && "$JOB2_STATUS" == "failed" ]]; then
    echo "Job 1 succeeded but Job 2 failed. Consider:"
    echo ""
    echo "1. Check commit differences between the two jobs"
    echo "2. Review new errors introduced in Job 2 logs"
    echo "3. Verify environment variables and secrets"
    echo "4. Check if runner environment changed"
    echo "5. Look for dependency version changes"
elif [[ "$JOB1_STATUS" == "failed" && "$JOB2_STATUS" == "success" ]]; then
    echo "✅ Job 2 succeeded while Job 1 failed - issue appears to be resolved!"
elif [[ "$JOB1_STATUS" == "failed" && "$JOB2_STATUS" == "failed" ]]; then
    echo "Both jobs failed. Consider:"
    echo ""
    echo "1. Check if the same error persists across both runs (flaky vs deterministic)"
    echo "2. Review error patterns to identify root cause"
    echo "3. If errors are identical, issue is likely reproducible"
else
    echo "Both jobs succeeded - no obvious issues to investigate."
fi

echo ""
