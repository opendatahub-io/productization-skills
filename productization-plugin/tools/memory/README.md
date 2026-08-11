# Memory/State Management Tool

## Overview

The memory/state management tool provides a shared library for Productization skills to persist analysis results across multiple steps, reducing model token usage and API round-trips for very large datasets.

## What is it?

A lightweight, session-based state management system that allows skills to:
- **Save** analysis results to disk (JSON format)
- **Retrieve** results later without re-running expensive operations
- **Query** specific fields from saved data using `jq`
- **Share state** across multiple analysis steps in the same session

## Why does it exist?

### The Problem

When analyzing large datasets, returning all data directly to the model can be inefficient:

```bash
# ❌ Problem: Returning 500KB of log analysis results
# - High token usage (500KB → model context)
# - Multiple round-trips to re-fetch same data
# - Expensive API calls repeated unnecessarily
```

### The Solution

State management allows "get once, query many times" workflow:

```bash
# ✅ Solution: Save once, query multiple times
# 1. Run analysis and save state (returns summary only)
OUTPUT=$(./analyze_errors.sh /aws/logs 24 --save-state)
# Returns: {"state_id": "analyze_errors_123", "summary": "1247 errors"}

# 2. Query specific fields as needed (no re-analysis)
./view_state.sh analyze_errors | jq '.total_errors'        # ~100 tokens
./view_state.sh analyze_errors | jq '.top_errors[:5]'      # ~500 tokens
./view_state.sh analyze_errors | jq '.by_severity'         # ~200 tokens
```

**Benefit:** Instead of 500KB in one call, we make targeted queries totaling ~5-10KB.

## Architecture

### Directory Structure

```
tools/memory/
├── README.md              # This file
└── scripts/
    ├── state.sh           # Core state management library
    └── view_state.sh      # State viewer utility
```

### How It Works

**1. Session-based Storage**

Each Claude Code session gets a unique session directory:

```
~/.{skill-name}/state/
├── metadata.json                          # Session index
├── .current_session                       # Active session ID
└── session_20260209_143045/               # Session directory
    ├── analyze_errors_1707483645.json     # Saved state
    ├── analyze_pipeline_1707483698.json   # Saved state
    └── trace_request_1707483712.json      # Saved state
```

**2. State Object Format**

Each saved state is a JSON object:

```json
{
  "state_id": "analyze_errors_1707483645",
  "session_id": "session_20260209_143045",
  "operation": "analyze_errors",
  "timestamp": 1707483645,
  "summary": "Analyzed 1247 errors in /aws/app/myapp",
  "data": {
    "log_group": "/aws/app/myapp",
    "total_errors": 1247,
    "top_errors": [...],
    "by_severity": {...},
    ...
  }
}
```

**3. Skills Maintain Separate State**

Each skill has its own state directory via environment variable:

```bash
# aws-log-analyzer
SKILL_STATE_DIR="${AWS_LOG_ANALYZER_STATE_DIR:-$HOME/.aws-log-analyzer/state}"

# glab-job-analyzer
SKILL_STATE_DIR="${GLAB_JOB_ANALYZER_STATE_DIR:-$HOME/.glab-job-analyzer/state}"

# my-new-skill
SKILL_STATE_DIR="${MY_NEW_SKILL_STATE_DIR:-$HOME/.my-new-skill/state}"
```

This ensures skills don't interfere with each other's state.

## When to Use State Management

### ✅ Use State When:

1. **Very large datasets** - Analysis produces >100KB of JSON
2. **Multi-step workflows** - Later steps need to reference earlier results
3. **Expensive operations** - Re-running analysis is costly (time/API calls)
4. **Complex queries** - Need to query same data multiple different ways

**Example:**
```bash
# Analyzing 100K+ log entries across 50+ error patterns
# - Initial analysis: 5 minutes, 2M tokens
# - Save state: Returns 500-token summary
# - Query as needed: 100-1000 tokens per query
```

