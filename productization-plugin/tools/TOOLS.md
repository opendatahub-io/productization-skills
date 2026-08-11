# Tools Installation Scripts Guide

This document provides guidelines for creating and maintaining tool installation scripts in the `productization-plugin/tools/` directory.

## Overview

The `tools/` directory contains installation scripts for CLI tools used by skills. Each tool has its own subdirectory with a standardized `install.sh` script.

**Design Philosophy:**
- Keep scripts simple and focused
- Reuse common functionality via `common.sh`
- Support Linux only (x86_64 and ARM64)
- Minimal options (only `--check`)
- Let the tools do one thing well: install if missing

## Directory Structure

```
productization-plugin/tools/
├── common.sh              # Shared library with common functions
├── TOOLS.md              # This guide
├── <tool-name>/
│   └── install.sh        # Installation script for the tool
└── ...
```

## Common Library (`common.sh`)

**IMPORTANT:** Always check `common.sh` first before writing new functions. Reuse existing functions to maintain consistency and reduce duplication.

### Available Functions

#### Logging
- `log()` - Simple logging to stdout

#### Platform Detection
- `detect_arch()` - Detect architecture (returns: `x86_64` or `aarch64`)
- `verify_linux()` - Verify running on Linux (exits with error if not)

#### Command Utilities
- `command_exists()` - Check if command exists in PATH

#### Version Comparison
- `version_gte()` - Semantic version comparison (returns 0 if v1 >= v2)

#### PATH Utilities
- `is_in_path()` - Check if directory is in PATH
- `warn_if_not_in_path()` - Warn user if install directory not in PATH

### Using Common Library

**Always source the common library at the top of your script:**

```bash
#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# LOAD COMMON LIBRARY
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common.sh
source "$SCRIPT_DIR/../common.sh"
```

## Platform Support

**Supported Platforms:**
- ✓ Linux x86_64 (amd64)
- ✓ Linux ARM64 (aarch64)

**NOT Supported:**
- ✗ macOS (Darwin)
- ✗ Windows
- ✗ Other architectures (ARM32, i386, etc.)

**Rationale:** Focus on Linux containers and CI/CD environments where these scripts are most commonly used.

## Script Structure Template

Use this template when creating a new tool installer:

```bash
#!/usr/bin/env bash
#
# <Tool Name> Installation Script (Linux Only)
#
# This script installs or updates <tool> on Linux systems.
# Supports: x86_64 and ARM64 (aarch64) architectures only.
#
# Usage:
#   ./install.sh                # Check and install <tool>
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
# renovate: datasource=github-releases depName=<org>/<repo>
TOOL_VERSION="x.y.z"

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

TMP_DIR="${TMP_DIR:-/tmp/<tool>-install}"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Get installed <tool> version
get_tool_version() {
    if command_exists <tool>; then
        # Extract version from tool output
        <tool> --version 2>&1 | grep -oP '<pattern>' || echo "unknown"
    else
        echo "not_installed"
    fi
}

# ============================================================================
# TOOL INSTALLATION
# ============================================================================

check_tool() {
    local current_version
    current_version=$(get_tool_version)

    if [ "$current_version" = "not_installed" ]; then
        log "<Tool> is not installed"
        return 1
    fi

    log "<Tool> version: $current_version"

    if version_gte "$current_version" "$TOOL_VERSION"; then
        log "<Tool> is up to date (>= $TOOL_VERSION)"
        return 0
    else
        log "<Tool> version $current_version is older than required $TOOL_VERSION"
        return 1
    fi
}

install_tool() {
    local arch
    arch=$(detect_arch)

    log "Installing <Tool> v${TOOL_VERSION} for Linux $arch..."

    # Verify we're on Linux
    verify_linux || return 1

    # Create temporary directory
    mkdir -p "$TMP_DIR"

    # Download based on architecture
    local download_url
    if [ "$arch" = "x86_64" ]; then
        download_url="<url-for-x86_64>"
    else
        download_url="<url-for-aarch64>"
    fi

    log "Downloading from: $download_url"

    # Download and install (adapt based on tool's distribution format)
    # For binary:
    curl -fsSL "$download_url" -o "${TMP_DIR}/<tool>"
    chmod +x "${TMP_DIR}/<tool>"

    # For archive (zip/tar.gz):
    # curl -fsSL "$download_url" -o "${TMP_DIR}/<tool>.zip"
    # unzip -q "${TMP_DIR}/<tool>.zip" -d "${TMP_DIR}"
    # chmod +x "${TMP_DIR}/<tool>/bin/<tool>"

    # Install to INSTALL_DIR
    log "Installing to: $INSTALL_DIR"
    if [ "$INSTALL_DIR" = "/usr/local/bin" ]; then
        sudo mv "${TMP_DIR}/<tool>" "$INSTALL_DIR/<tool>"
    else
        mv "${TMP_DIR}/<tool>" "$INSTALL_DIR/<tool>"
    fi

    # Cleanup
    rm -rf "$TMP_DIR"

    # Verify installation
    if check_tool; then
        log "✓ <Tool> installed successfully"
        return 0
    else
        log "✗ <Tool> installation verification failed" >&2
        return 1
    fi
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================

main() {
    local check_only=false

    # Parse arguments
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

    # Ensure INSTALL_DIR and TMP_DIR exist
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$TMP_DIR"

    # Check if INSTALL_DIR is in PATH
    warn_if_not_in_path "$INSTALL_DIR"

    # Execute based on options
    if [ "$check_only" = true ]; then
        check_tool
        exit $?
    fi

    # Install if needed
    if ! check_tool; then
        echo ""
        log "Installing <Tool>..."
        install_tool
    fi
}

# Run main function
main "$@"
```

