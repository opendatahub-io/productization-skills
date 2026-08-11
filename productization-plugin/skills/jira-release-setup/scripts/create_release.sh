#!/usr/bin/env bash
#
# Create the full Jira card structure for a product release milestone.
#
# By default creates a two-phase structure (Downstream Release + Post-Release
# Activities). Use --single-epic for products that only need one downstream epic.
#
# Usage:
#   ./create_release.sh --project KEY <product> <version> [options]
#
# Arguments:
#   product    Product name used in issue titles (any string, e.g. "MyProduct")
#   version    Release version string (e.g. "3.4 GA", "3.3.2", "3.4 EA2")
#
# Options:
#   --project KEY        Jira project key (required)
#   --component NAME     Component name to set on all created issues (optional)
#   --single-epic        Create one downstream epic only (default: two-phase)
#   --sprint-id ID       Assign all created cards to this sprint (optional)
#
# Two-phase structure (default):
#   Epic: <product> <version> Downstream Release
#     Task: Build <product> <version> RC drops
#     Task: Release <product> <version> to production
#     Task: Send a <product> <version> release announcement email
#   Epic: <product> <version> Post-Release Activities
#     Task: Push <product> <version> to cloud marketplaces
#     Task: Bump <product> version to <next-version>
#
# Single-epic structure (--single-epic):
#   Epic: <product> <version> Downstream Release
#     Task: Release <product> <version> to production
#     Task: Send a <product> <version> release announcement email
#     Task: Bump <product> version to <next-version>
#
# Examples:
#   ./create_release.sh --project MYPROJ MyProduct "3.3.2" --single-epic
#   ./create_release.sh --project MYPROJ MyProduct "3.4 GA" --sprint-id 44147
#   ./create_release.sh --project MYPROJ MyProduct "3.3.2" --component "Productization"
#
# Exit codes: 0=success, 1=invalid params, 4=auth error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JIRA_UTILS="$(cd "$SCRIPT_DIR/../../jira-utilities/scripts" && pwd)"
source "$JIRA_UTILS/_common.sh"

PROJECT=""
COMPONENT=""
SPRINT_ID=""
SINGLE_EPIC=false
POSITIONAL=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project)     PROJECT="$2";   shift 2 ;;
        --component)   COMPONENT="$2"; shift 2 ;;
        --sprint-id)   SPRINT_ID="$2"; shift 2 ;;
        --single-epic) SINGLE_EPIC=true; shift ;;
        --*)           echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
        *)             POSITIONAL+=("$1"); shift ;;
    esac
done

if [[ -z "$PROJECT" || ${#POSITIONAL[@]} -lt 2 ]]; then
    echo "Usage: $(basename "$0") --project KEY <product> <version> [--component NAME] [--single-epic] [--sprint-id ID]" >&2
    exit 1
fi

PRODUCT="${POSITIONAL[0]}"
VERSION="${POSITIONAL[1]}"

NEXT_VERSION=$("$SCRIPT_DIR/_next_version.sh" "$VERSION")
echo "Creating release cards for $PRODUCT $VERSION (next: $NEXT_VERSION)" >&2

ensure_auth

CREATED_KEYS=()
CREATED_DESCS=()

_create() {
    local summary="$1" issuetype="$2"; shift 2
    local component_arg=() team_arg=()
    [[ -n "$COMPONENT" ]]       && component_arg=(--component "$COMPONENT")
    [[ -n "${TEAM_UUID:-}" ]]   && team_arg=(--team "$TEAM_UUID")

    local key create_err create_stderr
    create_stderr=$(mktemp)
    key=$("$JIRA_UTILS/create_issue.sh" "$PROJECT" "$summary" \
        --issuetype "$issuetype" \
        "${component_arg[@]+"${component_arg[@]}"}" \
        "${team_arg[@]+"${team_arg[@]}"}" \
        "$@" 2>"$create_stderr" | jq -r '.key') || true
    create_err=$(cat "$create_stderr"); rm -f "$create_stderr"

    if [[ -z "$key" || "$key" == "null" ]]; then
        echo "ERROR: Failed to create $issuetype: $summary" >&2
        [[ -n "$create_err" ]] && echo "  Cause: $create_err" >&2
        exit 1
    fi

    CREATED_KEYS+=("$key")
    CREATED_DESCS+=("$issuetype|$summary")
    echo "  $key  [$issuetype] $summary" >&2
    echo "$key"
}

echo "" >&2
echo "=== Downstream Release ===" >&2
DOWNSTREAM_EPIC=$(_create "$PRODUCT $VERSION Downstream Release" Epic)

if [[ "$SINGLE_EPIC" == "true" ]]; then
    _create "Release $PRODUCT $VERSION to production"             Task --epic "$DOWNSTREAM_EPIC" > /dev/null
    _create "Send a $PRODUCT $VERSION release announcement email" Task --epic "$DOWNSTREAM_EPIC" > /dev/null
    _create "Bump $PRODUCT version to $NEXT_VERSION"              Task --epic "$DOWNSTREAM_EPIC" > /dev/null
else
    _create "Build $PRODUCT $VERSION RC drops"                    Task --epic "$DOWNSTREAM_EPIC" > /dev/null
    _create "Release $PRODUCT $VERSION to production"             Task --epic "$DOWNSTREAM_EPIC" > /dev/null
    _create "Send a $PRODUCT $VERSION release announcement email" Task --epic "$DOWNSTREAM_EPIC" > /dev/null

    echo "" >&2
    echo "=== Post-Release Activities ===" >&2
    POSTRELEASE_EPIC=$(_create "$PRODUCT $VERSION Post-Release Activities" Epic)
    _create "Push $PRODUCT $VERSION to cloud marketplaces"        Task --epic "$POSTRELEASE_EPIC" > /dev/null
    _create "Bump $PRODUCT version to $NEXT_VERSION"              Task --epic "$POSTRELEASE_EPIC" > /dev/null
fi

if [[ -n "$SPRINT_ID" ]]; then
    echo "" >&2
    echo "Assigning ${#CREATED_KEYS[@]} issue(s) to sprint $SPRINT_ID..." >&2
    "$JIRA_UTILS/assign_sprint.sh" "$SPRINT_ID" "${CREATED_KEYS[@]}" >/dev/null || {
        echo "WARNING: Sprint assignment failed. Created keys: ${CREATED_KEYS[*]}" >&2
        exit 1
    }
fi

echo ""
echo "Created ${#CREATED_KEYS[@]} issue(s):"
printf "%-15s %-8s %s\n" "KEY" "TYPE" "SUMMARY"
printf '%0.s─' {1..80}; echo
for i in "${!CREATED_KEYS[@]}"; do
    IFS='|' read -r itype summary <<< "${CREATED_DESCS[$i]}"
    printf "%-15s %-8s %s\n" "${CREATED_KEYS[$i]}" "$itype" "$summary"
done