### ❌ Don't Use State When:

1. **Small datasets** - Results are <100KB JSON (just return directly!)
2. **One-time queries** - Single analysis, single question
3. **Simple workflows** - No need to reference previous results
4. **Real-time data** - Data changes frequently (state becomes stale)

**Example:**
```bash
# Analyzing last 24 hours of errors (~30KB JSON)
# - Just return JSON directly: 1 call, 30KB
# - No state needed: Simple, efficient, reliable
```

## Current Philosophy: JSON-First

**Important:** As of the latest refactoring, **both aws-log-analyzer and glab-job-analyzer follow a JSON-first approach** where state management is **optional and rarely needed**.

### Recommended Approach

```bash
# ✅ RECOMMENDED: Direct JSON output (efficient for typical use cases)
OUTPUT=$(./scripts/analyze_pipeline.sh owner/repo 12345)
echo "$OUTPUT" | jq '.job_statistics'
echo "$OUTPUT" | jq '.failed_jobs[].name'

# Even for ~100KB JSON output, this is more efficient than state management!
```

### When State Actually Helps

```bash
# Only for VERY large datasets (>500KB) or multi-step workflows
./scripts/analyze_pipeline.sh owner/repo 12345 --save-state
# Returns: {"state_id": "analyze_pipeline_123", "summary": {...}}

# Later steps query without re-running
./scripts/view_state.sh analyze_pipeline | jq '.failed_jobs[] | select(.stage == "test")'
./scripts/view_state.sh analyze_pipeline | jq '.common_error_patterns'
```

## Usage Guide

### For Skill Developers

**1. Source the library in your script:**

```bash
#!/bin/bash
# skills/my-skill/scripts/my_script.sh

set -euo pipefail

# Set skill-specific state directory
SKILL_STATE_DIR="${MY_SKILL_STATE_DIR:-$HOME/.my-skill/state}"

# Source shared state library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../tools/memory/scripts/state.sh"

# Now you can use state functions
```

**2. Save state from your script:**

```bash
# Run expensive analysis
ANALYSIS_DATA=$(perform_expensive_analysis)

# Save to state
STATE_ID=$(save_state "my_operation" "$ANALYSIS_DATA" "Analysis of X completed")

# Return minimal summary to model
jq -n \
    --arg state_id "$STATE_ID" \
    --argjson summary "$(echo "$ANALYSIS_DATA" | jq '{total: .total, key_metrics: .metrics}')" \
    '{
        operation: "my_operation",
        state_saved: true,
        state_id: $state_id,
        summary: $summary
    }'
```

**3. Create a view_state.sh wrapper:**

```bash
#!/bin/bash
# skills/my-skill/scripts/view_state.sh

set -euo pipefail

SKILL_STATE_DIR="${MY_SKILL_STATE_DIR:-$HOME/.my-skill/state}"
source "$SCRIPT_DIR/../../../tools/memory/scripts/state.sh"

if [ $# -eq 0 ]; then
    list_states
    exit 0
fi

STATE_REF="$1"

if [[ "$STATE_REF" == *"_"* ]]; then
    # State ID
    SESSION_ID=$(get_session_id)
    STATE_FILE="$STATE_DIR/$SESSION_ID/${STATE_REF}.json"
    [ -f "$STATE_FILE" ] && cat "$STATE_FILE" | jq . || echo "State not found" >&2
else
    # Operation name
    get_state_by_operation "$STATE_REF"
fi
```

### For Model/AI Usage

**View saved state:**

```bash
# List all states in current session
./scripts/view_state.sh

# View latest state for an operation
./scripts/view_state.sh analyze_errors

# View specific state by ID
./scripts/view_state.sh analyze_errors_1707483645

# Query specific fields
./scripts/view_state.sh analyze_errors | jq '.total_errors'
./scripts/view_state.sh analyze_errors | jq '.top_errors[:10]'
./scripts/view_state.sh analyze_errors | jq '.by_severity.critical'
```

