#!/usr/bin/env bash
# Analyze GitLab CI/CD jobs grouped by runner tags
#
# Usage:
#   analyze_by_runner.sh <owner/repo> [OPTIONS]
#
# Analyzes job performance and success rates across different runner types.
# Useful for identifying runner-specific issues and comparing runner performance.
#
# Examples:
#   # Analyze all runners in last 24 hours
#   ./analyze_by_runner.sh owner/repo --hours 24
#
#   # Compare specific runner tags
#   ./analyze_by_runner.sh owner/repo --hours 24 --compare "aipcc-small-x86_64,aipcc-small-aarch64"
#
#   # Last 7 days
#   ./analyze_by_runner.sh owner/repo --days 7

set -euo pipefail

# Set state directory for this skill
SKILL_STATE_DIR="${GITLAB_JOB_ANALYZER_STATE_DIR:-$HOME/.gitlab-job-analyzer/state}"

# Source shared state library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../tools/memory/scripts/state.sh"

show_usage() {
    cat << 'EOF'
Usage: analyze_by_runner.sh <owner/repo> [OPTIONS]

Analyze GitLab CI/CD jobs grouped by runner tags.

ARGUMENTS:
    owner/repo             GitLab repository (e.g., gitlab-org/gitlab)

OPTIONS:
    --hours N              Analyze jobs from last N hours (default: 24)
    --days N               Analyze jobs from last N days
    --since DATE           Analyze jobs since specific date (ISO-8601)
    --compare TAGS         Compare specific runner tags (comma-separated)
    --json                 Output JSON format (default)
    --human                Output human-readable format
    -h, --help             Show this help message

OUTPUT (JSON mode - default):
    {
      "repository": "owner/repo",
      "time_range": {...},
      "total_jobs": 234,
      "by_runner_tag": [
        {
          "tag": "aipcc-small-x86_64",
          "total_jobs": 150,
          "success": 140,
          "failed": 10,
          "success_rate": 93,
          "avg_duration": 245.5,
          "common_failures": [...]
        }
      ]
    }

EXAMPLES:
    # Analyze all runners in last 24 hours
    analyze_by_runner.sh owner/repo --hours 24

    # Last 7 days
    analyze_by_runner.sh owner/repo --days 7

    # Compare specific runner tags
    analyze_by_runner.sh owner/repo --hours 24 --compare "aipcc-small-x86_64,aipcc-large-x86_64"

    # Human-readable output
    analyze_by_runner.sh owner/repo --hours 24 --human

EOF
}

# Parse arguments
REPO=""
HOURS=""
DAYS=""
SINCE=""
COMPARE_TAGS=""
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
        --compare)
            COMPARE_TAGS="$2"
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
    CUTOFF="$SINCE"
    TIME_DESCRIPTION="since $SINCE"
elif [ -n "$DAYS" ]; then
    if ! CUTOFF=$(date -d "$DAYS days ago" --iso-8601=seconds 2>/dev/null); then
        echo '{"error": "Failed to calculate date from --days"}' >&2
        exit 1
    fi
    TIME_DESCRIPTION="last $DAYS days"
elif [ -n "$HOURS" ]; then
    if ! CUTOFF=$(date -d "$HOURS hours ago" --iso-8601=seconds 2>/dev/null); then
        echo '{"error": "Failed to calculate date from --hours"}' >&2
        exit 1
    fi
    TIME_DESCRIPTION="last $HOURS hours"
else
    # Default to 24 hours
    HOURS=24
    if ! CUTOFF=$(date -d "24 hours ago" --iso-8601=seconds 2>/dev/null); then
        echo '{"error": "Failed to calculate date"}' >&2
        exit 1
    fi
    TIME_DESCRIPTION="last 24 hours (default)"
fi

END_TIME=$(date --iso-8601=seconds)
ENCODED_REPO="${REPO//\//%2F}"

# Progress messages
echo "=== Analyzing Jobs by Runner for $REPO ===" >&2
echo "Time range: $TIME_DESCRIPTION" >&2
echo "" >&2

