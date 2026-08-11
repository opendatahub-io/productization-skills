---
name: jira-release-setup
description: Create the complete Jira card structure for a product release milestone. Encodes the release card templates (epics + child tasks) so the agent never has to reconstruct them. Use this skill when the user asks to set up Jira cards for a new release, create release tracking epics, or set up sprint cards for a release milestone.
allowed-tools: Bash(*/jira-release-setup/scripts/*.sh *),Bash(*/jira-utilities/scripts/*.sh *)
---

# Jira Release Setup

Creates the complete Jira card structure for a product release milestone. Encodes the canonical release templates so no business logic needs to be reconstructed each session.

## Prerequisites

**Required environment variables:**
- `JIRA_SITE` — Atlassian site (e.g. `yourorg.atlassian.net`)
- `JIRA_TOKEN` — Atlassian API token
- `JIRA_EMAIL` — Your Atlassian account email

**Required tools:** `acli`, `jq`

## Card Templates

### Two-phase release (default)

```text
Epic: <product> <version> Downstream Release
  ├── Task: Build <product> <version> RC drops
  ├── Task: Release <product> <version> to production
  └── Task: Send a <product> <version> release announcement email

Epic: <product> <version> Post-Release Activities
  ├── Task: Push <product> <version> to cloud marketplaces
  └── Task: Bump <product> version to <next-version>
```

### Single-epic release (`--single-epic`)

```text
Epic: <product> <version> Downstream Release
  ├── Task: Release <product> <version> to production
  ├── Task: Send a <product> <version> release announcement email
  └── Task: Bump <product> version to <next-version>
```

## Version Calculation

Next-version is computed automatically by `_next_version.sh`:

| Input version | Next version |
|---|---|
| `3.4 GA` | `3.4.1` |
| `3.3.2` | `3.3.3` |
| `3.4 EA1` | `3.4 EA2` |

## Scripts

### `create_release.sh` — Create full release card structure

```bash
./scripts/create_release.sh --project KEY <product> <version> [options]
```

**Options:**
- `--project KEY` — Jira project key (required)
- `--component NAME` — component to set on all created issues (optional)
- `--single-epic` — create one downstream epic only (default: two-phase)
- `--sprint-id ID` — assign all created cards to this sprint (optional)

**Examples:**
```bash
# Single-epic release
./scripts/create_release.sh --project MYPROJ MyProduct "3.3.2" --single-epic

# Two-phase release assigned to sprint
./scripts/create_release.sh --project MYPROJ MyProduct "3.4 GA" --sprint-id 44147

# Get sprint ID first, then create
SPRINT=$(../../jira-sprint-manager/scripts/get_sprint_id.sh --board-id 42 --active)
./scripts/create_release.sh --project MYPROJ MyProduct "3.3.2" --single-epic --sprint-id "$SPRINT"
```

---

### `_next_version.sh` — Calculate next version (internal helper)

```bash
./scripts/_next_version.sh "3.3.2"   # → 3.3.3
./scripts/_next_version.sh "3.4 GA"  # → 3.4.1
./scripts/_next_version.sh "3.4 EA1" # → 3.4 EA2
```
