#!/usr/bin/env bash
# Analyze GitLab CI/CD jobs across ALL pipelines within a time range
#
# Usage:
#   analyze_recent_jobs.sh <owner/repo> [OPTIONS]
#
# This addresses the most common use case: "What jobs ran/failed in the last 24 hours?"
# Unlike analyze_pipeline.sh which focuses on a single pipeline, this script analyzes
# ALL jobs across multiple pipelines within a time range.
#
# Examples:
#   # Last 24 hours
#   ./analyze_recent_jobs.sh owner/repo --hours 24
#
#   # Last 7 days
#   ./analyze_recent_jobs.sh owner/repo --days 7
#
#   # With runner tag filter
#   ./analyze_recent_jobs.sh owner/repo --hours 24 --runner-tag "aipcc-"
#
#   # JSON output (default)
#   ./analyze_recent_jobs.sh owner/repo --hours 24 --json
#
#   # Human-readable output
#   ./analyze_recent_jobs.sh owner/repo --hours 24 --human

set -euo pipefail

# Set state directory for this skill
SKILL_STATE_DIR="${GITLAB_JOB_ANALYZER_STATE_DIR:-$HOME/.gitlab-job-analyzer/state}"

# Source shared state library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../tools/memory/scripts/state.sh"

show_usage() {
    cat << 'EOF'
Usage: analyze_recent_jobs.sh <owner/repo> [OPTIONS]

Analyze GitLab CI/CD jobs across ALL pipelines within a time range.

ARGUMENTS:
    owner/repo             GitLab repository (e.g., gitlab-org/gitlab)

OPTIONS:
    --hours N              Analyze jobs from last N hours (default: 24)
    --days N               Analyze jobs from last N days
    --since DATE           Analyze jobs since specific date (ISO-8601 format)
    --runner-tag PREFIX    Filter to jobs on runners with tag prefix (e.g., "aipcc-")
    --json                 Output JSON format (default)
    --human                Output human-readable format
    -h, --help             Show this help message

TIME RANGE:
    One of --hours, --days, or --since must be specified.
    If none specified, defaults to --hours 24.

OUTPUT (JSON mode - default):
    {
      "repository": "owner/repo",
      "time_range": {...},
      "total_jobs": 234,
      "job_statistics": {
        "success": 179,
        "failed": 22,
        "skipped": 32,
        "canceled": 1
      },
      "by_stage": [...],
      "pipelines": {...},
      "failed_jobs": [...],
      "runner_filter": {...}  // if --runner-tag provided
    }

EXAMPLES:
    # Last 24 hours
    analyze_recent_jobs.sh owner/repo --hours 24

    # Last 7 days
    analyze_recent_jobs.sh owner/repo --days 7

    # Specific date range
    analyze_recent_jobs.sh owner/repo --since "2026-02-09T00:00:00Z"

    # Filter by runner tags
    analyze_recent_jobs.sh owner/repo --hours 24 --runner-tag "aipcc-"

    # Human-readable output
    analyze_recent_jobs.sh owner/repo --hours 24 --human

    # Parse specific fields
    analyze_recent_jobs.sh owner/repo --hours 24 | jq '.job_statistics'
    analyze_recent_jobs.sh owner/repo --hours 24 | jq '.failed_jobs[] | {id, name, stage}'

EOF
}

# Parse arguments
REPO=""
HOURS=""
DAYS=""
SINCE=""
RUNNER_TAG=""
OUTPUT_MODE="json"

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        --hours)
            HOURS="$2"
            shift 2
            ;;
        --days)
            DAYS="$2"
            shift 2
            ;;
        --since)
            SINCE="$2"
            shift 2
            ;;
        --runner-tag)
            RUNNER_TAG="$2"
            shift 2
            ;;
        --json)
            OUTPUT_MODE="json"
            shift
            ;;
        --human)
            OUTPUT_MODE="human"
            shift
            ;;
        *)
            if [ -z "$REPO" ]; then
                REPO="$1"
            else
                echo '{"error": "Unknown argument: '"$1"'"}' >&2
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate arguments
if [ -z "$REPO" ]; then
    echo '{"error": "Repository argument required"}' >&2
    show_usage >&2
    exit 1
fi

# Check dependencies
if ! command -v glab &> /dev/null; then
    echo '{"error": "glab command not found. Install with: ../../../tools/glab/install.sh"}' >&2
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo '{"error": "jq command not found. Install with: ../../../tools/jq/install.sh"}' >&2
    exit 1
fi