## Available Functions

The `state.sh` library provides these functions:

### Core Functions

**`init_state()`**
- Initializes state directory and metadata
- Called automatically by other functions

**`get_session_id()`**
- Returns current session ID
- Creates new session if none exists

**`new_session()`**
- Explicitly creates a new session
- Returns new session ID

**`save_state <operation> <data> [summary]`**
- Saves state for an operation
- Returns state ID
- Example: `save_state "analyze_errors" "$JSON_DATA" "Analyzed 1247 errors"`

**`get_state <state_id>`**
- Retrieves state by exact state ID
- Returns full state object as JSON

**`get_state_by_operation <operation>`**
- Retrieves latest state for operation name
- Returns full state object as JSON
- Example: `get_state_by_operation "analyze_errors"`

**`get_state_summary <state_id>`**
- Returns only the summary field
- Useful for quick status checks

**`list_states()`**
- Lists all states in current session
- Shows state ID, operation, timestamp, summary

**`clean_old_sessions [keep_count]`**
- Removes old sessions (default: keeps last 5)
- Helps manage disk usage

## Examples

### Example 1: Large Log Analysis

```bash
#!/bin/bash
# Analyze 100K+ log entries

SKILL_STATE_DIR="${AWS_LOG_ANALYZER_STATE_DIR:-$HOME/.aws-log-analyzer/state}"
source "../../../tools/memory/scripts/state.sh"

LOG_GROUP="$1"
HOURS="$2"

# Expensive analysis
FULL_DATA=$(aws logs insights ... | complex_processing)

# Save state
STATE_ID=$(save_state "analyze_errors" "$FULL_DATA" "Analyzed errors in $LOG_GROUP")

# Return minimal summary
jq -n \
    --arg state_id "$STATE_ID" \
    --arg log_group "$LOG_GROUP" \
    --argjson total "$(echo "$FULL_DATA" | jq '.total_errors')" \
    '{
        operation: "analyze_errors",
        state_saved: true,
        state_id: $state_id,
        log_group: $log_group,
        total_errors: $total
    }'
```

**Query later:**
```bash
# Get top 20 errors
./view_state.sh analyze_errors | jq '.top_errors[:20]'

# Get critical errors only
./view_state.sh analyze_errors | jq '.critical_errors'

# Get hourly distribution
./view_state.sh analyze_errors | jq '.hourly_distribution'
```

### Example 2: Multi-Step Pipeline Analysis

```bash
# Step 1: Analyze entire pipeline (saves state)
./analyze_pipeline.sh owner/repo 12345 --save-state
# Returns: {"state_id": "analyze_pipeline_123", "summary": {...}}

# Step 2: Query failed jobs
./view_state.sh analyze_pipeline | jq '.failed_jobs'

# Step 3: Deep dive on specific job
JOB_ID=$(./view_state.sh analyze_pipeline | jq -r '.failed_jobs[0].id')
./compare_job_logs.sh owner/repo $PREV_JOB_ID $JOB_ID

# Step 4: Check dependencies
./view_state.sh analyze_pipeline | jq '.blocked_jobs'
```

## State Lifecycle

```
┌─────────────────────────────────────────────────────┐
│ Claude Code Session Starts                          │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│ Session Created: session_20260209_143045            │
│ Location: ~/.{skill}/state/session_20260209_143045/ │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│ Operations Save State:                               │
│ - analyze_errors_1707483645.json                     │
│ - analyze_pipeline_1707483698.json                   │
│ - trace_request_1707483712.json                      │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│ Model Queries State:                                 │
│ - view_state.sh analyze_errors                       │
│ - jq '.top_errors[:10]'                              │
│ - jq '.by_severity'                                  │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│ Session Ends                                         │
│ State Persists: Available in next session           │
└─────────────────────────────────────────────────────┘
```

