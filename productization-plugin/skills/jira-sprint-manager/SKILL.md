---
name: jira-sprint-manager
description: Sprint-aware Jira operations for managing cards within sprints. Use this skill when the user asks to list sprint cards, find a sprint ID by number or state, create a card and place it in a sprint, or assign existing cards to a sprint. Requires JIRA_SITE, JIRA_TOKEN, and JIRA_EMAIL env vars.
allowed-tools: Bash(*/jira-sprint-manager/scripts/*.sh *),Bash(*/jira-utilities/scripts/*.sh *)
---

# Jira Sprint Manager

Sprint-aware Jira operations: resolve sprint IDs from a board, list sprint cards, and create issues directly into a sprint.

## Prerequisites

**Required tools:** `acli`, `jq`

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `JIRA_SITE` | Yes | Atlassian site (e.g. `yourorg.atlassian.net`) |
| `JIRA_TOKEN` | Yes | Atlassian API token |
| `JIRA_EMAIL` | Yes | Your Atlassian account email |
| `JIRA_BOARD_ID` | No | Default board ID — skips `--board-id` flag |
| `JIRA_PROJECT` | No | Project key for board auto-discovery when `JIRA_BOARD_ID` is unset |

## Scripts

### `get_sprint_id.sh` — Resolve sprint ID

```bash
./scripts/get_sprint_id.sh [--board-id ID] <sprint-number>
./scripts/get_sprint_id.sh [--board-id ID] --active
./scripts/get_sprint_id.sh [--board-id ID] --next
```

`--board-id` is optional when `JIRA_BOARD_ID` env var is set.

Output is a plain integer on stdout — suitable for `$()` capture.

```bash
SPRINT=$(./scripts/get_sprint_id.sh --board-id 42 --active)
SPRINT=$(./scripts/get_sprint_id.sh --board-id 42 31)
# With JIRA_BOARD_ID=42 set:
SPRINT=$(./scripts/get_sprint_id.sh --active)
```

---

### `list_sprint_cards.sh` — List sprint work items

```bash
./scripts/list_sprint_cards.sh [--board-id ID] [options]
```

**Options:**
- `--board-id ID` — Jira Software board ID (optional — falls back to `JIRA_BOARD_ID` env var, then auto-discovery via `JIRA_PROJECT`, then boardless JQL)
- `--sprint-id ID` — Sprint ID to use directly (skips board/sprint resolution entirely)
- `--state active|future` — sprint state for resolution (default: `active`)
- `--assignee EMAIL` — filter by assignee
- `--status STATUS` — filter by status name (e.g. `"In Progress"`)

**Sprint resolution order:**
1. `--sprint-id` flag — skip all board/sprint resolution
2. `--board-id` flag → `JIRA_BOARD_ID` env var → auto-discovered via `JIRA_PROJECT`
3. If board resolution fails or returns no sprint, fall back to `sprint in openSprints()`

**Examples:**
```bash
# All cards in active sprint (board from env var or auto-discovery)
./scripts/list_sprint_cards.sh

# All cards in active sprint (explicit board ID)
./scripts/list_sprint_cards.sh --board-id 42

# Skip resolution entirely — use known sprint ID
./scripts/list_sprint_cards.sh --sprint-id 44128 --assignee user@example.com

# Cards assigned to a specific person
./scripts/list_sprint_cards.sh --board-id 42 --assignee user@example.com

# Cards in a specific status
./scripts/list_sprint_cards.sh --board-id 42 --status "In Progress"

# Future sprint overview
./scripts/list_sprint_cards.sh --board-id 42 --state future
```

---

### `create_and_assign.sh` — Create card and place in sprint

```bash
./scripts/create_and_assign.sh --project KEY <sprint_id> <summary> [create_issue.sh options...]
```

Creates an issue in the given project and immediately assigns it to a sprint.
Any extra options after `<summary>` are forwarded to `create_issue.sh`
(e.g. `--issuetype`, `--component`, `--team`, `--priority`, `--assignee`).

Output: created issue key on stdout.

**Examples:**
```bash
# Create and assign to active sprint
SPRINT=$(./scripts/get_sprint_id.sh --board-id 42 --active)
./scripts/create_and_assign.sh --project MYPROJ "$SPRINT" "Investigate flaky test"

# With optional fields
./scripts/create_and_assign.sh --project MYPROJ "$SPRINT" "Fix auth timeout" \
    --assignee user@example.com \
    --priority High \
    --component "Backend"
```

## Common Workflow

```bash
# Resolve active sprint, create card, assign — in one pipeline
SPRINT=$(./scripts/get_sprint_id.sh --board-id 42 --active)
KEY=$(./scripts/create_and_assign.sh --project MYPROJ "$SPRINT" "My task")
echo "Created: $KEY"
```
