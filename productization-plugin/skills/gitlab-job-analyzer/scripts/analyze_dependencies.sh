#!/usr/bin/env bash
#
# Analyze job dependencies in a GitLab CI pipeline
#
# Usage:
#   analyze_dependencies.sh <owner/repo> <pipeline-id>
#   analyze_dependencies.sh --help

set -euo pipefail

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] <owner/repo> <pipeline-id>

Analyze job dependencies in a GitLab CI pipeline.

ARGUMENTS:
    owner/repo             GitLab repository (e.g., gitlab-org/gitlab)
    pipeline-id            Pipeline ID to analyze

OUTPUT:
    - Dependency tree (which jobs depend on which)
    - Blocked jobs (jobs waiting on failed dependencies)
    - Critical path (longest dependency chain)
    - Impact analysis (what fails if a job fails)

EXAMPLES:
    # Analyze dependencies in pipeline 12345
    $(basename "$0") owner/repo 12345

OPTIONS:
    -h, --help              Show this help message
    --graph                 Output as dependency graph (mermaid format)
    --json                  Output as JSON

EOF
}

# Parse arguments
OUTPUT_GRAPH=false
OUTPUT_FORMAT="text"

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        --graph)
            OUTPUT_GRAPH=true
            shift
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
else
    echo "Error: jq is required for this script" >&2
    exit 1
fi

# Temporary directory
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

JOBS_JSON="$TEMP_DIR/jobs.json"

# Fetch all jobs in the pipeline
glab api --method GET "projects/$ENCODED_REPO/pipelines/$PIPELINE_ID/jobs" > "$JOBS_JSON"

# Extract job count
TOTAL_JOBS=$(jq 'length' < "$JOBS_JSON")

if [[ $TOTAL_JOBS -eq 0 ]]; then
    echo "No jobs found in pipeline $PIPELINE_ID"
    exit 1
fi

# Extract unique stages (used by graph, JSON, and text output)
STAGES=$(jq -r '.[].stage' < "$JOBS_JSON" | sort -u)

# Mermaid graph output
if $OUTPUT_GRAPH; then
    echo '```mermaid'
    echo 'graph TD'

    # Extract jobs and dependencies
    jq -r '.[] | "\(.id)[\(.name)]"' < "$JOBS_JSON" | while read -r job_def; do
        echo "    $job_def"
    done

    # Extract dependencies (needs)
    # Note: GitLab API doesn't always expose 'needs' in job JSON
    # We'll use stage dependencies as a fallback

    PREV_STAGE=""

    while IFS= read -r STAGE; do
        if [[ -n "$PREV_STAGE" ]]; then
            # Jobs in current stage depend on jobs in previous stage
            PREV_JOBS=$(jq -r --arg stage "$PREV_STAGE" '.[] | select(.stage == $stage) | .id' < "$JOBS_JSON")
            CURR_JOBS=$(jq -r --arg stage "$STAGE" '.[] | select(.stage == $stage) | .id' < "$JOBS_JSON")

            while read -r curr_job; do
                while read -r prev_job; do
                    echo "    $prev_job --> $curr_job"
                done <<< "$PREV_JOBS"
            done <<< "$CURR_JOBS"
        fi
        PREV_STAGE="$STAGE"
    done <<< "$STAGES"

    # Color failed jobs
    FAILED_JOBS=$(jq -r '.[] | select(.status == "failed") | .id' < "$JOBS_JSON")
    while read -r job_id; do
        [[ -z "$job_id" ]] && continue
        echo "    style $job_id fill:#f88"
    done <<< "$FAILED_JOBS"

    # Color running jobs
    RUNNING_JOBS=$(jq -r '.[] | select(.status == "running") | .id' < "$JOBS_JSON")
    while read -r job_id; do
        [[ -z "$job_id" ]] && continue
        echo "    style $job_id fill:#ff8"
    done <<< "$RUNNING_JOBS"

    # Color successful jobs
    SUCCESS_JOBS=$(jq -r '.[] | select(.status == "success") | .id' < "$JOBS_JSON")
    while read -r job_id; do
        [[ -z "$job_id" ]] && continue
        echo "    style $job_id fill:#8f8"
    done <<< "$SUCCESS_JOBS"

    echo '```'
    exit 0
