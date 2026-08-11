---
name: jira-gap-audit
description: Audit existing Jira cards for a release against the expected card template. Reports missing epics, empty epics (no children), and other structural gaps. Use this skill when the user asks to check if release cards are set up correctly, verify the Jira structure for a release, or get a gap report across a set of releases.
allowed-tools: Bash(*/jira-gap-audit/scripts/*.sh *),Bash(*/jira-utilities/scripts/*.sh *)
---

# Jira Gap Audit

Audits Jira card structure for release milestones against the canonical templates. Reports gaps so they can be fixed with `jira-release-setup`.

## Prerequisites

**Required environment variables:**
- `JIRA_SITE` — Atlassian site (e.g. `yourorg.atlassian.net`)
- `JIRA_TOKEN` — Atlassian API token
- `JIRA_EMAIL` — Your Atlassian account email

**Required tools:** `acli`, `jq`

## Expected Templates

Always audited: `<product> <version> Downstream Release` epic with ≥1 child task.

With `--post-release`: also audits `<product> <version> Post-Release Activities` epic with ≥1 child task.

## Scripts

### `audit_release.sh` — Audit a single release

```bash
./scripts/audit_release.sh --project KEY <product> <version> [--post-release]
```

**Options:**
- `--project KEY` — Jira project key (required)
- `--post-release` — also check for Post-Release Activities epic

**Examples:**
```bash
./scripts/audit_release.sh --project MYPROJ MyProduct "3.4 GA" --post-release
./scripts/audit_release.sh --project MYPROJ MyProduct "3.3.2"
```

**Output:**
```text
STATUS   | EXPECTED CARD                             | DETAIL
─────────────────────────────────────────────────────────────────────────────
FOUND    | Downstream Release                        | PROJ-101 (3 children)
FOUND    | Post-Release Activities                   | PROJ-102 (2 children)

No gaps found.
```

Possible status values:
- `FOUND` — epic exists and has children
- `EMPTY` — epic exists but has no child tasks
- `MISSING` — epic not found in the project

**Exit codes:** `0` = no gaps, `1` = gaps found, `2` = error

---

### `audit_all.sh` — Audit multiple releases

```bash
./scripts/audit_all.sh --project KEY "PRODUCT:VERSION" [...]
```

Runs `audit_release.sh` for each `PRODUCT:VERSION` pair. Quote entries containing spaces.

**Examples:**
```bash
./scripts/audit_all.sh --project MYPROJ \
    "MyProduct:3.4 GA" \
    "MyProduct:3.3.2" \
    "OtherProduct:1.0 GA"

# With post-release check, pipe --post-release via audit_release.sh directly
./scripts/audit_release.sh --project MYPROJ MyProduct "3.4 GA" --post-release
```

**Exit codes:** `0` = no gaps, `1` = at least one release has gaps

## Gap Resolution

When a gap is found, use `jira-release-setup` to create the missing cards:

```bash
# Missing single-epic release cards
../../jira-release-setup/scripts/create_release.sh --project MYPROJ MyProduct "3.3.2" --single-epic

# Missing two-phase release cards
../../jira-release-setup/scripts/create_release.sh --project MYPROJ MyProduct "3.4 GA"
```
