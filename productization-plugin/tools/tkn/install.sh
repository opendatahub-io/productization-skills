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
# renovate: datasource=github-release-attachments depName=tektoncd/cli
TKN_X86_64_URL="https://github.com/tektoncd/cli/releases/download/v0.46.0/tkn_0.46.0_Linux_x86_64.tar.gz"
TKN_X86_64_SHA256="4a69c3884b40a370bf6faff620ee719adb3a4b4c1820c2edba93520e54268419"
# renovate: datasource=github-release-attachments depName=tektoncd/cli
TKN_AARCH64_URL="https://github.com/tektoncd/cli/releases/download/v0.46.0/tkn_0.46.0_Linux_aarch64.tar.gz"
TKN_AARCH64_SHA256="1aecaf783da733feccaab84240581529a62f91df11596ab536717d92a0a9c8a2"

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

TMP_DIR="${TMP_DIR:-}"
TMP_DIR_CREATED=false

cleanup() {
    if [ "$TMP_DIR_CREATED" = true ]; then
        rm -rf -- "$TMP_DIR"
    fi
}

trap cleanup EXIT

# ============================================================================
# TKN INSTALLATION
# ============================================================================

check_tkn() {
    local current_version
    local tkn_path="$INSTALL_DIR/tkn"

    if [ ! -x "$tkn_path" ]; then
        tkn_path="$(command -v tkn || true)"
    fi

    if [ -z "$tkn_path" ]; then
        log "tkn is not installed"
        return 1
    fi

    current_version=$("$tkn_path" version 2>&1 | grep -oE 'Client version:[[:space:]]*v?[0-9.]+' | grep -oE 'v?[0-9.]+$' || echo "unknown")
    log "tkn version: $current_version"

    if [ "$current_version" = "unknown" ]; then
        log "Could not determine tkn version"
        return 1
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

    for command in curl sha256sum tar; do
        if ! command_exists "$command"; then
            log "ERROR: Required command not found: $command" >&2
            return 1
        fi
    done

    if [ -z "$TMP_DIR" ]; then
        TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/tkn-install.XXXXXX")
        TMP_DIR_CREATED=true
    else
        mkdir -p "$TMP_DIR"
    fi

    local download_arch
    if [ "$arch" = "x86_64" ]; then
        download_arch="x86_64"
    else
        download_arch="aarch64"
    fi

    local archive_name
    local download_url
    local expected_checksum
    if [ "$download_arch" = "x86_64" ]; then
        archive_name="${TKN_X86_64_URL##*/}"
        download_url="$TKN_X86_64_URL"
        expected_checksum="$TKN_X86_64_SHA256"
    else
        archive_name="${TKN_AARCH64_URL##*/}"
        download_url="$TKN_AARCH64_URL"
        expected_checksum="$TKN_AARCH64_SHA256"
    fi

    log "Downloading from: $download_url"
    curl -fsSL "$download_url" -o "${TMP_DIR}/${archive_name}"
    printf '%s  %s\n' "$expected_checksum" "${TMP_DIR}/${archive_name}" | sha256sum --check

    log "Extracting..."
    tar -xzf "${TMP_DIR}/${archive_name}" -C "$TMP_DIR"

    log "Installing to: $INSTALL_DIR"
    mv "${TMP_DIR}/tkn" "$INSTALL_DIR/tkn"
    chmod +x "$INSTALL_DIR/tkn"

    if PATH="$INSTALL_DIR:$PATH" check_tkn; then
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

    if [ "$check_only" = true ]; then
        check_tkn
        exit $?
    fi

    mkdir -p "$INSTALL_DIR"
    warn_if_not_in_path "$INSTALL_DIR"

    if ! check_tkn; then
        echo ""
        log "Installing tkn..."
        install_tkn
    fi
}

main "$@"