# Calculate time range
if [ -n "$SINCE" ]; then
    # User provided specific date
    CUTOFF="$SINCE"
    TIME_DESCRIPTION="since $SINCE"
elif [ -n "$DAYS" ]; then
    # Calculate from days
    if ! CUTOFF=$(date -d "$DAYS days ago" --iso-8601=seconds 2>/dev/null); then
        echo '{"error": "Failed to calculate date from --days. Ensure date command supports -d flag."}' >&2
        exit 1
    fi
    TIME_DESCRIPTION="last $DAYS days"
elif [ -n "$HOURS" ]; then
    # Calculate from hours
    if ! CUTOFF=$(date -d "$HOURS hours ago" --iso-8601=seconds 2>/dev/null); then
        echo '{"error": "Failed to calculate date from --hours. Ensure date command supports -d flag."}' >&2
        exit 1
    fi
    TIME_DESCRIPTION="last $HOURS hours"
else
    # Default to 24 hours
    HOURS=24
    if ! CUTOFF=$(date -d "24 hours ago" --iso-8601=seconds 2>/dev/null); then
        echo '{"error": "Failed to calculate date. Ensure date command supports -d flag."}' >&2
        exit 1
    fi
    TIME_DESCRIPTION="last 24 hours (default)"
fi

END_TIME=$(date --iso-8601=seconds)
ENCODED_REPO="${REPO//\//%2F}"

# Progress messages to stderr
echo "=== Analyzing Jobs for $REPO ===" >&2
echo "Time range: $TIME_DESCRIPTION" >&2
echo "Cutoff: $CUTOFF" >&2
echo "" >&2

# Step 1: Fetch recent pipelines, then jobs from those pipelines (EFFICIENT)
echo "Step 1/4: Fetching recent pipelines (updated after $CUTOFF)..." >&2
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Fetch pipelines updated after cutoff
glab api --method GET "projects/$ENCODED_REPO/pipelines?updated_after=$CUTOFF&per_page=100" --paginate > "$TEMP_DIR/pipelines.json"

PIPELINE_COUNT=$(jq 'length' "$TEMP_DIR/pipelines.json")
echo "  Found $PIPELINE_COUNT pipelines in time range" >&2

if [ "$PIPELINE_COUNT" -eq 0 ]; then
    echo "  No pipelines found in time range" >&2
    JOBS_IN_RANGE="[]"
    TOTAL_JOBS=0
else
    # Step 2: Fetch jobs from each pipeline
    echo "Step 2/4: Fetching jobs from $PIPELINE_COUNT pipelines..." >&2

    # Initialize empty jobs array
    echo "[]" > "$TEMP_DIR/all_jobs.json"

    # Counter for progress
    PIPELINE_NUM=0

    # Fetch jobs for each pipeline (using process substitution to avoid subshell)
    while read -r PIPELINE_ID; do
        PIPELINE_NUM=$((PIPELINE_NUM + 1))
        echo "  Fetching jobs from pipeline $PIPELINE_ID ($PIPELINE_NUM/$PIPELINE_COUNT)..." >&2

        # Fetch jobs for this pipeline
        glab api --method GET "projects/$ENCODED_REPO/pipelines/$PIPELINE_ID/jobs?per_page=100" --paginate > "$TEMP_DIR/pipeline_${PIPELINE_ID}_jobs.json" 2>/dev/null || echo "[]" > "$TEMP_DIR/pipeline_${PIPELINE_ID}_jobs.json"
    done < <(jq -r '.[].id' "$TEMP_DIR/pipelines.json")

    # Combine all jobs into single array
    jq -s 'add' "$TEMP_DIR"/pipeline_*_jobs.json > "$TEMP_DIR/all_jobs.json"

    # Filter by created_at >= cutoff (some jobs may be older if pipeline spans the cutoff)
    JOBS_IN_RANGE=$(jq --arg cutoff "$CUTOFF" '[.[] | select(.created_at >= $cutoff)]' "$TEMP_DIR/all_jobs.json")

    TOTAL_JOBS=$(echo "$JOBS_IN_RANGE" | jq 'length')
    echo "  Found $TOTAL_JOBS jobs in time range (across $PIPELINE_COUNT pipelines)" >&2
fi

echo "" >&2