fi

# JSON output
if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    # Build stage structure
    STAGES_JSON=$(jq -r 'group_by(.stage) | map({
        stage: .[0].stage,
        jobs: [.[] | {id, name, status}]
    })' < "$JOBS_JSON")

    # Identify failed jobs
    FAILED_JOBS_JSON=$(jq '[.[] | select(.status == "failed") | {id, name, stage, failure_reason}]' < "$JOBS_JSON")

    # Identify blocked jobs
    PENDING_JOBS_JSON=$(jq '[.[] | select(.status == "pending" or .status == "created") | {id, name, stage, status}]' < "$JOBS_JSON")

    # Stage durations
    STAGE_DURATIONS=$(echo "$STAGES" | while IFS= read -r STAGE; do
        STAGE_DURATION=$(jq -r --arg stage "$STAGE" '[.[] | select(.stage == $stage) | .duration // 0] | max' < "$JOBS_JSON")
        echo "{\"stage\": \"$STAGE\", \"max_duration\": $STAGE_DURATION}"
    done | jq -s .)

    jq -n \
        --arg repo "$REPO" \
        --argjson pipeline_id "$PIPELINE_ID" \
        --argjson total_jobs "$TOTAL_JOBS" \
        --argjson stages "$STAGES_JSON" \
        --argjson failed "$FAILED_JOBS_JSON" \
        --argjson pending "$PENDING_JOBS_JSON" \
        --argjson stage_durations "$STAGE_DURATIONS" \
        '{
            repository: $repo,
            pipeline_id: $pipeline_id,
            total_jobs: $total_jobs,
            stages: $stages,
            failed_jobs: $failed,
            blocked_jobs: $pending,
            stage_durations: $stage_durations,
            total_stages: ($stages | length),
            summary: {
                total_failed: ($failed | length),
                total_blocked: ($pending | length)
            }
        }'

    exit 0
fi

# Text output
cat << EOF
╔════════════════════════════════════════════════════════════════╗
║              Pipeline Dependency Analysis                      ║
╚════════════════════════════════════════════════════════════════╝

Repository: $REPO
Pipeline: #$PIPELINE_ID
Total Jobs: $TOTAL_JOBS

EOF

# Analyze by stage
echo "## Job Stages and Dependencies"
echo ""

STAGE_NUM=1

while IFS= read -r STAGE; do
    JOBS_IN_STAGE=$(jq -r --arg stage "$STAGE" '.[] | select(.stage == $stage) | "\(.id)|\(.name)|\(.status)"' < "$JOBS_JSON")
    JOB_COUNT=$(echo "$JOBS_IN_STAGE" | grep -c "^" || echo "0")

    echo "Stage $STAGE_NUM: $STAGE ($JOB_COUNT jobs)"
    echo ""

    while IFS='|' read -r job_id job_name job_status; do
        [[ -z "$job_id" ]] && continue

        # Status indicator
        case "$job_status" in
            success)
                STATUS_ICON="✅"
                ;;
            failed)
                STATUS_ICON="❌"
                ;;
            running)
                STATUS_ICON="🔄"
                ;;
            pending)
                STATUS_ICON="⏳"
                ;;
            *)
                STATUS_ICON="⚪"
                ;;
        esac

        echo "  $STATUS_ICON #$job_id: $job_name ($job_status)"
    done <<< "$JOBS_IN_STAGE"

    echo ""
    STAGE_NUM=$((STAGE_NUM + 1))
done <<< "$STAGES"

echo "────────────────────────────────────────────────────────────────"
echo ""