## Guidelines

### DO

✓ **Use common.sh functions** - Always check if a function exists in `common.sh` before implementing it yourself

✓ **Support Linux x86_64 and ARM64 only** - Use `detect_arch()` and `verify_linux()` from common.sh

✓ **Version tracking with Renovate** - Use the `# renovate:` comment format for automatic updates

✓ **Smart install directory** - Prefer `/usr/local/bin` (writable), fallback to `~/.local/bin`

✓ **Verify installation** - Always call `check_tool()` after installation to verify success

✓ **Cleanup temporary files** - Always remove `$TMP_DIR` after installation

✓ **Use `set -euo pipefail`** - Fail fast on errors

✓ **Minimal options** - Only support `--check` flag

✓ **Single responsibility** - Script should do one thing: install the tool if not present

✓ **Clear logging** - Use `log()` for all output, use `✓` and `✗` for success/failure

✓ **Make scripts executable** - `chmod +x install.sh`

### DON'T

✗ **Don't add `--help` or `-h`** - Keep scripts simple, usage is in header comment

✗ **Don't add `--version`** - Not needed, version info is in the script itself

✗ **Don't add `--force`** - Scripts should be idempotent, re-running is safe

✗ **Don't support macOS or Windows** - Linux only

✗ **Don't support other architectures** - x86_64 and ARM64 only

✗ **Don't duplicate common.sh functions** - Reuse existing functions

✗ **Don't use relative paths in source** - Always calculate `$SCRIPT_DIR` first

✗ **Don't hardcode paths** - Use `$INSTALL_DIR` and `$TMP_DIR` variables

✗ **Don't forget cleanup** - Always `rm -rf "$TMP_DIR"` after installation

✗ **Don't create complex argument parsing** - Only `--check` is needed

## Version Tracking with Renovate

Use the following comment format to enable automatic dependency updates:

```bash
# renovate: datasource=github-releases depName=<org>/<repo>
TOOL_VERSION="x.y.z"
```

**Common datasources:**
- `github-releases` - GitHub releases
- `npm` - npm packages
- `pypi` - Python packages
- `docker` - Docker images

**Example:**
```bash
# renovate: datasource=github-releases depName=aws/aws-cli
AWS_CLI_VERSION="2.15.17"

# renovate: datasource=github-releases depName=jqlang/jq
JQ_VERSION="1.7.1"
```

## Installation Patterns

