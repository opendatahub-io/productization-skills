---
name: jira-utilities
description: Jira utilities for reading issues, searching with JQL, creating issues, updating fields, linking issues, and fetching sprint information using the official Atlassian CLI (acli). Use this skill when the user asks about Jira issues (e.g. "show my open tickets", "get cards assigned to me", "create a Jira issue", "find bugs in project X") or when another skill needs to interact with Jira. Supports Jira Cloud only.
compatibility: Requires JIRA_SITE, JIRA_TOKEN, and JIRA_EMAIL environment variables. jq must be installed.
allowed-tools: Bash(*/jira-utilities/scripts/*.sh:*)
---

# Jira Utilities

Generic helper utilities for common Jira Cloud operations via the official Atlassian CLI (`acli`).

## Why acli?

`acli` is the first-party Atlassian CLI, officially maintained and distributed by Atlassian. It wraps the Jira REST API with a consistent interface and built-in JSON output.

Fields that `acli` does not expose as CLI flags (priority, components, team UUID, activity-type custom fields) are applied transparently via a follow-up REST API PATCH inside the wrapper scripts — so no functionality is lost compared to the previous Python implementation.

## Prerequisites

**Required environment variables:**
- `JIRA_SITE` - Atlassian site hostname (e.g., `yourorg.atlassian.net`)
- `JIRA_TOKEN` - API token from Atlassian account settings → Security → API tokens
- `JIRA_EMAIL` - Your Atlassian account email

**Required tools:**
- `acli` — install via `../../../tools/acli/install.sh`
- `jq` — install via `../../../tools/jq/install.sh`

No Python or pip dependencies.

## Authentication

`acli` requires a one-time login per session. All scripts call `ensure_auth` automatically, which runs:

```bash
echo "$JIRA_TOKEN" | acli jira auth login \
  --site "$JIRA_SITE" \
  --email "$JIRA_EMAIL" \
  --token
```

You can also run it explicitly:

```bash
./scripts/setup_auth.sh
```

Credentials are stored in `~/.config/acli/` and persist for the session.

## Scripts

### Get Issue

**Script:** `scripts/get_issue.sh`

**Usage:**
```bash
./scripts/get_issue.sh <issue_key>
```

**Example:**
```bash
./scripts/get_issue.sh PROJ-123
```

**Output:** JSON issue object.

---

### Search Issues

**Script:** `scripts/search_issues.sh`

**Usage:**
```bash
./scripts/search_issues.sh '<jql>'
./scripts/search_issues.sh --search KEYWORD [--project KEY]
./scripts/search_issues.sh --epic EPIC-KEY
```

**Options:**
- `jql` - JQL query string (mutually exclusive with `--search` / `--epic`)
- `--search` - Plain keyword; builds `text ~ "KEYWORD"` JQL automatically
- `--project` - Restrict `--search` to a specific project key
- `--epic` - Fetch all children of an Epic; covers both next-gen (`parent`) and classic (`Epic Link`) project types
- `--max-results N` - Max results (default: 50; use `0` to paginate all)
- `--fields f1,f2` - Comma-separated fields to include
- `--format json|table` - Output format (default: json)

**Examples:**
```bash
# Open issues in a project
./scripts/search_issues.sh 'project = PROJ AND status = "Open"'

# Keyword search scoped to a project, table output
./scripts/search_issues.sh --search "login timeout" --project MYPROJ --format table

# All children of an Epic
./scripts/search_issues.sh --epic PROJ-42

# Paginate all results
./scripts/search_issues.sh 'project = PROJ AND priority = High' --max-results 0
```

---

### Create Issue

**Script:** `scripts/create_issue.sh`

**Usage:**
```bash
./scripts/create_issue.sh <project> <summary> [options]
```

**Options:**
- `project` - Jira project key (e.g., `PROJ`)
- `summary` - Issue title/summary
- `--description TEXT` - Issue description
- `--issuetype TYPE` - Issue type (default: `Task`)
- `--priority NAME` - Priority name (e.g., `High`, `Critical`); applied via REST PATCH
- `--labels l1,l2` - Comma-separated labels
- `--assignee ID` - Assignee account ID, email, or `@me`
- `--component c1,c2` - Comma-separated component names; applied via REST PATCH
- `--team UUID` - Team UUID for `customfield_10001`; applied via REST PATCH
- `--epic KEY` - Parent epic key (e.g., `PROJ-42`)
- `--activity-type TYPE` - `customfield_10464`; applied via REST PATCH. One of:
  `Tech Debt & Quality`, `New Features`, `Learning & Enablement`

**Examples:**
```bash
# Basic task
./scripts/create_issue.sh PROJ "Fix login timeout"

# Bug with priority and labels
./scripts/create_issue.sh PROJ "Login fails after 5 minutes" \
  --issuetype Bug \
  --priority High \
  --description "Users report session expiry errors." \
  --labels "backend,auth"

# Full task with custom fields
./scripts/create_issue.sh PROJ "Implement login page" \
  --epic PROJ-42 \
  --team "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" \
  --assignee "user@example.com" \
  --component "My Team" \
  --activity-type "New Features"
```

**Output:** JSON from acli with the created issue key.

> **Key extraction:** The JSON contains many nested `"key"` fields (e.g. inside `statusCategory`). Always use `jq -r '.key'` to extract the top-level issue key — never `grep '"key"' | head -1`:
> ```bash
> KEY=$(./scripts/create_issue.sh PROJ "My issue" 2>/dev/null | jq -r '.key')
> echo "Created: $KEY"
> ```

---

### Update Issue

**Script:** `scripts/update_issue.sh`

**Usage:**
```bash
./scripts/update_issue.sh <issue_key> [options]
```

**Options:**
- `--summary TEXT` - New summary
- `--description TEXT` - New description
- `--priority NAME` - New priority; applied via REST PATCH
- `--assignee ID` - New assignee account ID or email
- `--labels l1,l2` - New labels, comma-separated (replaces existing)

**Examples:**
```bash
# Escalate priority
./scripts/update_issue.sh PROJ-123 --priority Critical

# Update summary and labels
./scripts/update_issue.sh PROJ-123 \
  --summary "Fix login timeout (production blocker)" \
  --labels "backend,auth,blocker"
```

**Output:** `{"updated": "PROJ-123"}`

---

### Link Issues

**Script:** `scripts/link_issues.sh`

**Usage:**
```bash
./scripts/link_issues.sh <inward_key> <outward_key> [--link-type TYPE]
```

**Options:**
- `--link-type TYPE` - Relationship type (default: `Relates`)
  Common types: `Blocks`, `Duplicates`, `Relates`, `Clones`
  List all: `acli jira workitem link type`

**Examples:**
```bash
./scripts/link_issues.sh PROJ-123 PROJ-456 --link-type Blocks
./scripts/link_issues.sh PROJ-789 PROJ-123 --link-type Duplicates
```

**Output:** `{"linked": ["PROJ-123", "PROJ-456"], "type": "Blocks"}`

---

### Get Board

**Script:** `scripts/get_board.sh`

**Usage:**
```bash
./scripts/get_board.sh <project> [options]
```

**Options:**
- `--name SUBSTR` - Filter boards by name substring (case-insensitive)
- `--type TYPE` - Filter by board type: `scrum` or `kanban`
- `--first` - Return only the first match as a single JSON object

**Examples:**
```bash
./scripts/get_board.sh MYPROJ
./scripts/get_board.sh MYPROJ --name "My Team" --type scrum --first
```

**Output:** JSON array `[{id, name, type}]` or single object with `--first`.

---

### Get Sprint

**Script:** `scripts/get_sprint.sh`

**Usage:**
```bash
# By board ID
./scripts/get_sprint.sh <board_id> [--state STATE]

# By project key (board auto-discovery)
./scripts/get_sprint.sh --project KEY [--board-name NAME] [--board-type TYPE] [--state STATE]
```

**Options:**
- `--state STATE` - Sprint state: `active`, `future`, or `closed` (default: `active`)
- `--project KEY` - Project key; triggers board discovery
- `--board-name NAME` - Name filter for board discovery disambiguation
- `--board-type TYPE` - Board type for discovery: `scrum` or `kanban` (default: `scrum`)

**Examples:**
```bash
./scripts/get_sprint.sh 42
./scripts/get_sprint.sh 42 --state future
./scripts/get_sprint.sh --project MYPROJ
./scripts/get_sprint.sh --project MYPROJ --board-name "My Team" --state active
```

**Output:** JSON array of sprint objects.

---

### Assign Sprint

**Script:** `scripts/assign_sprint.sh`

Add one or more issues to a sprint by sprint ID.

**Usage:**
```bash
./scripts/assign_sprint.sh <sprint_id> ISSUE-KEY [ISSUE-KEY ...]
```

**Example:**
```bash
./scripts/assign_sprint.sh 65352 PROJ-1 PROJ-2 PROJ-3
```

**Output:** `{"sprint_id": 65352, "added": ["PROJ-1", ...]}` (or Jira error JSON).

---

### Comment Issue

**Script:** `scripts/comment_issue.sh`

Add a comment to an existing issue.

**Usage:**
```bash
./scripts/comment_issue.sh <issue_key> "comment text"
./scripts/comment_issue.sh <issue_key> --file comment.txt
```

**Examples:**
```bash
./scripts/comment_issue.sh PROJ-123 "Deployed to staging. Waiting for QA sign-off."
./scripts/comment_issue.sh PROJ-123 --file release-notes.txt
```

---

### Transition Issue

**Script:** `scripts/transition_issue.sh`

List available transitions for an issue, or apply a transition by name or ID.

**Usage:**
```bash
./scripts/transition_issue.sh <issue_key> --list
./scripts/transition_issue.sh <issue_key> --to <status_name>
```

**Examples:**
```bash
# Discover available transitions (uses REST API — no acli equivalent)
./scripts/transition_issue.sh PROJ-123 --list

# Close a duplicate issue (uses acli jira workitem transition)
./scripts/transition_issue.sh PROJ-123 --to Closed

# Move to In Progress
./scripts/transition_issue.sh PROJ-123 --to "In Progress"
```

**Output:** acli JSON response on success.

> **Note:** Jira Cloud does not grant delete permission to regular users. Use `--to Closed` to retire duplicate issues instead of attempting deletion (which returns HTTP 403).

---

## Common Workflows

### Create Card from Slack Thread

```bash
RESULT=$(./scripts/create_issue.sh PROJ "Fix intermittent auth failures" \
  --issuetype Bug \
  --priority High \
  --description "Reported in #team-incidents. Users seeing 401s on login." \
  --labels "auth,backend,from-slack")

KEY=$(echo "$RESULT" | jq -r '.key')
echo "Created: $KEY"
```

### Escalate Blocked Issues

```bash
# Find open blockers
./scripts/search_issues.sh 'project = PROJ AND labels = "blocker" AND status != Done' \
  --fields summary,priority,status --format table

# Escalate each
./scripts/update_issue.sh PROJ-123 --priority Critical
```

### Get Active Sprint Without Knowing Board ID

```bash
./scripts/get_sprint.sh --project MYPROJ --board-name "My Team" --state active
```

### Find Available Link Types

```bash
acli jira workitem link type
```

## Troubleshooting

**Authentication errors:**
- Verify `JIRA_SITE` is just the hostname, not a full URL (e.g., `yourorg.atlassian.net` not `https://yourorg.atlassian.net`)
- Verify `JIRA_TOKEN` is an API token (Atlassian account settings → Security → API tokens), not your password
- Run `./scripts/setup_auth.sh` to re-authenticate

**Priority / component / custom field errors:**
- These are applied via REST PATCH after acli creates/edits the issue
- Priority names are case-sensitive and must match your instance's priority scheme
- Component names must exactly match existing components in the project
- Team must be the UUID string, not the display name

**"No boards found" errors:**
- Verify the project key is correct
- Use `acli jira board search --project PROJ` to list all boards manually
- Use `--board-name` to disambiguate when multiple boards exist
