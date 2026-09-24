#!/usr/bin/env bash
set -euo pipefail

# renovate: datasource=github-releases depName=cli/cli
GH_VERSION="2.100.0"
# renovate: datasource=github-release-attachments depName=cli/cli
GH_AMD64_URL="https://github.com/cli/cli/releases/download/v2.100.0/gh_2.100.0_linux_amd64.tar.gz"
GH_AMD64_SHA256="e4d4bb4498e8d007abe545b6568926793ace1b6447da598294a610018cb164be"
# renovate: datasource=github-release-attachments depName=cli/cli
GH_ARM64_URL="https://github.com/cli/cli/releases/download/v2.100.0/gh_2.100.0_linux_arm64.tar.gz"
GH_ARM64_SHA256="ea4e7a581a32ccad6cc7923cb1576ac5859ba4b9a16ab22eb8f8a96e78e2e961"