### Pattern 1: Single Binary Download

For tools distributed as a single binary (like jq):

```bash
install_tool() {
    local arch
    arch=$(detect_arch)

    verify_linux || return 1
    mkdir -p "$TMP_DIR"

    # Determine download URL based on architecture
    local download_url
    if [ "$arch" = "x86_64" ]; then
        download_url="https://example.com/tool-linux-amd64"
    else
        download_url="https://example.com/tool-linux-arm64"
    fi

    log "Downloading from: $download_url"
    curl -fsSL "$download_url" -o "${TMP_DIR}/tool"
    chmod +x "${TMP_DIR}/tool"

    log "Installing to: $INSTALL_DIR"
    if [ "$INSTALL_DIR" = "/usr/local/bin" ]; then
        sudo mv "${TMP_DIR}/tool" "$INSTALL_DIR/tool"
    else
        mv "${TMP_DIR}/tool" "$INSTALL_DIR/tool"
    fi

    rm -rf "$TMP_DIR"
}
```

### Pattern 2: Archive Extraction

For tools distributed as zip/tar.gz (like AWS CLI):

```bash
install_tool() {
    local arch
    arch=$(detect_arch)

    verify_linux || return 1

    # Check for required tools
    if ! command_exists unzip; then
        log "ERROR: unzip is required but not installed" >&2
        return 1
    fi

    mkdir -p "$TMP_DIR"
    cd "$TMP_DIR"

    # Download archive
    local download_url
    if [ "$arch" = "x86_64" ]; then
        download_url="https://example.com/tool-linux-x86_64.zip"
    else
        download_url="https://example.com/tool-linux-aarch64.zip"
    fi

    log "Downloading from: $download_url"
    curl -fsSL "$download_url" -o "tool.zip"

    log "Extracting..."
    unzip -q tool.zip

    log "Installing to: $INSTALL_DIR"
    if [ "$INSTALL_DIR" = "/usr/local/bin" ]; then
        sudo ./tool/install --update
    else
        ./tool/install --install-dir "$HOME/.local/tool" --bin-dir "$INSTALL_DIR" --update
    fi

    cd - >/dev/null
    rm -rf "$TMP_DIR"
}
```

### Pattern 3: Package Manager Installation

For tools best installed via package manager:

```bash
install_tool() {
    verify_linux || return 1

    # Detect package manager
    if command_exists apt-get; then
        log "Installing via apt-get..."
        sudo apt-get update
        sudo apt-get install -y tool
    elif command_exists yum; then
        log "Installing via yum..."
        sudo yum install -y tool
    elif command_exists dnf; then
        log "Installing via dnf..."
        sudo dnf install -y tool
    else
        log "ERROR: No supported package manager found" >&2
        return 1
    fi
}
```

## Testing Your Script

Before committing, test your script:

```bash
# 1. Check syntax
bash -n tools/<tool>/install.sh

# 2. Test --check when tool is not installed
tools/<tool>/install.sh --check

# 3. Test installation
tools/<tool>/install.sh

# 4. Test --check when tool is installed
tools/<tool>/install.sh --check

# 5. Test idempotency (should not reinstall)
tools/<tool>/install.sh

# 6. Verify the tool works
<tool> --version
```

## Example: Adding a New Tool

Let's walk through adding a hypothetical tool called `kubectl`:

### Step 1: Create Directory

```bash
mkdir -p productization-plugin/tools/kubectl
```

### Step 2: Create install.sh

```bash
touch productization-plugin/tools/kubectl/install.sh
chmod +x productization-plugin/tools/kubectl/install.sh
```

### Step 3: Use the Template

Copy the template from this guide and customize:

1. Replace `<Tool Name>` with `kubectl`
2. Replace `<tool>` placeholders with `kubectl`
3. Add Renovate comment with proper datasource
4. Implement `get_tool_version()` to extract version
5. Implement download URLs for x86_64 and aarch64
6. Choose appropriate installation pattern

### Step 4: Test

```bash
# Check syntax
bash -n tools/kubectl/install.sh

# Test installation
tools/kubectl/install.sh

# Verify
kubectl version
```

