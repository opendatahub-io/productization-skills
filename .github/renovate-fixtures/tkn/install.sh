#!/usr/bin/env bash
set -euo pipefail

# renovate: datasource=github-releases depName=tektoncd/cli
TKN_VERSION="0.45.0"
# renovate: datasource=github-release-attachments depName=tektoncd/cli
TKN_X86_64_URL="https://github.com/tektoncd/cli/releases/download/v0.45.0/tkn_0.45.0_Linux_x86_64.tar.gz"
TKN_X86_64_SHA256="c32a60b97388eb14e1ed2155b10bd7202aaf2e0a67ca7594b08fb96c1b94454b"
# renovate: datasource=github-release-attachments depName=tektoncd/cli
TKN_AARCH64_URL="https://github.com/tektoncd/cli/releases/download/v0.45.0/tkn_0.45.0_Linux_aarch64.tar.gz"
TKN_AARCH64_SHA256="f11bc2f834a2ab845b24f40dc01faf4b41dfc3af142062bf38e44f3fb5358456"
