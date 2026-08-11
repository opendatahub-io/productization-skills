#!/usr/bin/env bash
#
# Run release gap audit across a list of product releases.
#
# Usage:
#   ./audit_all.sh --project KEY "PRODUCT:VERSION" [...]
#
# Arguments:
#   --project KEY   Jira project key to search (required)
#   PRODUCT:VERSION Release to audit — use ':' to separate product and version.
#                   Quote entries with spaces: "My Product:3.4 GA"
#
# Examples:
#   ./audit_all.sh --project MYPROJ "ProductA:3.4 GA" "ProductB:3.3.2" "ProductB:3.4 GA"
#
# Output: consolidated gap table across all releases
# Exit codes: 0=no gaps, 1=gaps found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROJECT=""
RELEASES=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project) PROJECT="$2"; shift 2 ;;
        --*)       echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
        *)         RELEASES+=("$1"); shift ;;
    esac
done

if [[ -z "$PROJECT" || ${#RELEASES[@]} -eq 0 ]]; then
    echo "Usage: $(basename "$0") --project KEY \"PRODUCT:VERSION\" [...]" >&2
    echo "Example: $(basename "$0") --project MYPROJ \"ProductA:3.4 GA\" \"ProductB:3.3.2\"" >&2
    exit 1
fi

TOTAL_GAPS=0

run_audit() {
    local product="$1" version="$2"
    echo "┌── $product $version"
    output=$("$SCRIPT_DIR/audit_release.sh" --project "$PROJECT" "$product" "$version" 2>&1) || {
        code=$?
        [[ $code -eq 1 ]] && TOTAL_GAPS=$((TOTAL_GAPS + 1))
    }
    echo "$output" | sed 's/^/│   /'
    echo ""
}

echo "=== Jira Release Gap Audit ==="
echo "Project: $PROJECT"
echo "Date: $(date '+%Y-%m-%d')"
echo ""

for entry in "${RELEASES[@]}"; do
    product="${entry%%:*}"
    version="${entry#*:}"
    run_audit "$product" "$version"
done

echo "================================"
if [[ "$TOTAL_GAPS" -eq 0 ]]; then
    echo "All releases: no gaps found."
    exit 0
else
    echo "Total releases with gaps: $TOTAL_GAPS"
    exit 1
fi