if [ "$TOTAL_JOBS" -eq 0 ]; then
    # No jobs found
    if [ "$OUTPUT_MODE" = "json" ]; then
        jq -n \
            --arg repo "$REPO" \
            --arg start "$CUTOFF" \
            --arg end "$END_TIME" \
            --arg desc "$TIME_DESCRIPTION" \
            '{
                repository: $repo,
                time_range: {
                    start: $start,
                    end: $end,
                    description: $desc
                },
                total_jobs: 0,
                job_statistics: {
                    success: 0,
                    failed: 0,
                    skipped: 0,
                    canceled: 0,
                    running: 0,
                    pending: 0
                },
                message: "No jobs found in specified time range"
            }'
    else
        echo "No jobs found in time range: $TIME_DESCRIPTION"
    fi
    exit 0
fi

# Step 3: Apply runner tag filter if specified
if [ -n "$RUNNER_TAG" ]; then
    echo "Step 3/4: Filtering by runner tag prefix: $RUNNER_TAG" >&2

    TOTAL_BEFORE_FILTER=$TOTAL_JOBS
    FILTERED_JOBS=$(echo "$JOBS_IN_RANGE" | jq --arg tag "$RUNNER_TAG" '[.[] | select(any(.tag_list[]?; startswith($tag)))]')
    JOBS_IN_RANGE="$FILTERED_JOBS"
    TOTAL_JOBS=$(echo "$JOBS_IN_RANGE" | jq 'length')

    echo "  Matched $TOTAL_JOBS jobs (filtered from $TOTAL_BEFORE_FILTER)" >&2
    echo "" >&2

    if [ "$TOTAL_JOBS" -eq 0 ]; then
        if [ "$OUTPUT_MODE" = "json" ]; then
            jq -n \
                --arg repo "$REPO" \
                --arg start "$CUTOFF" \
                --arg end "$END_TIME" \
                --arg desc "$TIME_DESCRIPTION" \
                --arg tag "$RUNNER_TAG" \
                --argjson total_before "$TOTAL_BEFORE_FILTER" \
                '{
                    repository: $repo,
                    time_range: {
                        start: $start,
                        end: $end,
                        description: $desc
                    },
                    total_jobs: 0,
                    runner_filter: {
                        pattern: $tag,
                        total_jobs_before_filter: $total_before,
                        matched_jobs: 0
                    },
                    message: "No jobs found matching runner tag filter"
                }'
        else
            echo "No jobs found matching runner tag: $RUNNER_TAG (out of $TOTAL_BEFORE_FILTER total jobs)"
        fi
        exit 0
    fi
else
    echo "Step 3/4: No runner filter applied" >&2
    echo "" >&2
fi

# Step 4: Calculate statistics and extract errors from failed jobs
echo "Step 4/4: Calculating statistics and analyzing failures..." >&2

# Job statistics by status
SUCCESS_COUNT=$(echo "$JOBS_IN_RANGE" | jq '[.[] | select(.status == "success")] | length')
FAILED_COUNT=$(echo "$JOBS_IN_RANGE" | jq '[.[] | select(.status == "failed")] | length')
SKIPPED_COUNT=$(echo "$JOBS_IN_RANGE" | jq '[.[] | select(.status == "skipped")] | length')
CANCELED_COUNT=$(echo "$JOBS_IN_RANGE" | jq '[.[] | select(.status == "canceled")] | length')
RUNNING_COUNT=$(echo "$JOBS_IN_RANGE" | jq '[.[] | select(.status == "running")] | length')
PENDING_COUNT=$(echo "$JOBS_IN_RANGE" | jq '[.[] | select(.status == "pending" or .status == "created")] | length')

# Stage analysis with failure counts
BY_STAGE=$(echo "$JOBS_IN_RANGE" | jq 'group_by(.stage) | map({
    stage: .[0].stage,
    total: length,
    failed: ([.[] | select(.status == "failed")] | length),
    success: ([.[] | select(.status == "success")] | length),
    success_rate: (if length > 0 then (([.[] | select(.status == "success")] | length) * 100 / length | floor) else 0 end)
}) | sort_by(-.failed)')

# Failed jobs with details and error extraction
echo "  Extracting errors from $FAILED_COUNT failed jobs..." >&2

FAILED_JOB_IDS=$(echo "$JOBS_IN_RANGE" | jq -r '[.[] | select(.status == "failed") | .id] | join(" ")')

