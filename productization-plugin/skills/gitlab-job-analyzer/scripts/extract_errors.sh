#!/usr/bin/env bash
#
# Extract and categorize errors from GitLab CI job logs
#
# Usage:
#   extract_errors.sh <log-file>
#   extract_errors.sh --help

set -euo pipefail

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] <log-file>

Extract and categorize errors from GitLab CI job logs.

ARGUMENTS:
    log-file               Path to job log file

OUTPUT:
    Categorized errors by type:
    - Compilation/Build errors
    - Test failures
    - Runtime exceptions
    - Infrastructure/Timeout errors
    - Dependency/Package errors
    - Other errors

EXAMPLES:
    # Extract errors from job log
    $(basename "$0") job.log

    # Extract errors from job trace command
    glab ci trace 12345 -R owner/repo | $(basename "$0") /dev/stdin

OPTIONS:
    -h, --help              Show this help message
    --context N             Show N lines of context around errors (default: 3)
    --json                  Output as JSON

EOF
}

# Parse arguments
CONTEXT_LINES=3
OUTPUT_FORMAT="text"

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        --context)
            CONTEXT_LINES="$2"
            shift 2
            ;;
        --json)
            OUTPUT_FORMAT="json"
            shift
            ;;
        *)
            break
            ;;
    esac
done