# Identify blocked jobs
echo "## Blocked Jobs"
echo ""

PENDING_JOBS=$(jq -r '.[] | select(.status == "pending" or .status == "created") | "\(.id)|\(.name)|\(.stage)"' < "$JOBS_JSON")

if [[ -n "$PENDING_JOBS" ]]; then
    echo "Jobs waiting to run:"
    echo ""

    while IFS='|' read -r job_id job_name job_stage; do
        [[ -z "$job_id" ]] && continue
        echo "  ⏳ #$job_id: $job_name (waiting in stage: $job_stage)"
    done <<< "$PENDING_JOBS"
else
    echo "No jobs are currently blocked/pending"
fi

echo ""
echo "────────────────────────────────────────────────────────────────"
echo ""

# Identify failed jobs and their impact
echo "## Failed Jobs and Impact"
echo ""

FAILED_JOBS=$(jq -r '.[] | select(.status == "failed") | "\(.id)|\(.name)|\(.stage)"' < "$JOBS_JSON")

if [[ -n "$FAILED_JOBS" ]]; then
    echo "Failed jobs (may block downstream jobs):"
    echo ""

    while IFS='|' read -r job_id job_name job_stage; do
        [[ -z "$job_id" ]] && continue
        echo "  ❌ #$job_id: $job_name (stage: $job_stage)"

        # Find jobs in later stages that might be blocked
        STAGE_ORDER=$(echo "$STAGES" | grep -n "^$job_stage$" | cut -d: -f1)
        DOWNSTREAM_STAGES=$(echo "$STAGES" | tail -n +$((STAGE_ORDER + 1)))

        if [[ -n "$DOWNSTREAM_STAGES" ]]; then
            echo "     ⚠️  May block jobs in stages: $(echo "$DOWNSTREAM_STAGES" | tr '\n' ', ' | sed 's/,$//')"
        fi
    done <<< "$FAILED_JOBS"
else
    echo "✅ No failed jobs - pipeline dependencies are healthy"
fi

echo ""
echo "────────────────────────────────────────────────────────────────"
echo ""

# Critical path analysis
echo "## Critical Path Analysis"
echo ""

# Calculate stage durations
echo "Stage durations (total time spent in each stage):"
echo ""

while IFS= read -r STAGE; do
    STAGE_DURATION=$(jq -r --arg stage "$STAGE" '[.[] | select(.stage == $stage) | .duration // 0] | max' < "$JOBS_JSON")

    if [[ $STAGE_DURATION -lt 60 ]]; then
        STAGE_DURATION_FMT="${STAGE_DURATION}s"
    else
        minutes=$((STAGE_DURATION / 60))
        secs=$((STAGE_DURATION % 60))
        STAGE_DURATION_FMT="${minutes}m ${secs}s"
    fi

    echo "  $STAGE: $STAGE_DURATION_FMT"
done <<< "$STAGES"

echo ""
echo "ℹ️  Pipeline runs stages sequentially, so total time is roughly the sum of stage durations"
echo ""

echo "────────────────────────────────────────────────────────────────"
echo ""

# Recommendations
cat << EOF
## Recommendations

1. **Failed Jobs**: Fix failed jobs to unblock downstream stages
2. **Critical Path**: Focus on optimizing slowest stages to reduce overall pipeline time
3. **Parallelization**: Jobs within a stage run in parallel - ensure you have enough runners
4. **Dependencies**: Consider using 'needs:' keyword to create explicit dependencies and avoid waiting for entire stages

EOF

# Summary
cat << EOF
## Summary

- Total stages: $(echo "$STAGES" | wc -l)
- Failed jobs: $(echo "$FAILED_JOBS" | grep -c "^" || echo "0")
- Pending jobs: $(echo "$PENDING_JOBS" | grep -c "^" || echo "0")

To visualize dependencies as a graph, run:
  $(basename "$0") $REPO $PIPELINE_ID --graph

EOF