# Extract basic failed job details
FAILED_JOBS_BASE=$(echo "$JOBS_IN_RANGE" | jq '[.[] | select(.status == "failed") | {
    id,
    name,
    stage,
    pipeline_id: .pipeline.id,
    failure_reason: (.failure_reason // "unknown"),
    runner: (.runner.description // "unknown"),
    runner_tags: .tag_list,
    created_at,
    web_url
}]')

# Enhanced failed jobs with sample errors
FAILED_JOBS="[]"

if [ "$FAILED_COUNT" -gt 0 ]; then
    # Limit error extraction to first 10 failed jobs to avoid timeout
    FAILED_JOB_IDS_LIMITED=$(echo "$FAILED_JOB_IDS" | tr ' ' '\n' | head -10 | tr '\n' ' ')

    for JOB_ID in $FAILED_JOB_IDS_LIMITED; do
        echo "    Analyzing job $JOB_ID..." >&2

        # Get last 100 lines of log
        LOG_SAMPLE=$(glab ci trace "$JOB_ID" -R "$REPO" 2>/dev/null | tail -100 || echo "")

        # Extract error lines (up to 10 lines)
        if [ -n "$LOG_SAMPLE" ]; then
            SAMPLE_ERRORS=$(echo "$LOG_SAMPLE" | grep -i "error\|failed\|fatal\|exception" | head -10 || echo "")
        else
            SAMPLE_ERRORS=""
        fi

        # Get base job info
        JOB_INFO=$(echo "$FAILED_JOBS_BASE" | jq --argjson job_id "$JOB_ID" '.[] | select(.id == $job_id)')

        # Add sample errors to job info
        ENHANCED_JOB=$(echo "$JOB_INFO" | jq --arg errors "$SAMPLE_ERRORS" '. + {sample_errors: ($errors | split("\n") | map(select(length > 0)))}')

        # Append to FAILED_JOBS array
        FAILED_JOBS=$(echo "$FAILED_JOBS" | jq --argjson job "$ENHANCED_JOB" '. + [$job]')
    done

    # Add remaining failed jobs without error extraction if more than 10
    if [ "$FAILED_COUNT" -gt 10 ]; then
        REMAINING_JOBS=$(echo "$FAILED_JOBS_BASE" | jq --argjson extracted_count 10 '.[$extracted_count:] | map(. + {sample_errors: []})')
        FAILED_JOBS=$(echo "$FAILED_JOBS" | jq --argjson remaining "$REMAINING_JOBS" '. + $remaining')
    fi
else
    FAILED_JOBS="$FAILED_JOBS_BASE"
fi

# Pipeline-level statistics
UNIQUE_PIPELINES=$(echo "$JOBS_IN_RANGE" | jq '[.[] | .pipeline.id] | unique')
TOTAL_PIPELINES=$(echo "$UNIQUE_PIPELINES" | jq 'length')

# Calculate pipeline success (pipeline is successful if it has at least one job and all jobs succeeded or were skipped)
PIPELINE_STATS=$(echo "$JOBS_IN_RANGE" | jq 'group_by(.pipeline.id) | map({
    pipeline_id: .[0].pipeline.id,
    total_jobs: length,
    failed_jobs: ([.[] | select(.status == "failed")] | length),
    status: (if ([.[] | select(.status == "failed")] | length) > 0 then "failed" else "success" end)
})')

SUCCESSFUL_PIPELINES=$(echo "$PIPELINE_STATS" | jq '[.[] | select(.status == "success")] | length')
FAILED_PIPELINES=$(echo "$PIPELINE_STATS" | jq '[.[] | select(.status == "failed")] | length')

echo "  Total: $TOTAL_JOBS jobs across $TOTAL_PIPELINES pipelines" >&2
echo "  Success: $SUCCESS_COUNT, Failed: $FAILED_COUNT" >&2
echo "" >&2

# Build final JSON output
RESULT=$(jq -n \
    --arg repo "$REPO" \
    --arg start "$CUTOFF" \
    --arg end "$END_TIME" \
    --arg desc "$TIME_DESCRIPTION" \
    --argjson hours "${HOURS:-null}" \
    --argjson days "${DAYS:-null}" \
    --argjson total "$TOTAL_JOBS" \
    --argjson success "$SUCCESS_COUNT" \
    --argjson failed "$FAILED_COUNT" \
    --argjson skipped "$SKIPPED_COUNT" \
    --argjson canceled "$CANCELED_COUNT" \
    --argjson running "$RUNNING_COUNT" \
    --argjson pending "$PENDING_COUNT" \
    --argjson by_stage "$BY_STAGE" \
    --argjson failed_jobs "$FAILED_JOBS" \
    --argjson total_pipelines "$TOTAL_PIPELINES" \
    --argjson successful_pipelines "$SUCCESSFUL_PIPELINES" \
    --argjson failed_pipelines "$FAILED_PIPELINES" \
    '{
        repository: $repo,
        time_range: {
            start: $start,
            end: $end,
            description: $desc,
            hours: $hours,
            days: $days
        },
        total_jobs: $total,
        job_statistics: {
            success: $success,
            failed: $failed,
            skipped: $skipped,
            canceled: $canceled,
            running: $running,
            pending: $pending
        },
        by_stage: $by_stage,
        pipelines: {
            total: $total_pipelines,
            successful: $successful_pipelines,
            failed: $failed_pipelines
        },
        failed_jobs: $failed_jobs
    }')