# Fetch jobs efficiently using pipelines first
echo "Step 1/2: Fetching recent pipelines (updated after $CUTOFF)..." >&2
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
    # Fetch jobs from each pipeline
    echo "  Fetching jobs from $PIPELINE_COUNT pipelines..." >&2

    # Initialize empty jobs array
    echo "[]" > "$TEMP_DIR/all_jobs.json"

    # Counter for progress
    PIPELINE_NUM=0

    # Fetch jobs for each pipeline (using process substitution to avoid subshell)
    while read -r PIPELINE_ID; do
        PIPELINE_NUM=$((PIPELINE_NUM + 1))
        echo "    Pipeline $PIPELINE_NUM/$PIPELINE_COUNT (ID: $PIPELINE_ID)..." >&2

        # Fetch jobs for this pipeline
        glab api --method GET "projects/$ENCODED_REPO/pipelines/$PIPELINE_ID/jobs?per_page=100" --paginate > "$TEMP_DIR/pipeline_${PIPELINE_ID}_jobs.json" 2>/dev/null || echo "[]" > "$TEMP_DIR/pipeline_${PIPELINE_ID}_jobs.json"
    done < <(jq -r '.[].id' "$TEMP_DIR/pipelines.json")

    # Combine all jobs into single array
    jq -s 'add' "$TEMP_DIR"/pipeline_*_jobs.json > "$TEMP_DIR/all_jobs.json"

    # Filter by time range
    JOBS_IN_RANGE=$(jq --arg cutoff "$CUTOFF" '[.[] | select(.created_at >= $cutoff)]' "$TEMP_DIR/all_jobs.json")

    TOTAL_JOBS=$(echo "$JOBS_IN_RANGE" | jq 'length')
    echo "  Found $TOTAL_JOBS jobs in time range (across $PIPELINE_COUNT pipelines)" >&2
fi

echo "" >&2

if [ "$TOTAL_JOBS" -eq 0 ]; then
    if [ "$OUTPUT_MODE" = "json" ]; then
        jq -n \
            --arg repo "$REPO" \
            --arg start "$CUTOFF" \
            --arg end "$END_TIME" \
            --arg desc "$TIME_DESCRIPTION" \
            '{
                repository: $repo,
                time_range: {start: $start, end: $end, description: $desc},
                total_jobs: 0,
                message: "No jobs found in specified time range"
            }'
    else
        echo "No jobs found in time range: $TIME_DESCRIPTION"
    fi
    exit 0
fi

# Step 2: Group by runner tags
echo "Step 2/2: Grouping by runner tags..." >&2

# Extract unique runner tags and analyze each
if [ -n "$COMPARE_TAGS" ]; then
    # Compare specific tags
    IFS=',' read -ra TAG_ARRAY <<< "$COMPARE_TAGS"
    TAG_FILTER=""
    for tag in "${TAG_ARRAY[@]}"; do
        TAG_FILTER="$TAG_FILTER, \"$tag\""
    done
    TAG_FILTER="[${TAG_FILTER:2}]"  # Remove leading comma-space
else
    # Get all unique runner tags
    TAG_FILTER="null"
fi

