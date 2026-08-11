#!/usr/bin/env bash
#
# Authenticate acli with Jira Cloud using environment variables.
# Run this once per session/container before using other scripts.
#
# Required env vars:
#   JIRA_SITE   - Atlassian site hostname (e.g., yourorg.atlassian.net)
#   JIRA_TOKEN  - API token from Atlassian account settings
#   JIRA_EMAIL  - Your Atlassian account email
#
# Usage:
#   ./setup_auth.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

ensure_auth
echo "acli authenticated to $JIRA_SITE as $JIRA_EMAIL" >&2