# Add runner filter info if applicable
if [ -n "$RUNNER_TAG" ]; then
    RESULT=$(echo "$RESULT" | jq \
        --arg tag "$RUNNER_TAG" \
        --argjson matched "$TOTAL_JOBS" \
        --argjson failed "$FAILED_COUNT" \
        '. + {
            runner_filter: {
                pattern: $tag,
                matched_jobs: $matched,
                failed: $failed
            }
        }')
fi

# Output
if [ "$OUTPUT_MODE" = "json" ]; then
    # Save full analysis to state
    STATE_ID=$(save_state "analyze_recent_jobs" "$RESULT" \
        "Analyzed $TOTAL_JOBS jobs from $REPO ($TIME_DESCRIPTION)")

    # Return only summary + state reference
    echo "$RESULT" | jq --arg state_id "$STATE_ID" '{
        repository: .repository,
        time_range: .time_range,
        total_jobs: .total_jobs,
        job_statistics: .job_statistics,
        by_stage: .by_stage,
        pipelines: .pipelines,
        failed_jobs_count: (.failed_jobs | length),
        runner_filter: .runner_filter,
        state_id: $state_id,
        message: "Full analysis saved to state. Use ./scripts/view_state.sh \($state_id) to retrieve complete details including error samples."
    }'
else
    # Human-readable output
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║           Recent Jobs Analysis                                 ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Repository: $REPO"
    echo "Time Range: $TIME_DESCRIPTION"
    echo "  Start: $CUTOFF"
    echo "  End:   $END_TIME"
    echo ""

    if [ -n "$RUNNER_TAG" ]; then
        echo "Runner Filter: $RUNNER_TAG"
        echo ""
    fi

    echo "────────────────────────────────────────────────────────────────"
    echo ""
    echo "Job Statistics:"
    echo "  Total Jobs:    $TOTAL_JOBS"
    echo "  Success:       $SUCCESS_COUNT ($(( SUCCESS_COUNT * 100 / (TOTAL_JOBS > 0 ? TOTAL_JOBS : 1) ))%)"
    echo "  Failed:        $FAILED_COUNT ($(( FAILED_COUNT * 100 / (TOTAL_JOBS > 0 ? TOTAL_JOBS : 1) ))%)"
    echo "  Skipped:       $SKIPPED_COUNT"
    echo "  Canceled:      $CANCELED_COUNT"
    echo "  Running:       $RUNNING_COUNT"
    echo "  Pending:       $PENDING_COUNT"
    echo ""

    echo "────────────────────────────────────────────────────────────────"
    echo ""
    echo "Pipeline Statistics:"
    echo "  Total Pipelines:      $TOTAL_PIPELINES"
    echo "  Successful Pipelines: $SUCCESSFUL_PIPELINES"
    echo "  Failed Pipelines:     $FAILED_PIPELINES"
    echo ""

    echo "────────────────────────────────────────────────────────────────"
    echo ""
    echo "By Stage:"
    echo "$BY_STAGE" | jq -r '.[] | "  \(.stage):\n    Total: \(.total), Failed: \(.failed), Success Rate: \(.success_rate)%\n"'

    if [ "$FAILED_COUNT" -gt 0 ]; then
        echo "────────────────────────────────────────────────────────────────"
        echo ""
        echo "Failed Jobs ($FAILED_COUNT):"
        echo "$FAILED_JOBS" | jq -r '.[] | "  ❌ #\(.id): \(.name) (\(.stage))\n     Pipeline: #\(.pipeline_id)\n     Reason: \(.failure_reason)\n     Runner: \(.runner)\n     URL: \(.web_url)\n"'
    fi

    echo "────────────────────────────────────────────────────────────────"
    echo ""
    echo "💡 For JSON output: $(basename "$0") $REPO --hours ${HOURS:-24} --json"
    echo "💡 Parse specific fields: ... | jq '.job_statistics'"
fi

echo "Analysis complete!" >&2
