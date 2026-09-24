#!/usr/bin/env bash
#
# GitHub CLI (gh) Installation Script (Linux Only)
#
# This script installs or updates gh on Linux systems.
# Supports: x86_64 and ARM64 (aarch64) architectures only.
#
# Usage:
#   ./install.sh                # Check and install gh
#   ./install.sh --check        # Only check, don't install

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common.sh
source "$SCRIPT_DIR/../common.sh"

# renovate: datasource=github-releases depName=cli/cli
GH_VERSION="2.101.0"
# renovate: datasource=github-release-attachments depName=cli/cli
GH_AMD64_URL="https://github.com/cli/cli/releases/download/v2.101.0/gh_2.101.0_linux_amd64.tar.gz"
GH_AMD64_SHA256="9bca2d1c16825f109907a23307628a2f0698fbf99662b73a5cf0b020293072b8"
# renovate: datasource=github-release-attachments depName=cli/cli
GH_ARM64_URL="https://github.com/cli/cli/releases/download/v2.101.0/gh_2.101.0_linux_arm64.tar.gz"
GH_ARM64_SHA256="b57e8063f18862647c9d22727c32e9da1b963f8bf9db648fe123a6975695640f"

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

check_gh() {
    local gh_path="$INSTALL_DIR/gh"
    local current_version

    if [ ! -x "$gh_path" ]; then
        gh_path="$(command -v gh || true)"
    fi

    if [ -z "$gh_path" ]; then
        log "gh is not installed"
        return 1
    fi

    current_version=$("$gh_path" --version 2>&1 | awk 'NR == 1 && $1 == "gh" && $2 == "version" {print $3}')
    if [ -z "$current_version" ]; then
        log "Could not determine gh version"
        return 1
    fi

    log "gh version: $current_version"

    if version_gte "$current_version" "$GH_VERSION"; then
        log "gh is up to date (>= $GH_VERSION)"
        return 0
    else
        log "gh version $current_version is older than required $GH_VERSION"
        return 1
    fi
}

install_gh() {
    local arch
    arch=$(detect_arch)

    log "Installing gh v${GH_VERSION} for Linux $arch..."
    verify_linux || return 1

    for command in curl sha256sum tar; do
        if ! command_exists "$command"; then
            log "ERROR: Required command not found: $command" >&2
            return 1
        fi
    done

    if [ -z "$TMP_DIR" ]; then
        TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/gh-install.XXXXXX")
        TMP_DIR_CREATED=true
    else
        mkdir -p "$TMP_DIR"
    fi

    local download_arch
    if [ "$arch" = "x86_64" ]; then
        download_arch="amd64"
    else
        download_arch="arm64"
    fi

    local download_url
    local expected_checksum
    if [ "$download_arch" = "amd64" ]; then
        download_url="$GH_AMD64_URL"
        expected_checksum="$GH_AMD64_SHA256"
    else
        download_url="$GH_ARM64_URL"
        expected_checksum="$GH_ARM64_SHA256"
    fi

    local archive_name="${download_url##*/}"
    log "Downloading from: $download_url"
    curl -fsSL "$download_url" -o "${TMP_DIR}/${archive_name}"
    printf '%s  %s\n' "$expected_checksum" "${TMP_DIR}/${archive_name}" | sha256sum --check

    log "Extracting..."
    tar -xzf "${TMP_DIR}/${archive_name}" -C "$TMP_DIR"

    local gh_binary="${TMP_DIR}/gh_${GH_VERSION}_linux_${download_arch}/bin/gh"
    if [ ! -f "$gh_binary" ]; then
        log "ERROR: Could not find gh binary in extracted archive" >&2
        return 1
    fi

    log "Installing to: $INSTALL_DIR"
    mv "$gh_binary" "$INSTALL_DIR/gh"
    chmod +x "$INSTALL_DIR/gh"

    if check_gh; then
        log "✓ gh installed successfully"
    else
        log "✗ gh installation verification failed" >&2
        return 1
    fi
}

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
        check_gh
        exit $?
    fi

    mkdir -p "$INSTALL_DIR"
    warn_if_not_in_path "$INSTALL_DIR"

    if ! check_gh; then
        echo ""
        log "Installing gh..."
        install_gh
    fi
}

main "$@"