### Step 5: Document

Update skill documentation to reference the new tool:

```markdown
**Installation:**
```bash
# kubectl (required)
../../../tools/kubectl/install.sh          # Check and install kubectl
../../../tools/kubectl/install.sh --check  # Check only, don't install
```

## Common Pitfalls

### 1. Not sourcing common.sh correctly

**Wrong:**
```bash
source ../common.sh  # Relative path fails in different contexts
```

**Correct:**
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"
```

### 2. Hardcoding architecture names

**Wrong:**
```bash
download_url="https://example.com/tool-amd64"  # Hardcoded
```

**Correct:**
```bash
arch=$(detect_arch)  # Use common.sh function
if [ "$arch" = "x86_64" ]; then
    download_url="https://example.com/tool-amd64"
else
    download_url="https://example.com/tool-arm64"
fi
```

### 3. Not verifying Linux platform

**Wrong:**
```bash
install_tool() {
    # Assumes Linux, will fail on macOS
    curl -fsSL "https://example.com/tool-linux" -o tool
}
```

**Correct:**
```bash
install_tool() {
    verify_linux || return 1  # Use common.sh function
    curl -fsSL "https://example.com/tool-linux" -o tool
}
```

### 4. Forgetting to clean up

**Wrong:**
```bash
install_tool() {
    mkdir -p "$TMP_DIR"
    # ... installation ...
    # Forgot to cleanup!
}
```

**Correct:**
```bash
install_tool() {
    mkdir -p "$TMP_DIR"
    # ... installation ...
    rm -rf "$TMP_DIR"  # Always cleanup
}
```

### 5. Not making script executable

**Wrong:**
```bash
# Script has no execute permission
-rw-r--r-- install.sh
```

**Correct:**
```bash
chmod +x tools/<tool>/install.sh
# Now it has execute permission
-rwxr-xr-x install.sh
```

## Checklist for New Tool Scripts

Use this checklist when creating a new tool installer:

- [ ] Created directory: `tools/<tool>/`
- [ ] Created script: `tools/<tool>/install.sh`
- [ ] Made script executable: `chmod +x`
- [ ] Sourced `common.sh` correctly
- [ ] Added Renovate version tracking comment
- [ ] Used `detect_arch()` from common.sh
- [ ] Used `verify_linux()` from common.sh
- [ ] Used `command_exists()` from common.sh
- [ ] Used `version_gte()` from common.sh
- [ ] Used `warn_if_not_in_path()` from common.sh
- [ ] Implemented `get_tool_version()` function
- [ ] Implemented `check_tool()` function
- [ ] Implemented `install_tool()` function
- [ ] Only supports `--check` flag (no `--help`, `--version`, `--force`)
- [ ] Only supports Linux x86_64 and ARM64
- [ ] Cleans up temporary files
- [ ] Verifies installation after completing
- [ ] Tested with `bash -n` for syntax
- [ ] Tested installation flow
- [ ] Tested idempotency (running twice)
- [ ] Updated skill documentation (SKILL.md)

## Maintenance

### Updating Common Library

When adding a new function to `common.sh`:

1. Document the function with comments
2. Add it to the appropriate section (Logging, Platform Detection, etc.)
3. Update this guide's "Available Functions" section
4. Test with existing scripts to ensure no breakage

### Updating Existing Scripts

When updating a tool installer:

1. Check if the change should go in `common.sh` instead
2. Maintain backward compatibility
3. Update version tracking comments if needed
4. Test all affected scripts

### Deprecating a Tool

If a tool is no longer needed:

1. Remove the tool directory: `rm -rf tools/<tool>/`
2. Update skill documentation to remove references
3. Update any dependency checker scripts

## Questions?

When in doubt:

1. Check existing scripts (`aws-cli/install.sh`, `jq/install.sh`)
2. Check `common.sh` for available functions
3. Follow the template in this guide
4. Keep it simple - don't add unnecessary features

## Version

This guide follows the conventions established in February 2025 for the Productization Skills Plugin project.
