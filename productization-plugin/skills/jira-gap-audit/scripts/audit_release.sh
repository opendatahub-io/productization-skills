#!/usr/bin/env bash
#
# Audit Jira card structure for a release and report gaps vs the expected template.
#
# Always checks for: Epic "<product> <version> Downstream Release" with ≥1 child task.
# With --post-release: also checks for: Epic "<product> <version> Post-Release Activities".
#
# Usage:
#   ./audit_release.sh --project KEY <product> <version> [--post-release]
#
# Options:
#   --project KEY    Jira project key to search (required)
#   --post-release   Also audit the Post-Release Activities epic
#
# Examples:
#   ./audit_release.sh --project MYPROJ MyProduct "3.4 GA" --post-release
#   ./audit_release.sh --project MYPROJ MyProduct "3.3.2"
#
# Output: FOUND | MISSING | EMPTY per expected card
# Exit codes: 0=no gaps, 1=gaps found, 2=error

set -euo pipefail

JIRA_UTILS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../jira-utilities/scripts" && pwd)"
source "$JIRA_UTILS/_common.sh"

PROJECT=""
POST_RELEASE=false
POSITIONAL=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project)      PROJECT="$2"; shift 2 ;;
        --post-release) POST_RELEASE=true; shift ;;
        --*)            echo "ERROR: Unknown option: $1" >&2; exit 2 ;;
        *)              POSITIONAL+=("$1"); shift ;;
    esac
done

if [[ -z "$PROJECT" || ${#POSITIONAL[@]} -lt 2 ]]; then
    echo "Usage: $(basename "$0") --project KEY <product> <version> [--post-release]" >&2
    exit 2
fi

PRODUCT="${POSITIONAL[0]}"
VERSION="${POSITIONAL[1]}"

ensure_auth

GAPS=0

check_epic() {
    local label="$1" search_term="$2"
    local expected_summary="$PRODUCT $VERSION $search_term"

    RESULTS=$("$JIRA_UTILS/search_issues.sh" \
        "project = $PROJECT AND issuetype = Epic AND summary ~ \"$search_term\" AND summary ~ \"$VERSION\"" \
        --max-results 50 2>/dev/null)

    # Post-filter for exact summary match to avoid fuzzy-match false positives
    EPIC_KEY=$(echo "$RESULTS" | jq -r --arg s "$expected_summary" \
        '.[] | select(.fields.summary == $s) | .key' | head -1)

    if [[ -z "$EPIC_KEY" ]]; then
        printf "MISSING | %-40s | Not found in %s\n" "$label" "$PROJECT"
        GAPS=$((GAPS + 1))
        return
    fi

    CHILDREN=$("$JIRA_UTILS/search_issues.sh" \
        "project = $PROJECT AND parent = $EPIC_KEY" \
        --max-results 20 2>/dev/null)
    CHILD_COUNT=$(echo "$CHILDREN" | jq 'if type == "array" then length else 0 end')

    if [[ "$CHILD_COUNT" -eq 0 ]]; then
        printf "EMPTY   | %-40s | %s (no children)\n" "$label" "$EPIC_KEY"
        GAPS=$((GAPS + 1))
    else
        printf "FOUND   | %-40s | %s (%d children)\n" "$label" "$EPIC_KEY" "$CHILD_COUNT"
    fi
}

echo "Auditing $PRODUCT $VERSION in project $PROJECT..."
echo ""
printf "%-8s | %-40s | %s\n" "STATUS" "EXPECTED CARD" "DETAIL"
printf '%0.s─' {1..80}; echo

check_epic "Downstream Release" "Downstream Release"

if [[ "$POST_RELEASE" == "true" ]]; then
    check_epic "Post-Release Activities" "Post-Release Activities"
fi

echo ""
if [[ "$GAPS" -eq 0 ]]; then
    echo "No gaps found."
    exit 0
else
    echo "$GAPS gap(s) found."
    exit 1
fi