if [[ $# -lt 1 ]]; then
    echo "Error: Missing log file" >&2
    show_usage
    exit 1
fi

LOG_FILE="$1"

if [[ ! -r "$LOG_FILE" && "$LOG_FILE" != "/dev/stdin" ]]; then
    echo "Error: Cannot read log file: $LOG_FILE" >&2
    exit 1
fi

# Temporary files for categorization
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

COMPILATION_ERRORS="$TEMP_DIR/compilation.txt"
TEST_FAILURES="$TEMP_DIR/test.txt"
RUNTIME_EXCEPTIONS="$TEMP_DIR/runtime.txt"
INFRASTRUCTURE_ERRORS="$TEMP_DIR/infra.txt"
DEPENDENCY_ERRORS="$TEMP_DIR/deps.txt"
OTHER_ERRORS="$TEMP_DIR/other.txt"

# Extract compilation/build errors
grep -i -E "(^error:|fatal error:|make: \*\*\*.*Error [0-9]+|Build failed|compilation terminated|ld returned.*exit status)" "$LOG_FILE" > "$COMPILATION_ERRORS" || true

# Extract test failures
grep -i -E "(FAILED|FAIL:|Error:.*expected.*got|AssertionError|[0-9]+ failed.*[0-9]+ passed|Test.*FAILED)" "$LOG_FILE" > "$TEST_FAILURES" || true

# Extract runtime exceptions
grep -i -E "(Exception in thread|Traceback \(most recent call last\)|Caused by:|Segmentation fault|NullPointerException|panic:|RuntimeError)" "$LOG_FILE" > "$RUNTIME_EXCEPTIONS" || true

# Extract infrastructure/timeout errors
grep -i -E "(ERROR: Job failed.*execution took longer|timeout:.*|No space left on device|Connection refused|dial tcp.*timeout|runner.*system failure)" "$LOG_FILE" > "$INFRASTRUCTURE_ERRORS" || true

# Extract dependency/package errors
grep -i -E "(Could not find package|Failed to install|npm ERR!|pip.*ERROR|unable to resolve dependency|ModuleNotFoundError|ImportError)" "$LOG_FILE" > "$DEPENDENCY_ERRORS" || true

# Extract other generic errors (exclude lines already categorized above)
# Use -F (fixed strings) for exclusion so exact line content is matched
grep -i -E "(^ERROR|error:)" "$LOG_FILE" | grep -v -F -f "$COMPILATION_ERRORS" | grep -v -F -f "$TEST_FAILURES" | grep -v -F -f "$RUNTIME_EXCEPTIONS" | grep -v -F -f "$INFRASTRUCTURE_ERRORS" | grep -v -F -f "$DEPENDENCY_ERRORS" > "$OTHER_ERRORS" || true

# Count errors
count_errors() {
    local file="$1"
    if [[ -f "$file" ]]; then
        wc -l < "$file"
    else
        echo "0"
    fi
}

COMPILATION_COUNT=$(count_errors "$COMPILATION_ERRORS")
TEST_COUNT=$(count_errors "$TEST_FAILURES")
RUNTIME_COUNT=$(count_errors "$RUNTIME_EXCEPTIONS")
INFRA_COUNT=$(count_errors "$INFRASTRUCTURE_ERRORS")
DEPS_COUNT=$(count_errors "$DEPENDENCY_ERRORS")
OTHER_COUNT=$(count_errors "$OTHER_ERRORS")

TOTAL_ERRORS=$((COMPILATION_COUNT + TEST_COUNT + RUNTIME_COUNT + INFRA_COUNT + DEPS_COUNT + OTHER_COUNT))

# Output function
print_category() {
    local title="$1"
    local file="$2"
    local count="$3"

    if [[ $count -gt 0 ]]; then
        echo ""
        echo "=== $title ($count) ==="
        echo ""
        head -10 "$file"
        if [[ $count -gt 10 ]]; then
            echo "... (showing first 10 of $count errors)"
        fi
    fi
}

# JSON output
if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    cat << EOF
{
  "total_errors": $TOTAL_ERRORS,
  "categories": {
    "compilation": $COMPILATION_COUNT,
    "test_failures": $TEST_COUNT,
    "runtime_exceptions": $RUNTIME_COUNT,
    "infrastructure": $INFRA_COUNT,
    "dependencies": $DEPS_COUNT,
    "other": $OTHER_COUNT
  },
  "details": {
    "compilation": $(jq -R -s -c 'split("\n")[:-1]' < "$COMPILATION_ERRORS" 2>/dev/null || echo '[]'),
    "test_failures": $(jq -R -s -c 'split("\n")[:-1]' < "$TEST_FAILURES" 2>/dev/null || echo '[]'),
    "runtime_exceptions": $(jq -R -s -c 'split("\n")[:-1]' < "$RUNTIME_EXCEPTIONS" 2>/dev/null || echo '[]'),
    "infrastructure": $(jq -R -s -c 'split("\n")[:-1]' < "$INFRASTRUCTURE_ERRORS" 2>/dev/null || echo '[]'),
    "dependencies": $(jq -R -s -c 'split("\n")[:-1]' < "$DEPENDENCY_ERRORS" 2>/dev/null || echo '[]'),
    "other": $(jq -R -s -c 'split("\n")[:-1]' < "$OTHER_ERRORS" 2>/dev/null || echo '[]')
  }
}
EOF
    exit 0
fi

# Text output
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    Error Analysis Summary                      ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Total Errors Found: $TOTAL_ERRORS"
echo ""
echo "Breakdown by Category:"
echo "  - Compilation/Build Errors:    $COMPILATION_COUNT"
echo "  - Test Failures:                $TEST_COUNT"
echo "  - Runtime Exceptions:           $RUNTIME_COUNT"
echo "  - Infrastructure/Timeout:       $INFRA_COUNT"
echo "  - Dependency/Package Errors:    $DEPS_COUNT"
echo "  - Other Errors:                 $OTHER_COUNT"

print_category "Compilation/Build Errors" "$COMPILATION_ERRORS" "$COMPILATION_COUNT"
print_category "Test Failures" "$TEST_FAILURES" "$TEST_COUNT"
print_category "Runtime Exceptions" "$RUNTIME_EXCEPTIONS" "$RUNTIME_COUNT"
print_category "Infrastructure/Timeout Errors" "$INFRASTRUCTURE_ERRORS" "$INFRA_COUNT"
print_category "Dependency/Package Errors" "$DEPENDENCY_ERRORS" "$DEPS_COUNT"
print_category "Other Errors" "$OTHER_ERRORS" "$OTHER_COUNT"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                      Recommendations                           ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

if [[ $COMPILATION_COUNT -gt 0 ]]; then
    echo "- Review compilation errors and fix syntax/type issues"
fi

if [[ $TEST_COUNT -gt 0 ]]; then
    echo "- Investigate test failures and verify test expectations"
fi

if [[ $RUNTIME_COUNT -gt 0 ]]; then
    echo "- Check for null pointer/runtime exceptions and add error handling"
fi

if [[ $INFRA_COUNT -gt 0 ]]; then
    echo "- Check runner resources, network connectivity, or increase timeouts"
fi

if [[ $DEPS_COUNT -gt 0 ]]; then
    echo "- Verify dependency versions and package availability"
fi

if [[ $TOTAL_ERRORS -eq 0 ]]; then
    echo "No obvious errors found in the log."
    echo "Consider checking for:"
    echo "  - Exit codes (job may have failed silently)"
    echo "  - Warning messages that became critical"
    echo "  - Resource exhaustion (memory, disk)"
fi

echo ""
