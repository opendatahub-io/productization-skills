#!/usr/bin/env bash

set -euo pipefail

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat >&2 <<'EOF'
Usage:
  vault.sh status
  vault.sh inspect-pem PEM_PATH
  vault.sh put KV_MOUNT SECRET_PATH APP_ID INSTALLATION_ID PEM_PATH TICKET
  vault.sh get APP_ID|INSTALLATION_ID KV_MOUNT SECRET_PATH
  vault.sh metadata KV_MOUNT SECRET_PATH
  vault.sh cleanup-pem PEM_PATH
EOF
    exit 2
}

validate_vault_transport() {
    local skip_verify=${VAULT_SKIP_VERIFY:-}

    case "${VAULT_ADDR:-}" in
        https://[![:space:]]*) ;;
        *) die 'VAULT_ADDR must be set to an https:// URL' ;;
    esac
    case "${skip_verify,,}" in
        ''|0|false) ;;
        *) die 'VAULT_SKIP_VERIFY must be unset, empty, 0, or false' ;;
    esac
    if [[ -n "${VAULT_CACERT:-}" ]]; then
        [[ -f "$VAULT_CACERT" && ! -L "$VAULT_CACERT" ]] ||
            die 'VAULT_CACERT must point to a regular certificate file'
    fi
}

validate_mount() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] ||
        die 'KV mount must contain only letters, digits, underscores, and hyphens'
}

validate_secret_path() {
    local path=$1
    [[ "$path" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] ||
        die 'secret path contains invalid characters'
    [[ "$path" != *..* && "$path" != *//* && "$path" != */ ]] ||
        die 'secret path contains an invalid path component'
}

validate_identifier() {
    [[ "$1" =~ ^[0-9]+$ ]] || die 'GitHub identifiers must contain only digits'
}

validate_ticket() {
    [[ "$1" =~ ^[A-Za-z][A-Za-z0-9]+-[0-9]+$ ]] ||
        die 'ticket must use the expected PROJECT-123 format'
}

validate_pem_path() {
    local pem_path=$1
    local mode owner current_user

    [[ "$pem_path" =~ ^/[A-Za-z0-9._/-]+$ ]] ||
        die 'PEM path must be absolute and contain no shell metacharacters or whitespace'
    if [[ "$pem_path" =~ (^|/)(tmp|Downloads|downloads|Dropbox|OneDrive|Nextcloud|backup|backups)(/|$) ||
        "$pem_path" == *"/Google Drive/"* ]]; then
        die 'PEM path must not be in temporary, download, backup, or sync storage'
    fi
    [[ -f "$pem_path" && ! -L "$pem_path" ]] ||
        die 'PEM path must be a regular file, not a symlink'

    mode=$(stat -c '%a' -- "$pem_path")
    [[ "$mode" = 600 ]] || die 'PEM file must have owner-only permissions (0600)'
    owner=$(stat -c '%u' -- "$pem_path")
    current_user=$(id -u)
    [[ "$owner" = "$current_user" ]] || die 'PEM file must be owned by the current user'
}

validate_kv_v2() {
    local mount=$1
    local mounts

    command -v jq >/dev/null 2>&1 || die 'jq is required to inspect Vault mount versions'
    mounts=$(vault secrets list -detailed -format=json)
    jq -e --arg mount "${mount%/}/" \
        '.[$mount].type == "kv" and (.[$mount].options.version // "") == "2"' \
        <<<"$mounts" >/dev/null ||
        die "Vault mount '$mount' must be a KV v2 mount"
}

inspect_pem() {
    local pem_path=$1
    local first_line

    validate_pem_path "$pem_path"
    IFS= read -r first_line < "$pem_path" || true
    case "$first_line" in
        '-----BEGIN RSA PRIVATE KEY-----'|'-----BEGIN PRIVATE KEY-----'|'-----BEGIN EC PRIVATE KEY-----') ;;
        *) die 'PEM file does not have a recognized private-key header' ;;
    esac
    printf 'PEM file is present, owner-only, and has a recognized private-key header\n'
}

put_secret() {
    local mount=$1
    local path=$2
    local app_id=$3
    local installation_id=$4
    local pem_path=$5
    local ticket=$6
    local -a vault_put_args

    validate_vault_transport
    validate_mount "$mount"
    validate_secret_path "$path"
    validate_identifier "$app_id"
    validate_identifier "$installation_id"
    validate_ticket "$ticket"
    validate_pem_path "$pem_path"
    validate_kv_v2 "$mount"

    vault_put_args=(kv put -cas=0 "-mount=$mount" "$path"
        "github_app_id=$app_id"
        "github_app_installation_id=$installation_id"
        "github_app_private_key=@$pem_path")
    vault "${vault_put_args[@]}"
    vault kv metadata put "-mount=$mount" "-custom-metadata=jira=$ticket" "$path"
}

get_identifier() {
    local field=$1
    local mount=$2
    local path=$3

    case "$field" in
        APP_ID) field=github_app_id ;;
        INSTALLATION_ID) field=github_app_installation_id ;;
        *) die 'only GitHub App identifiers may be retrieved' ;;
    esac
    validate_vault_transport
    validate_mount "$mount"
    validate_secret_path "$path"
    validate_kv_v2 "$mount"
    vault kv get -mount="$mount" -field="$field" "$path"
}

get_metadata() {
    local mount=$1
    local path=$2

    validate_vault_transport
    validate_mount "$mount"
    validate_secret_path "$path"
    validate_kv_v2 "$mount"
    vault kv metadata get -mount="$mount" "$path"
}

cleanup_pem() {
    local pem_path=$1

    validate_pem_path "$pem_path"
    rm -- "$pem_path"
    printf 'PEM file removed\n'
}

[[ $# -ge 1 ]] || usage
case "$1" in
    status)
        [[ $# = 1 ]] || usage
        validate_vault_transport
        vault status
        ;;
    inspect-pem)
        [[ $# = 2 ]] || usage
        inspect_pem "$2"
        ;;
    put)
        [[ $# = 7 ]] || usage
        put_secret "$2" "$3" "$4" "$5" "$6" "$7"
        ;;
    get)
        [[ $# = 4 ]] || usage
        get_identifier "$2" "$3" "$4"
        ;;
    metadata)
        [[ $# = 3 ]] || usage
        get_metadata "$2" "$3"
        ;;
    cleanup-pem)
        [[ $# = 2 ]] || usage
        cleanup_pem "$2"
        ;;
    *)
        usage
        ;;
esac
