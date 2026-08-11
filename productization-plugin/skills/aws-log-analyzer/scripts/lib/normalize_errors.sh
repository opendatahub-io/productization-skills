#!/bin/bash
# Error message normalization functions
# Normalizes error messages by replacing variable parts (timestamps, IPs, UUIDs, etc.)
# with placeholders to group similar errors by pattern.
#
# Usage:
#   source "$SCRIPT_DIR/lib/normalize_errors.sh"
#   NORMALIZED=$(normalize_insights_errors "$JSON_ARRAY")

# normalize_insights_errors - Add pattern field to error objects
#
# Takes a JSON array of objects with "message" and "count" fields,
# normalizes messages by replacing timestamps, IPs, UUIDs, numbers, and
# hex values with placeholders, and adds a "pattern" field to each object.
#
# Arguments:
#   $1 - JSON array string: [{"message": "...", "count": N}, ...]
#
# Output:
#   JSON array with added "pattern" field on stdout
#
# Example:
#   Input:  [{"message": "Error at 2026-02-06 15:30:45", "count": 120}]
#   Output: [{"message": "Error at 2026-02-06 15:30:45", "count": 120, "pattern": "Error at <TIMESTAMP>"}]
normalize_insights_errors() {
    local json_input="$1"

    echo "$json_input" | jq '[
        .[] | . + {
            pattern: (
                .message
                # ISO 8601 timestamps: 2026-02-06T15:30:45.123Z or 2026-02-06T15:30:45+00:00
                | gsub("\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}[.\\d]*[A-Z]*[+\\-]?[\\d:]*"; "<TIMESTAMP>")
                # Date-time with space: 2026-02-06 15:30:45
                | gsub("\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}[.\\d]*"; "<TIMESTAMP>")
                # Time only: 15:30:45.123
                | gsub("\\d{2}:\\d{2}:\\d{2}[.\\d]+"; "<TIME>")
                # UUIDs: 550e8400-e29b-41d4-a716-446655440000
                | gsub("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"; "<UUID>")
                # IPv4 addresses: 192.168.1.100
                | gsub("\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}"; "<IP>")
                # Hex strings (8+ chars): 0x7fff5fbff8c0 or deadbeef01234567
                | gsub("0x[0-9a-fA-F]{4,}"; "<HEX>")
                | gsub("\\b[0-9a-fA-F]{16,}\\b"; "<HEX>")
                # Long numeric sequences (5+ digits, likely IDs/timestamps)
                | gsub("\\b\\d{5,}\\b"; "<NUM>")
            )
        }
    ]'
}
