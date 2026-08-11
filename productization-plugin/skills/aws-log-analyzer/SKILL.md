---
name: aws-log-analyzer
description: Troubleshoot and analyze logs from AWS CloudWatch Logs. This skill should be used when the user asks to investigate logs, troubleshoot application issues, query log groups, analyze error patterns, or perform log analysis for machines writing to AWS CloudWatch. Uses the AWS CLI for CloudWatch Logs operations.
allowed-tools: Bash(aws logs describe-log-groups:*),Bash(aws logs describe-log-streams:*),Bash(aws logs filter-log-events:*),Bash(aws logs start-query:*),Bash(aws logs get-query-results:*),Bash(aws logs tail:*),Bash(*/aws-log-analyzer/scripts/*.sh:*),Bash(*/tools/*/install.sh:*)
---

# AWS Log Analyzer

## Overview

Troubleshoot and analyze logs from AWS CloudWatch Logs - AWS's centralized logging service for applications and infrastructure.

**Prerequisites:**
- `aws` CLI is installed and configured
- User is already authenticated (via IAM credentials, SSO, or instance profile)
- Appropriate IAM permissions for CloudWatch Logs read operations

**Installation:**
Use the centralized tool installation scripts:

```bash
# Check and install AWS CLI (required)
../../../tools/aws-cli/install.sh

# Check and install jq (optional, recommended)
../../../tools/jq/install.sh
```

## Core Concepts

- **Log Group**: Container for log streams (typically one per application/service)
- **Log Stream**: Sequence of log events from a single source (e.g., instance, container)
- **Log Event**: Individual log entry with timestamp and message
- **CloudWatch Logs Insights**: SQL-like query language for advanced log analysis

## Analysis Philosophy

**Always follow this pattern:**
1. Start broad → identify the problem scope
2. Narrow down → focus on specific errors or patterns
3. Filter noise → exclude known non-critical errors
4. Analyze distribution → understand when errors occur

**Use CloudWatch Logs Insights for all error analysis** - it supports case-insensitive regex, which is essential because logs may contain "error", "Error", or "ERROR" in different formats.

## Output Format

**All scripts output JSON by default** to make results easy to parse programmatically by AI assistants and automation tools.

**⚠️ RECOMMENDATION: Use full JSON output for typical error analysis**

For most use cases, **direct JSON output is more efficient** than state management:
- ✅ Single round-trip - get all data in one call
- ✅ No state lookup complexity - data is immediately available
- ✅ Reliable - no session ID or file path issues
- ✅ For typical analyses (even 10K+ errors), JSON output is manageable (~30KB)

**Only use `--save-state` (via state management scripts) if:**
- You're analyzing 100K+ log entries
- The JSON output exceeds 100KB
- You need to reference the same data across multiple analysis steps over time

**Recommended approach - get all data in one call:**
```bash
# Run analysis and capture full JSON output
OUTPUT=$(./scripts/analyze_errors.sh <log-group> 24)

# Parse specific fields as needed
echo "$OUTPUT" | jq '.total_errors'
echo "$OUTPUT" | jq '.by_severity'
echo "$OUTPUT" | jq '.top_errors[:5]'
```

### JSON Output (Default)

```bash
# Default: JSON output to stdout, progress to stderr
./scripts/analyze_errors.sh /aws/app/myapp 24

# Output:
{
  "log_group": "/aws/app/myapp",
  "hours_analyzed": 24,
  "total_errors": "1247",
  "by_severity": {
    "critical": 15,
    "error": 1200,
    "warning": 25,
    "failed": 7
  },
  "top_errors": [
    {
      "message": "Connection timeout to database",
      "count": 342,
      "percentage": 27.43,
      "pattern": "Connection timeout to database"
    },
    ...
  ],
  "critical_errors": [...],
  "top_errors_by_pattern": [
    {
      "pattern": "Error at <TIMESTAMP>",
      "total_count": 450,
      "occurrences": 12,
      "examples": [
        {"message": "Error at 2026-02-06 15:30:45", "count": 120},
        {"message": "Error at 2026-02-06 16:45:12", "count": 95}
      ]
    },
    ...
  ],
  "hourly_distribution": [...],
  "comparison": null  // or populated if --compare-previous is used
}
```

**With additional flags:**

```bash
# Exclude noise patterns and compare with previous period
./scripts/analyze_errors.sh /aws/app/myapp 24 --exclude-noise --compare-previous

# Output includes comparison data:
{
  ...
  "comparison": {
    "current_period": {"total_errors": 1247, "hours": 24},
    "previous_period": {"total_errors": 1050, "hours": 24},
    "change": "+18.76%",
    "trend": "increasing"
  }
}
```

**Benefits:**
- **Structured data** - Easy to parse and extract specific fields
- **Clean separation** - Progress messages go to stderr, results to stdout
- **Consistent format** - All scripts use the same JSON structure pattern
- **AI-friendly** - Models can easily process and reason about JSON

### Human-Readable Output

Add `--human` flag for human-readable table/text format:

```bash
./scripts/analyze_errors.sh /aws/app/myapp 24 --human

# Output:
=== Error Analysis Results ===
Log Group: /aws/app/myapp
Total Errors: 1247

Top Errors by Frequency:
  342x: Connection timeout to database
  125x: Authentication failed...
  ...
```

### Parsing JSON Output

**In the model context:**
```bash
# Extract specific field
./scripts/analyze_errors.sh /aws/app/myapp 24 | jq '.total_errors'

# Count distinct error types
./scripts/analyze_errors.sh /aws/app/myapp 24 | jq '.top_errors | length'

# Get top 3 errors
./scripts/analyze_errors.sh /aws/app/myapp 24 | jq '.top_errors[:3]'
```

---

## State Management

**⚠️ IMPORTANT: State management is for advanced use cases only**

The state management system (`~/.aws-log-analyzer/state/`) is available for very large datasets or multi-step workflows, but is **NOT recommended for typical error analysis**.

**Shared Library:** This skill uses `productization-plugin/tools/memory/scripts/state.sh` - a shared state management library used across multiple skills.

**Why direct JSON output is better:**
- ✅ Simpler - no session IDs or file paths to manage
- ✅ Faster - single round-trip instead of save → view → parse
- ✅ More reliable - no file system dependencies
- ✅ Efficient even for 10K+ errors (~30KB JSON)

**Note:** `analyze_errors.sh` no longer supports the `--save-state` flag. Use direct JSON output instead (see examples above).

### Manual State Management (Advanced)

If you need state management for very large datasets (100K+ entries), you can manually save/load data:

```bash
# Capture output and save manually if needed
OUTPUT=$(./scripts/analyze_errors.sh <log-group> 24)
echo "$OUTPUT" > /tmp/analysis_result.json

# Later, load and parse
jq '.top_errors[:10]' /tmp/analysis_result.json
```

**View saved state:**

```bash
# List all saved states
./scripts/view_state.sh

# View specific state by ID
./scripts/view_state.sh analyze_errors_1707224567

# View latest state for an operation
./scripts/view_state.sh analyze_errors
```

### When to Use State

**Use `--save-state` when:**
- Working with the model and want to minimize token usage
- Results are large (thousands of log entries, many error types)
- Building multi-step workflows where later steps reference earlier results

**Don't use `--save-state` when:**
- Running scripts manually and want immediate full output
- Results are small and fit easily in context
- Doing one-off investigations

### Querying Saved State

**Once data is saved, you can extract specific information using jq:**

```bash
# Get the total error count
./scripts/view_state.sh analyze_errors | jq '.total_errors'

# Get top 5 errors with their counts
./scripts/view_state.sh analyze_errors | jq '.top_errors[0:5][] | {message: .message, count: .count}'

# Get only critical errors (count > 10)
./scripts/view_state.sh analyze_errors | jq '.critical_errors[] | select(.count > 10)'

# Get severity breakdown
./scripts/view_state.sh analyze_errors | jq '.by_severity'

# Get errors from a specific time bucket
./scripts/view_state.sh analyze_errors | jq '.hourly_distribution[] | select(.time_bucket | contains("2026-02-06T15"))'

# Extract error patterns (grouped by similarity)
./scripts/view_state.sh analyze_errors | jq '.top_errors_by_pattern[0:5]'

# Get all errors matching a specific pattern
./scripts/view_state.sh analyze_errors | jq '.top_errors[] | select(.pattern | contains("Connection"))'

# Get percentage of errors that are critical
./scripts/view_state.sh analyze_errors | jq '(.by_severity.critical / (.total_errors | tonumber) * 100)'

# Compare current vs previous period (if --compare-previous was used)
./scripts/view_state.sh analyze_errors | jq '.comparison'

# Get examples of a specific error pattern
./scripts/view_state.sh analyze_errors | jq '.top_errors_by_pattern[0].examples'
```

**Example workflow using saved state:**

```bash
# Step 1: Analyze errors with state saving
./scripts/analyze_errors.sh /aws/app/myapp 24 --save-state --exclude-noise

# Output:
# {
#   "operation": "analyze_errors",
#   "state_saved": true,
#   "state_id": "analyze_errors_1738858234",
#   "summary": {
#     "log_group": "/aws/app/myapp",
#     "total_errors": 1247,
#     "top_error_patterns": [...]
#   }
# }

# Step 2: Query specific details without re-running analysis
./scripts/view_state.sh analyze_errors | jq '.by_severity'
# Output: {"critical": 15, "error": 1200, "warning": 25, "failed": 7}

# Step 3: Get top 3 error patterns
./scripts/view_state.sh analyze_errors | jq '.top_errors_by_pattern[0:3]'

# Step 4: Find all errors with high frequency (> 50 occurrences)
./scripts/view_state.sh analyze_errors | jq '.top_errors[] | select(.count > 50)'
```

---

## Available Scripts

All operations are performed through the following scripts:

### State Management Scripts
- `view_state.sh` - View saved script outputs (for advanced workflows only)
  - **Note:** `analyze_errors.sh` no longer supports `--save-state` flag
  - State management is available through manual save/load if needed for very large datasets

### Discovery Scripts
- `list_log_groups.sh` - List available log groups
- `list_log_streams.sh` - List log streams within a group

### Analysis Scripts
- `analyze_errors.sh` - Complete error analysis (recommended for most cases)
  - Flags: `--human`, `--exclude-noise`, `--compare-previous`
  - Features: Severity classification, pattern grouping, trend analysis
  - **Output:** Full JSON by default (efficient for typical datasets)
- `find_recent_errors.sh` - Quick search for recent errors
- `run_insights_query.sh` - Execute custom CloudWatch Logs Insights queries
- `trace_request.sh` - Trace a request ID across multiple log groups

### Monitoring Scripts
- `tail_logs.sh` - Monitor logs in real-time

## Template Queries

Pre-built CloudWatch Logs Insights queries are available in `scripts/insights_queries.json`:

**Error Analysis:**
- `error_analysis.total_count` - Count total errors
- `error_analysis.by_message` - Group errors by message
- `error_analysis.unique_errors` - Find unique errors (excludes noise)
- `error_analysis.hourly_distribution` - Hourly error distribution
- `error_analysis.recent_errors` - Last 100 errors

**Performance Analysis:**
- `performance_analysis.slow_requests` - Requests slower than 1s
- `performance_analysis.latency_percentiles` - P50, P90, P99 latencies
- `performance_analysis.requests_per_minute` - Request rate

**Request Tracing:**
- `request_tracing.by_request_id` - Trace by request ID
- `request_tracing.by_user` - Trace by user ID

**Application Monitoring:**
- `application_monitoring.status_codes` - HTTP status code distribution
- `application_monitoring.error_rate` - Error rate percentage
- `application_monitoring.top_endpoints` - Most accessed endpoints

## Common Workflows

### Workflow 1: Analyze Errors in a Log Group

**User Request:** "Analyze errors for <log-group> in the last 24 hours"

**Execution Sequence:**
```bash
# Step 1: Run complete error analysis
./scripts/analyze_errors.sh <log-group-name> 24
```

**Output Provides:**
1. Total error count
2. Top error messages by frequency
3. Critical/unique errors (excludes noise)
4. Hourly error distribution

**Recommended approach - capture output and parse as needed:**
```bash
# Step 1: Run analysis and capture full JSON output
OUTPUT=$(./scripts/analyze_errors.sh <log-group-name> 24)

# Step 2: Extract specific fields
echo "$OUTPUT" | jq '.total_errors'
# Output: "1247"

echo "$OUTPUT" | jq '.by_severity'
# Output: {"critical": 15, "error": 1200, "warning": 25, "failed": 7}

echo "$OUTPUT" | jq '.top_errors[:3]'
# Output: Array of top 3 errors with counts and percentages

# Step 3: Get more details on specific errors if needed
./scripts/find_recent_errors.sh <log-group-name> 1 50
```

**Why this is efficient:**
- Single execution of analyze_errors.sh gets all data
- No round-trips to view state
- No session ID management
- For typical datasets (even 10K errors), JSON is ~30KB - completely manageable
- Parse different fields from the same output as needed

---

### Workflow 2: Investigate Errors (Unknown Log Group)

**User Request:** "Check for errors in my application"

**Execution Sequence:**
```bash
# Step 1: Find the log group
./scripts/list_log_groups.sh /aws/application

# Step 2: Analyze errors in the identified log group
./scripts/analyze_errors.sh <log-group-name> 24
```

---

### Workflow 3: Trace a Request Across Services

**User Request:** "Trace request ID abc-123 through all services"

**Execution Sequence:**
```bash
# Single command to search all log groups with a common prefix
./scripts/trace_request.sh abc-123 /aws/myapp 24
```

**Output:** Shows all log entries containing the request ID, sorted by timestamp, across all log groups.

---

### Workflow 4: Monitor for Specific Errors in Real-Time

**User Request:** "Watch for OutOfMemory errors in real-time"

**Execution Sequence:**
```bash
# Tail logs with filter pattern
./scripts/tail_logs.sh <log-group-name> "OutOfMemoryError" 1h
```

**Time formats:** `1h`, `30m`, `2d`, `5s`

---

### Workflow 5: Custom Error Analysis

**User Request:** "Find all authentication failures in the last 6 hours"

**Execution Sequence:**
```bash
# Step 1: Run custom Insights query
./scripts/run_insights_query.sh <log-group-name> 6 \
  'fields @timestamp, @message | filter @message like /(?i)(auth|authentication)/ and @message like /(?i)(fail|denied)/ | sort @timestamp desc | limit 100'
```

**Alternative using template query:**
```bash
# Step 1: Load query from template (if you have one defined)
QUERY=$(jq -r '.custom_queries.auth_failures' scripts/insights_queries.json)

# Step 2: Run the query
./scripts/run_insights_query.sh <log-group-name> 6 "$QUERY"
```

---

### Workflow 6: Analyze Performance Issues

**User Request:** "Find slow database queries in the last 24 hours"

**Execution Sequence:**
```bash
# Step 1: Use performance template query
QUERY=$(jq -r '.performance_analysis.slow_requests' scripts/insights_queries.json)

# Step 2: Run the query
./scripts/run_insights_query.sh <log-group-name> 24 "$QUERY"
```

**For RDS slow query logs:**
```bash
# Custom query for RDS slow query format
./scripts/run_insights_query.sh /aws/rds/instance/mydb/slowquery 24 \
  'fields @timestamp, query_time, lock_time, rows_examined, @message | parse @message /Query_time: (?<qt>[0-9.]+)\s+Lock_time: (?<lt>[0-9.]+).*\n(?<query>.*)/ | filter qt > 1.0 | sort qt desc | limit 20'
```

---

### Workflow 7: Investigate Recent Activity

**User Request:** "What's happening in my application right now?"

**Execution Sequence:**
```bash
# Step 1: List recent log streams to see activity
./scripts/list_log_streams.sh <log-group-name> 10

# Step 2: Tail recent logs
./scripts/tail_logs.sh <log-group-name> "" 10m

# Step 3: If errors are seen, analyze them
./scripts/analyze_errors.sh <log-group-name> 1
```

---

### Workflow 8: Compare Error Rates

**User Request:** "Has the error rate increased in the last hour?"

**Execution Sequence:**
```bash
# Step 1: Get errors from last hour
./scripts/analyze_errors.sh <log-group-name> 1

# Step 2: Get errors from previous hour for comparison
./scripts/run_insights_query.sh <log-group-name> 2 \
  'fields @timestamp | filter @message like /(?i)(error|fail|exception|critical)/ | stats count() as error_count by bin(1h)'
```

---

## Performance Optimization

**When combining this skill with other skills (especially gitlab-job-analyzer):**

See the complete optimization guide in the main CLAUDE.md documentation under "Performance Optimization for Cross-Skill Analysis".

**Key optimizations:**
1. **Parallel execution** - Run GitLab + AWS analysis simultaneously in one message
2. **Parse JSON once** - Capture output, parse multiple times with jq (don't re-run scripts)
3. **Smart targeting** - Analyze only log groups for failing runners/components identified in GitLab analysis
4. **Direct JSON output** - For typical analyses (10K+ errors), direct JSON is more efficient than state management

**Example - Optimized cross-skill analysis:**
```bash
# SINGLE MESSAGE - Parallel execution:
# Tool 1: AWS log analysis for component 1
./aws-log-analyzer/scripts/analyze_errors.sh /aws/app/component1 24

# Tool 2: AWS log analysis for component 2 (runs in parallel)
./aws-log-analyzer/scripts/analyze_errors.sh /aws/app/component2 24

# Tool 3: GitLab analysis (runs in parallel)
./gitlab-job-analyzer/scripts/analyze_recent_jobs.sh owner/repo --hours 24

# Then parse AWS output multiple ways without re-running:
echo "$AWS_OUTPUT" | jq '.total_errors'
echo "$AWS_OUTPUT" | jq '.by_severity'
echo "$AWS_OUTPUT" | jq '.top_errors[:5]'
echo "$AWS_OUTPUT" | jq '.hourly_distribution'
```

**Expected performance:**
- Optimized: 3-4 minutes, $0.75-0.85
- Non-optimized: 10+ minutes, $1.06+

## Best Practices

### 1. Always Use Case-Insensitive Patterns

**Logs may contain "error", "Error", or "ERROR"** - always use case-insensitive regex in CloudWatch Logs Insights queries:
- ✅ Use: `/(?i)error/` in Insights queries
- ❌ Avoid: `"ERROR"` filter patterns (case-sensitive)

### 2. Start with analyze_errors.sh

**For most error investigations**, use `analyze_errors.sh` first:
- Provides complete overview in one command
- Uses case-insensitive matching
- Excludes known noise patterns
- Shows time distribution

### 3. Use Template Queries

**Leverage `scripts/insights_queries.json`** for common analysis patterns:
- Pre-tested queries for common scenarios
- Easy to customize
- Consistent results

### 4. Filter Out Noise

**Noise patterns are defined in `scripts/noise-patterns.txt`:**
- GitLab Runner: `file already closed`
- AWS SDK throttling: `SlowDown`, `ThrottlingException`, `TooManyRequestsException`
- Rate limiting: `RequestLimitExceeded`, `Throttled`, `RequestThrottled`
- Provisioning: `ProvisionedThroughputExceededException`

**Usage:**
```bash
# Enable noise filtering (uses patterns from noise-patterns.txt)
./scripts/analyze_errors.sh <log-group> 24 --exclude-noise

# View all noise patterns
cat scripts/noise-patterns.txt

# Add custom patterns (edit the file)
echo "MyCustomNoisePattern" >> scripts/noise-patterns.txt
```

**Note:** Patterns are applied as case-insensitive regex patterns in CloudWatch Logs Insights queries.

### 5. Narrow Time Ranges for Performance

**Time range guidelines:**
- Initial investigation: 1-6 hours
- Trend analysis: 24 hours
- Historical analysis: 7 days maximum

**Narrower time ranges:**
- Reduce CloudWatch Logs Insights costs
- Improve query performance
- Faster results

### 6. Leverage Pattern Grouping

**Error messages often differ only in timestamps, IPs, or IDs:**
- "Error at 2026-02-06 15:30:45" vs "Error at 2026-02-06 16:45:12"
- "Connection failed to 192.168.1.100" vs "Connection failed to 192.168.1.200"

**Pattern normalization groups similar errors automatically:**
```bash
# The output includes both individual errors and pattern-grouped errors
./scripts/analyze_errors.sh <log-group> 24

# Query pattern-grouped errors from saved state
./scripts/view_state.sh analyze_errors | jq '.top_errors_by_pattern'
```

**Pattern output structure:**
```json
{
  "pattern": "Error at <TIMESTAMP>",
  "total_count": 450,
  "occurrences": 12,
  "examples": [
    {"message": "Error at 2026-02-06 15:30:45", "count": 120},
    {"message": "Error at 2026-02-06 16:45:12", "count": 95}
  ]
}
```

**Benefits:**
- See the "true" error count (not inflated by timestamp variations)
- Identify systemic issues vs one-time errors
- Reduce noise from UUID/IP variations

### 7. Use Tracing for Distributed Systems

**For microservices/distributed architectures:**
- Use `trace_request.sh` to follow requests across services
- Ensure request IDs are logged consistently
- Search across all related log groups with a common prefix

---

## Troubleshooting Guide

### Problem: No Errors Found

**Cause:** Case-sensitive filter patterns don't match logs

**Solution:**
```bash
# ✅ Use Insights-based scripts (case-insensitive)
./scripts/analyze_errors.sh <log-group-name> 24
./scripts/find_recent_errors.sh <log-group-name> 1
```

---

### Problem: Too Many Results

**Cause:** Broad search across large time range

**Solution:**
```bash
# Step 1: Narrow time range
./scripts/analyze_errors.sh <log-group-name> 1  # Last hour instead of 24

# Step 2: Filter by specific pattern
./scripts/run_insights_query.sh <log-group-name> 1 \
  'fields @timestamp, @message | filter @message like /(?i)OutOfMemory/ | limit 50'
```

---

### Problem: Query Timeout

**Cause:** Query too complex or time range too large

**Solution:**
```bash
# Step 1: Reduce time range
./scripts/analyze_errors.sh <log-group-name> 1  # Instead of 24

# Step 2: Simplify query (remove complex parsing)

# Step 3: Add more specific filters early in the query
./scripts/run_insights_query.sh <log-group-name> 1 \
  'fields @timestamp, @message | filter @message like /(?i)specific_error/ | stats count()'
```

---

### Problem: Log Group Not Found

**Cause:** Typo or wrong region

**Solution:**
```bash
# Step 1: List all log groups to verify name
./scripts/list_log_groups.sh

# Step 2: Search with prefix
./scripts/list_log_groups.sh /aws/application

# Step 3: Verify AWS region is correct (check AWS CLI config)
```

---

## Integration with Other Skills

### With Kubernetes Skill

**Workflow: Correlate K8s pod events with application logs**

```bash
# Step 1: Get pod name from kubernetes skill
# (kubernetes skill command)

# Step 2: Search CloudWatch logs for that pod
./scripts/trace_request.sh <pod-name> /aws/application 24
```

### With GitLab Skill

**Workflow: Investigate deployment-related errors**

```bash
# Step 1: Get commit SHA from gitlab skill
# (gitlab skill command)

# Step 2: Search logs for that deployment
./scripts/trace_request.sh <commit-sha> /aws/application 24

# Step 3: Analyze errors during deployment window
./scripts/analyze_errors.sh /aws/application/myapp 1
```

---

## Common Log Group Patterns

**AWS Services:**
```
/aws/lambda/<function-name>
/aws/rds/instance/<instance-id>/*
/aws/ecs/containerinsights/<cluster>
/aws/eks/<cluster>/cluster
/aws/apigateway/<api-id>/<stage>
```

**Application Logs:**
```
/aws/application/<app-name>
/var/log/messages
/aws/containerinsights/<cluster>/*
```

---

## Quick Reference

### Most Common Commands

**All commands output JSON by default. Add `--human` for human-readable format.**

```bash
# Analyze errors (JSON output) - RECOMMENDED
OUTPUT=$(./scripts/analyze_errors.sh <log-group> 24)
echo "$OUTPUT" | jq '.total_errors'

# Analyze errors (human-readable)
./scripts/analyze_errors.sh <log-group> 24 --human

# Analyze errors with noise filtering and comparison
./scripts/analyze_errors.sh <log-group> 24 --exclude-noise --compare-previous

# Find recent errors
./scripts/find_recent_errors.sh <log-group> 1

# Trace a request
./scripts/trace_request.sh <request-id> <log-group-prefix> 24

# Monitor in real-time
./scripts/tail_logs.sh <log-group>

# List log groups
./scripts/list_log_groups.sh

# Custom query
./scripts/run_insights_query.sh <log-group> 24 '<insights-query>'

# Parse JSON output
./scripts/analyze_errors.sh <log-group> 24 | jq '.total_errors'
./scripts/list_log_groups.sh | jq '.log_groups[].name'
```

### Time Formats

**For most scripts (hours):**
- `1` = last 1 hour
- `24` = last 24 hours
- `168` = last 7 days

**For tail_logs.sh (relative time):**
- `1h` = last hour
- `30m` = last 30 minutes
- `2d` = last 2 days

---

## Dependencies

**Required:**
- `aws` CLI v2 (recommended) or v1
  - Install: `../../../tools/aws-cli/install.sh`
  - Check: `../../../tools/aws-cli/install.sh --check`

**Optional (recommended):**
- `jq` - JSON processor for parsing outputs
  - Install: `../../../tools/jq/install.sh`
  - Check: `../../../tools/jq/install.sh --check`

All installation scripts:
- Auto-detect architecture (Linux x86_64, ARM64)
- No root access required
- Idempotent (safe to run multiple times)
- Version tracking for Renovate updates
