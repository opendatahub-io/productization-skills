#!/usr/bin/env bash
#
# Common Library for Tool Installation Scripts
#
# This library provides shared functions used across tool installation scripts.
# Usage: source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"

# ============================================================================
# LOGGING
# ============================================================================

log() {
    echo "$*"
}

# ============================================================================
# PLATFORM DETECTION
# ============================================================================

# Detect architecture
# Returns: x86_64 or aarch64
# Exit code: 0 on success, 1 if unsupported
detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)
            echo "x86_64"
            ;;
        aarch64|arm64)
            echo "aarch64"
            ;;
        *)
            log "ERROR: Unsupported architecture: $(uname -m)" >&2
            log "This script only supports x86_64 and aarch64 (ARM64)" >&2
            return 1
            ;;
    esac
}

# Verify we're running on Linux
# Exit code: 0 if Linux, 1 otherwise
verify_linux() {
    if [ "$(uname -s)" != "Linux" ]; then
        log "ERROR: This script only supports Linux" >&2
        log "Detected OS: $(uname -s)" >&2
        return 1
    fi
    return 0
}

# ============================================================================
# COMMAND UTILITIES
# ============================================================================

# Check if command exists
# Args: $1 - command name
# Exit code: 0 if exists, 1 otherwise
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# ============================================================================
# VERSION COMPARISON
# ============================================================================

# Compare versions (semantic versioning)
# Args: $1 - version 1, $2 - version 2
# Returns: 0 if v1 >= v2, 1 otherwise
version_gte() {
    local v1="$1"
    local v2="$2"

    if [ "$v1" = "$v2" ]; then
        return 0
    fi

    local IFS=.
    local i ver1=($v1) ver2=($v2)

    # Fill empty positions with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
        ver1[i]=0
    done

    for ((i=0; i<${#ver1[@]}; i++)); do
        if [[ -z ${ver2[i]} ]]; then
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]})); then
            return 0
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]})); then
            return 1
        fi
    done
    return 0
}

# ============================================================================
# SUDO UTILITIES
# ============================================================================

# Run command with sudo if available, otherwise run directly
# Args: $@ - command and arguments
# Exit code: exit code of the command
maybe_sudo() {
    if command_exists sudo; then
        sudo "$@"
    else
        "$@"
    fi
}

# ============================================================================
# PATH UTILITIES
# ============================================================================

# Check if directory is in PATH
# Args: $1 - directory path
# Exit code: 0 if in PATH, 1 otherwise
is_in_path() {
    local dir="$1"
    [[ ":$PATH:" == *":$dir:"* ]]
}

# Warn if install directory is not in PATH
# Args: $1 - install directory
warn_if_not_in_path() {
    local install_dir="$1"

    if ! is_in_path "$install_dir"; then
        log "WARNING: $install_dir is not in your PATH"
        log "Add this to your shell rc file (~/.bashrc or ~/.zshrc):"
        log "  export PATH=\"\$PATH:$install_dir\""
        echo ""
    fi
}
