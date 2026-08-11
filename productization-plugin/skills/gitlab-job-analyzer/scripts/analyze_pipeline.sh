#!/usr/bin/env bash
# Comprehensive GitLab pipeline analysis - fetch everything in ONE call
#
# Usage:
#   analyze_pipeline.sh <owner/repo> <pipeline-id> [--human] [--include-successful] [--log-lines N]
#
# Output: JSON by default with ALL analysis data
#
# IMPORTANT: This script expects a pipeline ID (numeric ID), NOT a pipeline IID (internal ID).
# When running `glab ci list`, you'll see output like: #2315214741 (#2433)
#   - The first number (2315214741) is the pipeline ID - USE THIS
#   - The number in parentheses (2433) is the IID - DO NOT use this
#
# Examples:
#   # Get full JSON output
#   ./analyze_pipeline.sh owner/repo 12345
#
#   # Parse specific fields
#   ./analyze_pipeline.sh owner/repo 12345 | jq '.job_statistics'
#   ./analyze_pipeline.sh owner/repo 12345 | jq '.failed_jobs[].name'
#
#   # Human-readable output
#   ./analyze_pipeline.sh owner/repo 12345 --human

set -euo pipefail

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] <owner/repo> <pipeline-id>

Comprehensive pipeline analysis - gets all data in a single call.

ARGUMENTS:
    owner/repo             GitLab repository (e.g., gitlab-org/gitlab)
    pipeline-id            Pipeline ID (numeric ID, NOT IID) to analyze

IMPORTANT - Pipeline ID vs IID:
    When you run 'glab ci list', you see: #2315214741 (#2433)
      - The first number (2315214741) is the pipeline ID → USE THIS
      - The number in parentheses (2433) is the IID → DO NOT use this

    This script requires the pipeline ID (the larger number).

OPTIONS:
    --human                Output human-readable format instead of JSON
    --include-successful   Include successful job logs in analysis (increases output size)
    --log-lines N          Number of log lines to fetch per failed job (default: 100)
    -h, --help             Show this help message

OUTPUT (JSON mode - default):
    Complete JSON object with:
    - Pipeline metadata (status, ref, sha, duration, user)
    - Job statistics (total, passed, failed, skipped, running)
    - Stage summary (jobs per stage, failures, duration)
    - Failed jobs with error analysis
    - Common error patterns across all failures
    - Dependency information

OUTPUT (Human mode - with --human):
    Formatted report with same information

EXAMPLES:
    # Get all pipeline data as JSON
    $(basename "$0") owner/repo 12345

    # Parse specific fields with jq
    $(basename "$0") owner/repo 12345 | jq '.job_statistics'
    $(basename "$0") owner/repo 12345 | jq '.failed_jobs[] | {id, name, stage, failure_reason}'
    $(basename "$0") owner/repo 12345 | jq '.common_error_patterns'

    # Human-readable output
    $(basename "$0") owner/repo 12345 --human

    # Include successful job analysis
    $(basename "$0") owner/repo 12345 --include-successful

EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse flags
HUMAN_OUTPUT=false
INCLUDE_SUCCESSFUL=false
LOG_LINES=100

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        --human)
            HUMAN_OUTPUT=true
            shift
            ;;
        --include-successful)
            INCLUDE_SUCCESSFUL=true
            shift
            ;;
        --log-lines)
            LOG_LINES="$2"
            shift 2
            ;;
        *)
            break
            ;;
    esac
done