# Analyze by runner tag
BY_RUNNER_TAG=$(echo "$JOBS_IN_RANGE" | jq --argjson tags "$TAG_FILTER" '
    # Flatten jobs with their tags
    [
        .[] |
        {
            job_id: .id,
            job_name: .name,
            stage: .stage,
            status: .status,
            duration: .duration,
            failure_reason: (.failure_reason // "unknown"),
            runner: (.runner.description // "unknown"),
            tags: .tag_list
        } |
        # Create one entry per tag
        .tags[] as $tag |
        (if $tags == null or ($tags | index($tag)) then
            {
                tag: $tag,
                job_id: .job_id,
                job_name: .job_name,
                stage: .stage,
                status: .status,
                duration: .duration,
                failure_reason: .failure_reason,
                runner: .runner
            }
        else
            empty
        end)
    ] |
    # Group by tag
    group_by(.tag) |
    map({
        tag: .[0].tag,
        total_jobs: length,
        success: ([.[] | select(.status == "success")] | length),
        failed: ([.[] | select(.status == "failed")] | length),
        skipped: ([.[] | select(.status == "skipped")] | length),
        canceled: ([.[] | select(.status == "canceled")] | length),
        running: ([.[] | select(.status == "running")] | length),
        success_rate: (if length > 0 then (([.[] | select(.status == "success")] | length) * 100 / length | floor) else 0 end),
        avg_duration: (if length > 0 then ([.[].duration // 0] | add / length | floor) else 0 end),
        max_duration: ([.[].duration // 0] | max),
        min_duration: ([.[].duration // 0] | min),
        common_failures: (
            [.[] | select(.status == "failed") | .failure_reason] |
            group_by(.) |
            map({reason: .[0], count: length}) |
            sort_by(-.count)
        ),
        failed_jobs: (
            [.[] | select(.status == "failed") | {
                id: .job_id,
                name: .job_name,
                stage: .stage,
                failure_reason
            }]
        )
    }) |
    sort_by(-.total_jobs)
')

echo "  Analyzed $(echo "$BY_RUNNER_TAG" | jq 'length') unique runner tags" >&2
echo "" >&2

# Build final result
RESULT=$(jq -n \
    --arg repo "$REPO" \
    --arg start "$CUTOFF" \
    --arg end "$END_TIME" \
    --arg desc "$TIME_DESCRIPTION" \
    --argjson total "$TOTAL_JOBS" \
    --argjson by_runner "$BY_RUNNER_TAG" \
    '{
        repository: $repo,
        time_range: {
            start: $start,
            end: $end,
            description: $desc
        },
        total_jobs: $total,
        by_runner_tag: $by_runner
    }')

# Output
if [ "$OUTPUT_MODE" = "json" ]; then
    # Save full analysis to state
    STATE_ID=$(save_state "analyze_by_runner" "$RESULT" \
        "Analyzed $TOTAL_JOBS jobs by runner from $REPO ($TIME_DESCRIPTION)")

    # Return summary + state reference
    echo "$RESULT" | jq --arg state_id "$STATE_ID" '{
        repository: .repository,
        time_range: .time_range,
        total_jobs: .total_jobs,
        runner_count: (.by_runner_tag | length),
        by_runner_tag: [.by_runner_tag[] | {tag, total_jobs, success_rate, failed_jobs: .failed_jobs | length}],
        state_id: $state_id,
        message: "Full analysis saved to state. Use ./scripts/view_state.sh \($state_id) to retrieve complete details."
    }'
else
    # Human-readable output
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║           Runner Analysis Results                              ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Repository: $REPO"
    echo "Time Range: $TIME_DESCRIPTION"
    echo "  Start: $CUTOFF"
    echo "  End:   $END_TIME"
    echo ""
    echo "Total Jobs: $TOTAL_JOBS"
    echo ""

    echo "────────────────────────────────────────────────────────────────"
    echo ""

    RUNNER_COUNT=$(echo "$BY_RUNNER_TAG" | jq 'length')
    if [ "$RUNNER_COUNT" -eq 0 ]; then
        echo "No runner tags found in jobs"
    else
        echo "Runner Tag Analysis ($RUNNER_COUNT tags):"
        echo ""

        echo "$BY_RUNNER_TAG" | jq -r '.[] |
            "  🏃 \(.tag):\n" +
            "     Total Jobs:    \(.total_jobs)\n" +
            "     Success:       \(.success) (\(.success_rate)%)\n" +
            "     Failed:        \(.failed)\n" +
            "     Avg Duration:  \(.avg_duration)s\n" +
            "     Max Duration:  \(.max_duration)s\n" +
            (if (.common_failures | length) > 0 then
                "     Common Failures:\n" +
                (.common_failures | map("       - \(.reason): \(.count) job(s)") | join("\n")) +
                "\n"
            else
                ""
            end) +
            "\n"
        '
    fi

    echo "────────────────────────────────────────────────────────────────"
    echo ""
    echo "💡 For JSON output: $(basename "$0") $REPO --hours ${HOURS:-24} --json"
    echo "💡 Parse specific tags: ... | jq '.by_runner_tag[] | select(.tag == \"aipcc-small-x86_64\")'"
fi

echo "Analysis complete!" >&2
