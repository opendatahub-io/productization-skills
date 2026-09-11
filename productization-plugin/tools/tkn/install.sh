#!/usr/bin/env bash
#
# tkn Installation Script (Linux Only)
#
# This script installs or updates the Tekton CLI on Linux systems.
# Supports: x86_64 and ARM64 (aarch64) architectures only.
#
# Usage:
#   ./install.sh                # Check and install tkn
#   ./install.sh --check        # Only check, don't install

set -euo pipefail

# ============================================================================
# LOAD COMMON LIBRARY
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common.sh
source "$SCRIPT_DIR/../common.sh"

# ============================================================================
# DEPENDENCY VERSION
# ============================================================================
# This version is tracked by Renovate for automatic updates
# renovate: datasource=github-releases depName=tektoncd/cli
TKN_VERSION="0.46.0"

# ============================================================================
# CONFIGURATION
# ============================================================================

# Determine install directory - prefer /usr/local/bin, fallback to ~/.local/bin
if [ -z "${INSTALL_DIR:-}" ]; then
    if [ -w "/usr/local/bin" ]; then
        INSTALL_DIR="/usr/local/bin"
    else
        INSTALL_DIR="$HOME/.local/bin"
    fi
fi

TMP_DIR="${TMP_DIR:-/tmp/tkn-install}"

# ============================================================================
# TKN INSTALLATION
# ============================================================================

check_tkn() {
    local current_version

    if ! command_exists tkn; then
        log "tkn is not installed"
        return 1
    fi

    current_version=$(tkn version 2>&1 | grep -oP 'Client version:\s*v?\K[0-9.]+' || echo "unknown")
    log "tkn version: $current_version"

    if [ "$current_version" = "unknown" ]; then
        log "Could not determine tkn version"
        return 0
    fi

    if version_gte "$current_version" "$TKN_VERSION"; then
        log "tkn is up to date (>= $TKN_VERSION)"
        return 0
    else
        log "tkn version $current_version is older than required $TKN_VERSION"
        return 1
    fi
}

install_tkn() {
    local arch
    arch=$(detect_arch)

    log "Installing tkn v${TKN_VERSION} for Linux $arch..."

    verify_linux || return 1

    mkdir -p "$TMP_DIR"

    local download_arch
    if [ "$arch" = "x86_64" ]; then
        download_arch="x86_64"
    else
        download_arch="aarch64"
    fi

    local archive_name="tkn_${TKN_VERSION}_Linux_${download_arch}.tar.gz"
    local download_url="https://github.com/tektoncd/cli/releases/download/v${TKN_VERSION}/${archive_name}"

    log "Downloading from: $download_url"
    curl -fsSL "$download_url" -o "${TMP_DIR}/${archive_name}"

    log "Extracting..."
    tar -xzf "${TMP_DIR}/${archive_name}" -C "$TMP_DIR"

    log "Installing to: $INSTALL_DIR"
    mv "${TMP_DIR}/tkn" "$INSTALL_DIR/tkn"
    chmod +x "$INSTALL_DIR/tkn"

    rm -rf "$TMP_DIR"

    if check_tkn; then
        log "✓ tkn installed successfully"
        return 0
    else
        log "✗ tkn installation verification failed" >&2
        return 1
    fi
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================

main() {
    local check_only=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--check)
                check_only=true
                shift
                ;;
            *)
                log "ERROR: Unknown option: $1" >&2
                log "Usage: $(basename "$0") [--check]" >&2
                exit 1
                ;;
        esac
    done

    mkdir -p "$INSTALL_DIR"
    mkdir -p "$TMP_DIR"

    warn_if_not_in_path "$INSTALL_DIR"

    if [ "$check_only" = true ]; then
        check_tkn
        exit $?
    fi

    if ! check_tkn; then
        echo ""
        log "Installing tkn..."
        install_tkn
    fi
}

main "$@"