if [ $# -lt 2 ]; then
    echo '{"error": "Missing required arguments", "usage": "analyze_pipeline.sh <owner/repo> <pipeline-id> [--human] [--include-successful]"}' >&2
    exit 1
fi

REPO="$1"
PIPELINE_ID="$2"
ENCODED_REPO="${REPO//\//%2F}"

# Check dependencies
if ! command -v glab &> /dev/null; then
    echo '{"error": "glab command not found"}' >&2
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo '{"error": "jq command not found - required for JSON processing"}' >&2
    exit 1
fi

# Temp directory
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Progress to stderr if JSON output
if [ "$HUMAN_OUTPUT" = false ]; then
    exec 3>&1  # Save stdout
    exec 1>&2  # Redirect stdout to stderr for progress messages
fi

echo "=== Pipeline Analysis for $REPO #$PIPELINE_ID ===" >&2
echo "" >&2

# Step 1: Fetch pipeline metadata
echo "Step 1/5: Fetching pipeline metadata" >&2
if ! glab api --method GET "projects/$ENCODED_REPO/pipelines/$PIPELINE_ID" > "$TEMP_DIR/pipeline.json" 2>"$TEMP_DIR/pipeline_error.log"; then
    ERROR_MSG=$(cat "$TEMP_DIR/pipeline_error.log" || echo "Unknown error")
    if [ "$HUMAN_OUTPUT" = false ]; then
        exec 1>&3  # Restore stdout
    fi
    echo "{\"error\": \"Failed to fetch pipeline #$PIPELINE_ID\", \"details\": \"$ERROR_MSG\", \"hint\": \"Verify the pipeline ID is correct. Note: use pipeline ID (not IID). Run 'glab ci list -R $REPO' to see available pipelines.\"}" >&2
    exit 1
fi

PIPELINE_DATA=$(cat "$TEMP_DIR/pipeline.json")

# Validate pipeline data
if ! echo "$PIPELINE_DATA" | jq -e '.id' > /dev/null 2>&1; then
    if [ "$HUMAN_OUTPUT" = false ]; then
        exec 1>&3  # Restore stdout
    fi
    echo "{\"error\": \"Invalid pipeline data received\", \"hint\": \"Pipeline #$PIPELINE_ID may not exist in repository $REPO\"}" >&2
    exit 1
fi

# Step 2: Fetch all jobs
echo "Step 2/5: Fetching all jobs in pipeline" >&2
glab api --method GET "projects/$ENCODED_REPO/pipelines/$PIPELINE_ID/jobs" > "$TEMP_DIR/jobs.json"
JOBS_DATA=$(cat "$TEMP_DIR/jobs.json")

# Step 3: Calculate job statistics
echo "Step 3/5: Computing job statistics" >&2
TOTAL_JOBS=$(echo "$JOBS_DATA" | jq 'length')

# Handle pipelines with 0 jobs
if [ "$TOTAL_JOBS" -eq 0 ]; then
    echo "  ⚠️  Pipeline has 0 jobs (may have failed during creation or been canceled before jobs started)" >&2
    echo "" >&2

    # Build minimal response
    EMPTY_RESULT=$(jq -n \
        --arg repo "$REPO" \
        --argjson pipeline_id "$PIPELINE_ID" \
        --argjson pipeline "$PIPELINE_DATA" \
        '{
            repository: $repo,
            pipeline_id: $pipeline_id,
            pipeline_metadata: {
                status: $pipeline.status,
                ref: $pipeline.ref,
                sha: $pipeline.sha,
                duration: $pipeline.duration,
                created_at: $pipeline.created_at,
                updated_at: $pipeline.updated_at,
                user: ($pipeline.user.username // "unknown")
            },
            total_jobs: 0,
            message: "Pipeline has no jobs. This typically occurs when a pipeline fails during creation or is canceled before any jobs start.",
            job_statistics: {
                total: 0,
                passed: 0,
                failed: 0,
                skipped: 0,
                running: 0
            },
            stages: [],
            analyzed_jobs: [],
            failure_reasons: [],
            blocked_jobs: [],
            common_error_patterns: []
        }')

    if [ "$HUMAN_OUTPUT" = false ]; then
        exec 1>&3  # Restore stdout
        echo "$EMPTY_RESULT"
    else
        exec 1>&3  # Restore stdout
        echo "╔════════════════════════════════════════════════════════════════╗"
        echo "║              Pipeline Analysis Results                         ║"
        echo "╚════════════════════════════════════════════════════════════════╝"
        echo ""
        echo "Repository: $REPO"
        echo "Pipeline: #$PIPELINE_ID"
        echo ""
        echo "$EMPTY_RESULT" | jq -r '.pipeline_metadata | "  Status: \(.status)\n  Ref: \(.ref)\n  SHA: \(.sha[0:8])\n  Duration: \(.duration)s\n  Created: \(.created_at)\n  User: @\(.user)"'
        echo ""
        echo "⚠️  Pipeline has no jobs"
        echo ""
        echo "This typically occurs when:"
        echo "  - Pipeline failed during creation (YAML syntax error, etc.)"
        echo "  - Pipeline was canceled before any jobs could start"
        echo "  - Pipeline is still being created (very rare)"
        echo ""
        echo "Tip: Check pipeline status in GitLab UI or run 'glab ci view $PIPELINE_ID -R $REPO'"
    fi
    exit 0
fi

PASSED_JOBS=$(echo "$JOBS_DATA" | jq '[.[] | select(.status == "success")] | length')
FAILED_JOBS=$(echo "$JOBS_DATA" | jq '[.[] | select(.status == "failed")] | length')
SKIPPED_JOBS=$(echo "$JOBS_DATA" | jq '[.[] | select(.status == "skipped" or .status == "canceled")] | length')
RUNNING_JOBS=$(echo "$JOBS_DATA" | jq '[.[] | select(.status == "running" or .status == "pending")] | length')

echo "  Total: $TOTAL_JOBS jobs, Failed: $FAILED_JOBS, Passed: $PASSED_JOBS" >&2
echo "" >&2

# Step 4: Analyze failed jobs (and optionally successful ones)
echo "Step 4/5: Analyzing jobs and extracting errors" >&2

if [ "$INCLUDE_SUCCESSFUL" = true ]; then
    JOB_IDS=$(echo "$JOBS_DATA" | jq -r '.[].id')
    JOB_FILTER="all"
else
    JOB_IDS=$(echo "$JOBS_DATA" | jq -r '.[] | select(.status == "failed") | .id')
    JOB_FILTER="failed"
fi

JOB_COUNT=$(echo "$JOB_IDS" | grep -c "^" || echo "0")
JOBS_WITH_ANALYSIS="[]"
JOB_NUM=1

while read -r JOB_ID; do
    [[ -z "$JOB_ID" ]] && continue

    echo "  [$JOB_NUM/$JOB_COUNT] Analyzing job #$JOB_ID" >&2

    # Get job metadata
    JOB_DATA=$(echo "$JOBS_DATA" | jq --arg id "$JOB_ID" '.[] | select(.id == ($id | tonumber))')

    # Skip if job data is empty (shouldn't happen but be defensive)
    if [ -z "$JOB_DATA" ] || [ "$JOB_DATA" = "null" ]; then
        echo "    ⚠️  Warning: Could not find job data for #$JOB_ID, skipping" >&2
        JOB_NUM=$((JOB_NUM + 1))
        continue
    fi

    # Fetch log (last N lines to avoid bloat)
    LOG_FILE="$TEMP_DIR/job_${JOB_ID}.log"
    glab ci trace "$JOB_ID" -R "$REPO" 2>/dev/null | tail -n "$LOG_LINES" > "$LOG_FILE" || echo "Could not fetch logs" > "$LOG_FILE"

    # Extract errors using extract_errors.sh --json
    # Use a fallback if the script fails
    if ERROR_ANALYSIS=$("$SCRIPT_DIR/extract_errors.sh" "$LOG_FILE" --json 2>/dev/null); then
        # Validate it's valid JSON
        if ! echo "$ERROR_ANALYSIS" | jq empty 2>/dev/null; then
            ERROR_ANALYSIS='{"total_errors": 0, "categories": {}}'
        fi
    else
        ERROR_ANALYSIS='{"total_errors": 0, "categories": {}}'
    fi

    # Get last 20 error lines from log for context
    ERROR_LINES=$(grep -i -E "(error|failed|exception|fatal)" "$LOG_FILE" 2>/dev/null | tail -20 || echo "")
    ERROR_LINES_JSON=$(echo "$ERROR_LINES" | jq -R -s -c 'split("\n")[:-1]' 2>/dev/null || echo '[]')

    # Validate error_lines_json
    if ! echo "$ERROR_LINES_JSON" | jq empty 2>/dev/null; then
        ERROR_LINES_JSON='[]'
    fi

    # Combine job metadata + error analysis + sample error lines
    # Use safer jq invocation with validation
    if JOB_WITH_ERRORS=$(echo "$JOB_DATA" | jq \
        --argjson errors "$ERROR_ANALYSIS" \
        --argjson error_lines "$ERROR_LINES_JSON" \
        '. + {
            error_analysis: $errors,
            sample_error_lines: $error_lines
        }' 2>/dev/null); then
        # Success - append to array
        JOBS_WITH_ANALYSIS=$(echo "$JOBS_WITH_ANALYSIS" | jq --argjson job "$JOB_WITH_ERRORS" '. + [$job]')
    else
        # Failed to combine - add job without error analysis
        echo "    ⚠️  Warning: Could not analyze errors for job #$JOB_ID, including without error analysis" >&2
        JOB_WITH_ERRORS=$(echo "$JOB_DATA" | jq '. + {
            error_analysis: {"total_errors": 0, "categories": {}, "error": "Failed to analyze errors"},
            sample_error_lines: []
        }')
        JOBS_WITH_ANALYSIS=$(echo "$JOBS_WITH_ANALYSIS" | jq --argjson job "$JOB_WITH_ERRORS" '. + [$job]')
    fi

    JOB_NUM=$((JOB_NUM + 1))
done <<< "$JOB_IDS"

echo "" >&2

# Step 5: Aggregate statistics and patterns
echo "Step 5/5: Aggregating patterns and dependencies" >&2

# Stage-level analysis
STAGE_SUMMARY=$(echo "$JOBS_DATA" | jq 'group_by(.stage) | map({
    stage: .[0].stage,
    total_jobs: length,
    failed: ([.[] | select(.status == "failed")] | length),
    passed: ([.[] | select(.status == "success")] | length),
    running: ([.[] | select(.status == "running" or .status == "pending")] | length),
    skipped: ([.[] | select(.status == "skipped" or .status == "canceled")] | length),
    max_duration: ([.[].duration // 0] | max),
    total_duration: ([.[].duration // 0] | add)
})')

# Aggregate error patterns across all analyzed jobs
COMMON_ERROR_PATTERNS=$(echo "$JOBS_WITH_ANALYSIS" | jq '[
    .[].error_analysis.categories | to_entries[] |
    select(.value > 0) |
    {category: .key, count: .value}
] | group_by(.category) | map({
    category: .[0].category,
    total_occurrences: ([.[].count] | add),
    jobs_affected: length
}) | sort_by(-.total_occurrences)')

# Get failure reasons distribution
FAILURE_REASONS=$(echo "$JOBS_DATA" | jq -r '
    [.[] | select(.status == "failed") | .failure_reason // "unknown"] |
    group_by(.) | map({
        reason: .[0],
        count: length
    }) | sort_by(-.count)
')

# Identify blocked jobs
BLOCKED_JOBS=$(echo "$JOBS_DATA" | jq '[
    .[] | select(.status == "pending" or .status == "created") |
    {id, name, stage, status}
]')

# Build complete JSON output
FULL_DATA=$(jq -n \
    --arg repo "$REPO" \
    --argjson pipeline_id "$PIPELINE_ID" \
    --argjson pipeline "$PIPELINE_DATA" \
    --argjson total "$TOTAL_JOBS" \
    --argjson passed "$PASSED_JOBS" \
    --argjson failed "$FAILED_JOBS" \
    --argjson skipped "$SKIPPED_JOBS" \
    --argjson running "$RUNNING_JOBS" \
    --argjson analyzed_jobs "$JOBS_WITH_ANALYSIS" \
    --argjson stages "$STAGE_SUMMARY" \
    --argjson patterns "$COMMON_ERROR_PATTERNS" \
    --argjson failure_reasons "$FAILURE_REASONS" \
    --argjson blocked "$BLOCKED_JOBS" \
    '{
        repository: $repo,
        pipeline_id: $pipeline_id,
        pipeline_metadata: {
            status: $pipeline.status,
            ref: $pipeline.ref,
            sha: $pipeline.sha,
            duration: $pipeline.duration,
            created_at: $pipeline.created_at,
            updated_at: $pipeline.updated_at,
            user: ($pipeline.user.username // "unknown")
        },
        job_statistics: {
            total: $total,
            passed: $passed,
            failed: $failed,
            skipped: $skipped,
            running: $running
        },
        stages: $stages,
        analyzed_jobs: $analyzed_jobs,
        failure_reasons: $failure_reasons,
        blocked_jobs: $blocked,
        common_error_patterns: $patterns
    }')

echo "Analysis complete!" >&2
echo "" >&2

# Output results
if [ "$HUMAN_OUTPUT" = false ]; then
    exec 1>&3  # Restore stdout

    # Output full data as JSON
    echo "$FULL_DATA"
else
    # Human-readable output
    exec 1>&3  # Restore stdout

    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║              Pipeline Analysis Results                         ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Repository: $REPO"
    echo "Pipeline: #$PIPELINE_ID"
    echo ""

    echo "Pipeline Metadata:"
    echo "$FULL_DATA" | jq -r '.pipeline_metadata | "  Status: \(.status)\n  Ref: \(.ref)\n  SHA: \(.sha[0:8])\n  Duration: \(.duration)s\n  Created: \(.created_at)\n  User: @\(.user)"'
    echo ""

    echo "Job Statistics:"
    echo "$FULL_DATA" | jq -r '.job_statistics | "  Total: \(.total)\n  Passed: \(.passed) (\((.passed / .total * 100) | floor)%)\n  Failed: \(.failed) (\((.failed / .total * 100) | floor)%)\n  Skipped: \(.skipped)\n  Running: \(.running)"'
    echo ""

    echo "────────────────────────────────────────────────────────────────"
    echo ""

    if [ "$FAILED_JOBS" -gt 0 ]; then
        echo "Failed Jobs:"
        echo "$FULL_DATA" | jq -r '.analyzed_jobs[] | select(.status == "failed") | "  ❌ #\(.id): \(.name) (\(.stage))\n     Reason: \(.failure_reason // "unknown")\n     Errors: \(.error_analysis.total_errors)"'
        echo ""

        echo "────────────────────────────────────────────────────────────────"
        echo ""

        echo "Failure Reasons:"
        echo "$FULL_DATA" | jq -r '.failure_reasons[] | "  - \(.reason): \(.count) job(s)"'
        echo ""

        echo "────────────────────────────────────────────────────────────────"
        echo ""

        echo "Common Error Patterns:"
        if [ "$(echo "$FULL_DATA" | jq '.common_error_patterns | length')" -gt 0 ]; then
            echo "$FULL_DATA" | jq -r '.common_error_patterns[] | "  - \(.category): \(.total_occurrences) occurrences across \(.jobs_affected) job(s)"'
        else
            echo "  No common patterns detected"
        fi
        echo ""
    else
        echo "✅ No failed jobs - pipeline is healthy!"
        echo ""
    fi

    echo "────────────────────────────────────────────────────────────────"
    echo ""

    echo "Stage Summary:"
    echo "$FULL_DATA" | jq -r '.stages[] | "  Stage: \(.stage)\n    Jobs: \(.total_jobs) (failed: \(.failed), passed: \(.passed))\n    Max Duration: \(.max_duration)s\n"'

    if [ "$(echo "$FULL_DATA" | jq '.blocked_jobs | length')" -gt 0 ]; then
        echo "────────────────────────────────────────────────────────────────"
        echo ""
        echo "Blocked Jobs:"
        echo "$FULL_DATA" | jq -r '.blocked_jobs[] | "  ⏳ #\(.id): \(.name) (\(.stage))"'
        echo ""
    fi

    echo "────────────────────────────────────────────────────────────────"
    echo ""
    echo "💡 For detailed JSON output, run without --human flag"
    echo "💡 Parse specific fields: $(basename "$0") $REPO $PIPELINE_ID | jq '.job_statistics'"
fi
