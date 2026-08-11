---
name: gitlab-job-analyzer
description: Analyze GitLab CI/CD job failures, parse logs, identify error patterns, and troubleshoot pipeline issues. This skill should be used when the user asks to investigate failed jobs, debug pipeline failures, analyze job logs, compare job runs, or generate failure reports. Uses the official GitLab CLI (glab) and integrates with the gitlab skill.
allowed-tools: Bash(*/gitlab-job-analyzer/scripts/*.sh:*),Bash(*/tools/*/install.sh:*)
---

# GitLab Job Analyzer

## Overview

Comprehensive analysis of GitLab CI/CD jobs - identify failures, parse logs, extract errors, compare runs, analyze dependencies, and generate structured failure reports.

**Prerequisites:**
- `glab` command is available
- User is already authenticated
- Works with gitlab.com, GitLab Self-Managed, and GitLab Dedicated
- Optional: `jq` for JSON parsing

**Installation:**
Use the centralized tool installation scripts to install dependencies:

```bash
# glab CLI (required)
../../../tools/glab/install.sh          # Check and install glab
../../../tools/glab/install.sh --check  # Check only, don't install

# jq (optional, recommended)
../../../tools/jq/install.sh            # Check and install jq
../../../tools/jq/install.sh --check    # Check only, don't install
```

The tool scripts are idempotent - safe to run multiple times. They will only install if the tool is not present or outdated.

**Philosophy:**
Start with job status, identify failures, fetch logs, extract error patterns, and provide actionable insights. Use structured analysis to diagnose root causes.

## Core Concepts

- **Job**: Individual unit of work in a CI/CD pipeline (build, test, deploy)
- **Pipeline**: Collection of jobs organized in stages
- **Job Log**: Console output from a job execution
- **Job Artifacts**: Files produced by a job (test reports, binaries, coverage)
- **Job Dependencies**: Jobs that must complete before a job can start
- **Job Trace**: Complete log output from a job execution

## Analysis Philosophy: JSON-First

**All analysis scripts output JSON by default** to make results easy to parse and minimize model interaction.

**⚠️ RECOMMENDATION: Use `analyze_pipeline.sh` for comprehensive analysis**

For most pipeline investigations, **use the comprehensive analyzer** to get all data in a single call:
- ✅ Single round-trip - get complete pipeline analysis in one command
- ✅ No multiple script calls - everything included (metadata, jobs, errors, dependencies)
- ✅ Efficient - For typical pipelines (even 50+ jobs), JSON output is manageable (~100KB)
- ✅ Parse what you need - Use `jq` to extract specific fields

**Recommended approach - get everything in one call:**

```bash
# Run comprehensive analysis and capture full JSON output
OUTPUT=$(./scripts/analyze_pipeline.sh owner/repo 12345)

# Parse specific fields as needed
echo "$OUTPUT" | jq '.job_statistics'
echo "$OUTPUT" | jq '.failed_jobs[] | {id, name, stage, failure_reason}'
echo "$OUTPUT" | jq '.common_error_patterns'
echo "$OUTPUT" | jq '.stages[] | select(.failed > 0)'
```

### JSON Output (Default)

```bash
# Get all pipeline data as JSON
./scripts/analyze_pipeline.sh owner/repo 12345

# Output structure:
{
  "repository": "owner/repo",
  "pipeline_id": 12345,
  "pipeline_metadata": {
    "status": "failed",
    "ref": "main",
    "sha": "abc123...",
    "duration": 1234,
    "created_at": "2026-02-09T...",
    "user": "username"
  },
  "job_statistics": {
    "total": 20,
    "passed": 15,
    "failed": 3,
    "skipped": 2,
    "running": 0
  },
  "stages": [ ... ],
  "analyzed_jobs": [ ... ],  // Failed jobs with error analysis
  "failure_reasons": [ ... ],
  "blocked_jobs": [ ... ],
  "common_error_patterns": [ ... ]
}
```

### Human-Readable Output

Add `--human` flag for formatted output:

```bash
./scripts/analyze_pipeline.sh owner/repo 12345 --human
```

### When to Use Specialized Scripts

The comprehensive analyzer is recommended for most cases. Use specialized scripts for:
- **`compare_job_logs.sh`** - Detailed comparison of two specific job runs
- **`analyze_dependencies.sh`** - Dependency graph visualization
- **`extract_errors.sh`** - Detailed error categorization of a single log file

All specialized scripts also support `--json` output.

## Common Use Cases

**Most common workflow:** Time-based job analysis across ALL pipelines.

Use the following scripts based on your needs:

1. **Recent Job Summary (Most Common)** → `analyze_recent_jobs.sh`
   - "What jobs ran/failed in the last 24 hours?"
   - "Show me all failures this week"
   - Analyzes jobs across ALL pipelines in a time range

2. **Runner-Specific Analysis** → `analyze_by_runner.sh`
   - "Show me failures on aipcc-* runners"
   - "Compare performance across different runner types"
   - Groups jobs by runner tags and shows success rates

3. **Single Pipeline Deep Dive** → `analyze_pipeline.sh`
   - "What failed in pipeline #12345?"
   - "Analyze errors in this specific pipeline"
   - Comprehensive analysis of one pipeline

4. **Compare Two Job Runs** → `compare_job_logs.sh`
   - "Why did this job start failing?"
   - "Compare successful vs failed runs"
   - Find differences between job executions

## Analysis Workflows

### Workflow 1: Recent Job Summary (Most Common Use Case)

**User:** "What jobs failed in the last 24 hours?" or "Summarize jobs for the last 24h"

This is the **most common use case** - analyzing recent activity across ALL pipelines.

**Recommended Approach:**

```bash
# Last 24 hours (default)
./scripts/analyze_recent_jobs.sh owner/repo --hours 24

# Parse specific fields
./scripts/analyze_recent_jobs.sh owner/repo --hours 24 | jq '.job_statistics'
# Output: {"success": 179, "failed": 22, "skipped": 32, ...}

./scripts/analyze_recent_jobs.sh owner/repo --hours 24 | jq '.by_stage'
# Output: Stage-level breakdown with failure counts

./scripts/analyze_recent_jobs.sh owner/repo --hours 24 | jq '.failed_jobs[] | {id, name, stage, failure_reason}'
# Output: List of failed jobs with details

# Human-readable output
./scripts/analyze_recent_jobs.sh owner/repo --hours 24 --human
```

**Other time ranges:**

```bash
# Last 7 days
./scripts/analyze_recent_jobs.sh owner/repo --days 7

# Since specific date
./scripts/analyze_recent_jobs.sh owner/repo --since "2026-02-09T00:00:00Z"
```

**Filter by runner tags:**

```bash
# Only jobs on aipcc-* runners
./scripts/analyze_recent_jobs.sh owner/repo --hours 24 --runner-tag "aipcc-"

# See how many jobs matched the filter
./scripts/analyze_recent_jobs.sh owner/repo --hours 24 --runner-tag "aipcc-" | jq '.runner_filter'
```

**Output includes:**
- Total jobs in time period
- Breakdown by status (success/failed/skipped/canceled/running)
- Breakdown by stage with failure counts and success rates
- Pipeline summary (total, successful, failed)
- Detailed list of failed jobs with failure reasons
- Runner filter statistics (if --runner-tag provided)

### Workflow 2: Runner-Specific Analysis

**User:** "Show me failures on aipcc-* runners" or "Compare runner performance"

Analyze job performance grouped by runner tags.

**Commands:**

```bash
# Analyze all runners in last 24 hours
./scripts/analyze_by_runner.sh owner/repo --hours 24

# Parse specific runner
./scripts/analyze_by_runner.sh owner/repo --hours 24 | jq '.by_runner_tag[] | select(.tag == "aipcc-small-x86_64")'

# Compare specific runners
./scripts/analyze_by_runner.sh owner/repo --hours 24 --compare "aipcc-small-x86_64,aipcc-small-aarch64"

# Human-readable output
./scripts/analyze_by_runner.sh owner/repo --days 7 --human
```

**Output includes:**
- Jobs grouped by runner tag
- Success rate per runner type
- Average/max/min duration per runner
- Common failures per runner type
- List of failed jobs per runner

**Use cases:**
- Identify runner-specific issues (e.g., "aipcc-small-x86_64 has 80% failure rate")
- Compare performance across architectures (x86_64 vs aarch64)
- Find slow runners (high avg_duration)
- Track infrastructure problems

### Workflow 3: Single Pipeline Deep Dive

**User:** "What failed in pipeline #12345?" or "Analyze errors in this specific pipeline"

When you need to deeply analyze a **specific pipeline** (not recent activity across all pipelines).

**IMPORTANT - Pipeline ID vs IID:**
- `glab ci list` shows: `#2315214741 (#2433)`
- First number (2315214741) is the **pipeline ID** → USE THIS
- Number in parentheses (2433) is the IID → DO NOT use this

**Recommended Approach (JSON-first):**

```bash
# Step 1: Run comprehensive analysis
OUTPUT=$(./scripts/analyze_pipeline.sh owner/repo 12345)

# Step 2: Extract key information
echo "$OUTPUT" | jq '.job_statistics'
# Output: {"total": 20, "passed": 15, "failed": 3, "skipped": 2, "running": 0}

echo "$OUTPUT" | jq '.analyzed_jobs[] | select(.status == "failed") | {id, name, stage, failure_reason}'
# Output: List of failed jobs with details

echo "$OUTPUT" | jq '.common_error_patterns'
# Output: Error patterns across all failures

echo "$OUTPUT" | jq '.analyzed_jobs[] | select(.status == "failed") | .sample_error_lines[]' | head -20
# Output: Sample error lines from failed jobs
```

**Benefits:**
- ✅ Single command gets all data (~100KB JSON for typical pipeline)
- ✅ No multiple round-trips to GitLab API
- ✅ Error analysis already included
- ✅ Parse specific fields as needed with jq

**Special Cases:**

**Pipeline with 0 jobs:**
If a pipeline failed during creation (YAML syntax error, etc.), the script will detect this:
```bash
./scripts/analyze_pipeline.sh owner/repo 12345
# Output: {"total_jobs": 0, "message": "Pipeline has no jobs. This typically occurs when..."}
```

### Workflow 4: Compare Job Runs (Find Regressions)

**User:** "Why did job 'test-integration' start failing? It worked before."

**Approach:**

Use `analyze_recent_jobs.sh` to find recent jobs, then use `compare_job_logs.sh` to compare specific runs:

```bash
# Step 1: Find recent jobs with the same name
./scripts/analyze_recent_jobs.sh owner/repo --hours 48 | jq -r '.all_jobs[] | select(.name == "test-integration") | "\(.id) \(.status) \(.created_at)"' | head -10

# Step 2: Get job IDs from the output above, then compare
# Use the last successful and last failed job IDs
OUTPUT=$(./scripts/compare_job_logs.sh owner/repo <success-job-id> <failed-job-id> --json)

# Step 3: Extract comparison results
echo "$OUTPUT" | jq '.comparison'
# Output: {duration_difference: -45, same_runner: true, same_commit: false, ...}

echo "$OUTPUT" | jq '.log_analysis.new_errors[]'
# Output: New error lines in the failed job

echo "$OUTPUT" | jq '.recommendation'
# Output: "Job 1 succeeded but Job 2 failed - investigate new errors..."
```

**Human-readable output:**

```bash
./scripts/compare_job_logs.sh owner/repo <success-job-id> <failed-job-id>
```

### Workflow 5: Extract Error Patterns

**User:** "What errors are causing the test job to fail?"

**Approach:**

Use `analyze_pipeline.sh` to get error analysis for all failed jobs in a pipeline:

```bash
# Analyze entire pipeline with error extraction
OUTPUT=$(./scripts/analyze_pipeline.sh owner/repo <pipeline-id>)

# Get error patterns across all failures
echo "$OUTPUT" | jq '.common_error_patterns'

# Get specific failed job's error lines
echo "$OUTPUT" | jq '.analyzed_jobs[] | select(.name == "test-integration") | .sample_error_lines'
```

**For detailed error categorization of a specific job log:**

The `extract_errors.sh` script can categorize errors if you have a log file saved locally:

```bash
# If you have a log file from another source
./scripts/extract_errors.sh job.log --json | jq '.categories'
```

### Workflow 6: Analyze Job Dependencies

**User:** "Which jobs are blocking the deployment?"

**Approach:**

Use the `analyze_dependencies.sh` script to analyze job dependencies and critical paths:

```bash
# Analyze dependencies and get JSON output
OUTPUT=$(./scripts/analyze_dependencies.sh owner/repo <pipeline-id> --json)

# Get blocked jobs (waiting on failed dependencies)
echo "$OUTPUT" | jq '.blocked_jobs'

# Get dependency tree
echo "$OUTPUT" | jq '.stages'

# Get critical path
echo "$OUTPUT" | jq '.critical_path'
```

**For visual dependency graph:**

```bash
# Generate Mermaid graph
./scripts/analyze_dependencies.sh owner/repo <pipeline-id> --graph
```

**Human-readable output:**

```bash
./scripts/analyze_dependencies.sh owner/repo <pipeline-id>
```

### Workflow 7: Generate Failure Report

**User:** "Give me a summary of all failures in the last pipeline"

**Approach:**

Use `analyze_pipeline.sh` for JSON output or `generate_failure_report.sh` for markdown reports:

```bash
# Get comprehensive analysis (JSON)
./scripts/analyze_pipeline.sh owner/repo <pipeline-id> | jq '.'

# Get human-readable report
./scripts/analyze_pipeline.sh owner/repo <pipeline-id> --human

# Generate detailed markdown report
./scripts/generate_failure_report.sh owner/repo <pipeline-id> > failure-report.md
```

The report includes:
- Summary (total/passed/failed)
- Failed job details
- Error excerpts
- Recommendations

## Helper Scripts Reference

All scripts output JSON by default. Add `--human` for formatted text. Run any script with `--help` for full usage.

| Script | Purpose | Key Args |
|--------|---------|----------|
| `analyze_recent_jobs.sh` | Jobs across ALL pipelines in time range | `--hours N`, `--days N`, `--runner-tag PREFIX` |
| `analyze_by_runner.sh` | Jobs grouped by runner tags | `--hours N`, `--days N`, `--compare TAGS` |
| `analyze_pipeline.sh` | Single pipeline deep dive | `<pipeline-id>`, `--include-successful` |
| `compare_job_logs.sh` | Compare two job runs | `<job-id-1> <job-id-2>` |
| `analyze_dependencies.sh` | Dependency graph and critical path | `<pipeline-id>`, `--graph`, `--json` |
| `extract_errors.sh` | Categorize errors from a log file | `<log-file>`, `--json` |
| `generate_failure_report.sh` | Markdown failure report (legacy) | `<pipeline-id>` |

## Performance Optimization

**When combining this skill with other skills (especially aws-log-analyzer):**

See the complete optimization guide in the main CLAUDE.md documentation under "Performance Optimization for Cross-Skill Analysis".

**Key optimizations:**
1. **Parallel execution** - Run GitLab + AWS analysis simultaneously in one message
2. **Parse JSON once** - Capture output, parse multiple times with jq (don't re-run scripts)
3. **Skip redundant scripts** - Extract runner data from `analyze_recent_jobs.sh` with jq instead of running `analyze_by_runner.sh`
4. **Smart targeting** - Identify problematic runners first, then analyze only those AWS log groups

**Example - Optimized cross-skill analysis:**
```bash
# SINGLE MESSAGE - Parallel execution:
# Tool 1: GitLab analysis
./gitlab-job-analyzer/scripts/analyze_recent_jobs.sh owner/repo --hours 24

# Tool 2: AWS analysis (runs in parallel)
./aws-log-analyzer/scripts/analyze_errors.sh /aws/app/component1 24

# Then parse GitLab output multiple ways without re-running:
echo "$GITLAB_OUTPUT" | jq '.job_statistics'
echo "$GITLAB_OUTPUT" | jq '.by_runner_tag[] | select(.failed > 5)'
echo "$GITLAB_OUTPUT" | jq '.failed_jobs[] | {name, stage, runner_tag}'
```

**Expected performance:**
- Optimized: 3-4 minutes, $0.75-0.85
- Non-optimized: 10+ minutes, $1.06+

## Best Practices

- Focus on the last 100-200 lines of logs where errors typically appear
- Compare jobs from similar time periods and same runner tags
- Distinguish between flaky failures (intermittent) vs. deterministic
- Use `failure_reason` field for initial categorization, then analyze logs for details
- Use `gitlab` skill for broader repository operations (MRs, commits, issues)

## Common Failure Reasons

GitLab provides `failure_reason` field in job JSON:

- `script_failure` - Job script failed (exit code != 0)
- `stuck_or_timeout_failure` - Job timed out
- `runner_system_failure` - Runner infrastructure issue
- `missing_dependency_failure` - Required service not available
- `api_failure` - API request failed during job
- `runner_unsupported` - Runner doesn't support job requirements
- `stale_schedule` - Scheduled pipeline was stale
- `job_execution_timeout` - Job exceeded max execution time
- `archived_failure` - Project is archived
- `unmet_prerequisites` - Job prerequisites not met
- `scheduler_failure` - Scheduler error
- `data_integrity_failure` - Data integrity issue

**Use failure_reason for initial categorization, then analyze logs for details.**

## Troubleshooting Tips

**No logs available:**
- Job may still be running - check status first
- Logs may have been expired (check artifacts_expire_at)
- Job may have been canceled before producing logs
- Runner may have crashed before logs were uploaded

**Truncated logs:**
- GitLab has max trace size (default 4MB, configurable)
- Use job artifacts to capture full logs
- Look for "Job log exceeded limit" message
- Check runner logs for full output

**Job stuck in pending:**
- No available runners with matching tags
- Runner capacity exceeded
- Pipeline quota reached
- Protected branch requires specific runners

**Flaky tests:**
- Compare multiple runs of same job
- Look for race conditions in logs
- Check for timing-dependent assertions
- Review test isolation (shared state issues)

## Dependencies

**Required:** `glab` (install via `tools/glab/install.sh`)
**Optional:** `jq` (install via `tools/jq/install.sh`)

## State Management (Advanced)

For large datasets, scripts save results via `tools/memory/scripts/state.sh`. View saved state with `./scripts/view_state.sh`. Direct JSON output is recommended for typical use cases.

