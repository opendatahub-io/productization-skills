#!/usr/bin/env bash
#
# Vault Installation Script (Linux Only)
#
# This script installs or updates the HashiCorp Vault CLI on Linux systems.
# Supports: x86_64 and ARM64 (aarch64) architectures only.
#
# Usage:
#   ./install.sh                # Check and install Vault
#   ./install.sh --check        # Only check, don't install

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common.sh
source "$SCRIPT_DIR/../common.sh"

# renovate: datasource=github-releases depName=hashicorp/vault
VAULT_VERSION="2.1.1"
# renovate: datasource=github-release-attachments depName=hashicorp/vault
VAULT_X86_64_SHA256="8aa90f9cea46f541fc7baa3d0ec692fc06afde9a248cc1f2dcac46a567c6f56b"
# renovate: datasource=github-release-attachments depName=hashicorp/vault
VAULT_AARCH64_SHA256="c2c74e111ffbc83b3d29c6f0c0215a5e53d738c9fad045f7797bcdcde3156067"

if [ -z "${INSTALL_DIR:-}" ]; then
    if [ -w "/usr/local/bin" ]; then
        INSTALL_DIR="/usr/local/bin"
    else
        INSTALL_DIR="$HOME/.local/bin"
    fi
fi

TMP_DIR="${TMP_DIR:-}"

cleanup() {
    if [ -n "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT

check_vault() {
    local current_version

    if ! command_exists vault; then
        log "Vault is not installed"
        return 1
    fi

    current_version=$(vault version 2>&1 | grep -oE 'v[0-9.]+' | head -1 | tr -d 'v' || true)
    log "Vault version: ${current_version:-unknown}"
    if [ -z "$current_version" ]; then
        log "Could not determine Vault version"
        return 1
    fi

    if version_gte "$current_version" "$VAULT_VERSION"; then
        log "Vault is up to date (>= $VAULT_VERSION)"
        return 0
    fi
    log "Vault version $current_version is older than required $VAULT_VERSION"
    return 1
}

install_vault() {
    local arch download_arch archive_name download_url expected_checksum

    arch=$(detect_arch)
    verify_linux || return 1
    for command in curl sha256sum unzip; do
        command_exists "$command" || {
            log "ERROR: Required command not found: $command" >&2
            return 1
        }
    done

    if [ -z "$TMP_DIR" ]; then
        TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/vault-install.XXXXXX")
    else
        mkdir -p "$TMP_DIR"
    fi

    if [ "$arch" = "x86_64" ]; then
        download_arch="amd64"
        expected_checksum="$VAULT_X86_64_SHA256"
    else
        download_arch="arm64"
        expected_checksum="$VAULT_AARCH64_SHA256"
    fi
    archive_name="vault_${VAULT_VERSION}_linux_${download_arch}.zip"
    download_url="https://releases.hashicorp.com/vault/${VAULT_VERSION}/${archive_name}"

    log "Downloading from: $download_url"
    curl -fsSL "$download_url" -o "$TMP_DIR/$archive_name"
    printf '%s  %s\n' "$expected_checksum" "$TMP_DIR/$archive_name" | sha256sum --check
    unzip -q "$TMP_DIR/$archive_name" -d "$TMP_DIR"

    log "Installing to: $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    mv "$TMP_DIR/vault" "$INSTALL_DIR/vault"
    chmod +x "$INSTALL_DIR/vault"

    PATH="$INSTALL_DIR:$PATH" check_vault || {
        log "Vault installation verification failed" >&2
        return 1
    }
    log "Vault installed successfully"
}

main() {
    local check_only=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
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
        check_vault
        exit $?
    fi

    warn_if_not_in_path "$INSTALL_DIR"
    if ! check_vault; then
        install_vault
    fi
}

main "$@"