## Best Practices

### 1. Prefer Direct JSON Output

**For typical use cases (<100KB JSON), return data directly:**

```bash
# ✅ Efficient and simple
./analyze_pipeline.sh owner/repo 12345 | jq '.job_statistics'
```

**Not:**

```bash
# ❌ Unnecessary complexity for small datasets
./analyze_pipeline.sh owner/repo 12345 --save-state
./view_state.sh analyze_pipeline | jq '.job_statistics'
```

### 2. Include Operation Context in Summary

```bash
# ✅ Good: Descriptive summary
save_state "analyze_errors" "$DATA" "Analyzed 1247 errors in /aws/app/myapp (last 24h)"

# ❌ Bad: Generic summary
save_state "analyze_errors" "$DATA" "Done"
```

### 3. Clean Up Old Sessions

```bash
# Periodically clean old sessions (keep last 5)
clean_old_sessions 5
```

### 4. Use Meaningful Operation Names

```bash
# ✅ Good: Descriptive, unique
save_state "analyze_errors_myapp_20260209" "$DATA" "..."

# ❌ Bad: Generic, conflicts with other operations
save_state "data" "$DATA" "..."
```

### 5. Document When State is Used

In skill documentation, clearly indicate if/when state management is used:

```markdown
## Output Format

**Default: JSON output to stdout (recommended for typical use)**

For very large datasets (>100KB), use `--save-state`:
./analyze_errors.sh <log-group> 24 --save-state
```

## Integration with Existing Skills

### aws-log-analyzer

**State directory:** `~/.aws-log-analyzer/state/`

**Usage:**
```bash
# State management available but not recommended for typical use
# Prefer direct JSON output for most analyses
./scripts/view_state.sh  # List saved states (if any)
```

### glab-job-analyzer

**State directory:** `~/.glab-job-analyzer/state/`

**Usage:**
```bash
# State management available but not recommended for typical use
# Prefer direct JSON output from analyze_pipeline.sh
./scripts/view_state.sh  # List saved states (if any)
```

## Troubleshooting

### State not found

**Problem:** `Error: State not found: analyze_errors`

**Solution:**
```bash
# List all available states
./view_state.sh

# Check current session
ls ~/.{skill-name}/state/session_*/
```

### State directory permission error

**Problem:** `Permission denied: ~/.aws-log-analyzer/state/`

**Solution:**
```bash
# Check permissions
ls -la ~/.aws-log-analyzer/

# Fix permissions
chmod 755 ~/.aws-log-analyzer/state/
```

### Stale state data

**Problem:** State contains old data

**Solution:**
```bash
# Start new session
new_session

# Or manually clean old sessions
clean_old_sessions 1  # Keep only latest session
```

## Future Enhancements

Potential improvements for the memory/state management system:

1. **Automatic cleanup** - TTL-based session expiration
2. **Compression** - Compress large state files automatically
3. **Cross-skill state** - Share state between related skills (with explicit opt-in)
4. **State snapshots** - Save/restore entire session state
5. **State migration** - Tools to migrate state between versions

## Contributing

When adding new state management features:

1. **Keep it simple** - State should be transparent and easy to understand
2. **Maintain isolation** - Each skill's state should remain separate
3. **Document clearly** - Update this README with new features
4. **Test thoroughly** - Ensure backward compatibility

## Summary

The memory/state management tool provides a **lightweight, optional** system for persisting analysis results across multiple steps.

**Key Points:**
- ✅ **Use for:** Very large datasets (>100KB), multi-step workflows
- ❌ **Don't use for:** Typical analyses (<100KB), one-time queries
- 📊 **Current approach:** JSON-first (direct output preferred)
- 🔧 **Location:** `productization-plugin/tools/memory/scripts/`
- 🎯 **Purpose:** Reduce token usage for large datasets, enable multi-step workflows

For most use cases, **direct JSON output is simpler and more efficient** than state management.
