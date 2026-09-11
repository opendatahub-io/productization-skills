---
name: setup-github-app
description: Walk through creating a GitHub App and storing its credentials in Vault. Use when the user needs to create or configure a GitHub App for an automation workflow.
disable-model-invocation: true
allowed-tools: Bash(*/setup-github-app/scripts/vault.sh:*),Bash(*/tools/vault/install.sh:*),Bash(*/tools/jq/install.sh:*),Read,AskUserQuestion
---

# Set Up a GitHub App

Guide the user through creating a GitHub App and storing its credentials in
Vault. Work through these steps interactively, confirming each one before
proceeding. Never ask the user to paste a private key into the conversation.

## Step 1: Check for an existing GitHub App

Ask the user whether the app already exists. If it does, skip app creation and
continue with installation and credential collection.

## Step 2: Create the GitHub App

Ask for:

- The app name
- The GitHub organization and, if applicable, repositories where it will be installed
- The requested repository and organization permissions
- The request or ticket reference
- The Vault KV mount and secret path where the credentials should be stored

If the user is responding to an existing request, use those details instead of
asking again. Do not invent a Vault path.

Walk the user through:

1. Go to **Settings > Developer settings > GitHub Apps > New GitHub App** in the target organization.
2. Set the requested app name and a homepage URL.
3. Uncheck **Webhook > Active**, unless the request requires webhooks.
4. Grant exactly the requested repository and organization permissions.
5. Click **Create GitHub App**.
6. Generate a private key from the app's **General** page. Save it directly to a
   controlled, owner-only location such as
   `~/.config/github-app-keys/<app-name>.pem`, not Downloads, temporary storage,
   a backup directory, or a sync service. Ensure the file is a regular file
   owned by the current user with mode `0600`.

Tell the user to note:

- The **App ID**
- The **Installation ID** after the app is installed

## Step 3: Install the app

Ask the user to install the app on the requested organization or repositories.
The **Installation ID** is in the installation URL or the app's installation
details. It is not the same as the App ID.

## Step 4: Collect credentials

Store these values in Vault:

- `github_app_id`
- `github_app_installation_id`
- `github_app_private_key`

Store the request or ticket reference as Vault KV custom metadata.

## Step 5: Private key

Ask the user for the absolute path to the `.pem` private key file. If they have
not generated one, direct them to the app's **General** page to generate it in a
controlled owner-only location. Do not accept paths in Downloads, temporary,
backup, or synchronized directories.

Ensure Vault's CLI and `jq` are installed before using the helper:

```bash
${CLAUDE_SKILL_DIR}/../../tools/vault/install.sh --check
${CLAUDE_SKILL_DIR}/../../tools/jq/install.sh --check
```

If either check fails, install the missing tool with the corresponding script.
Inspect the file without printing its contents:

```bash
${CLAUDE_SKILL_DIR}/scripts/vault.sh inspect-pem '<pem-path>'
```

The helper checks the file owner, mode, location, and PEM header. Never print
the full file, include its contents in a command argument, or log its contents.

## Step 6: Store credentials in Vault

Confirm the following immediately before writing:

- Vault is authenticated and `VAULT_ADDR` is configured by the user's environment with an `https://` scheme
- `VAULT_SKIP_VERIFY` is unset, empty, `0`, or `false`; when Vault uses a private certificate authority, `VAULT_CACERT` points to its certificate file
- The exact KV mount and secret path
- The App ID and Installation ID
- The request or ticket reference

Check Vault access:

```bash
${CLAUDE_SKILL_DIR}/scripts/vault.sh status
```

The helper rejects non-HTTPS endpoints, unverifiable TLS, non-KV-v2 mounts, and
invalid input. It uses Vault's file-value syntax so the private key is read from
disk and is not exposed in shell history. Validate every AskUserQuestion value
before invoking it. Reject shell metacharacters, whitespace, `..`, and command
substitution syntax; pass each validated value as a separate single-quoted
argument, never by generating Bash source from the value. The helper repeats
these allowlist checks.

```bash
${CLAUDE_SKILL_DIR}/scripts/vault.sh put '<kv-mount>' '<secret-path>' \
  '<app-id>' '<installation-id>' '<pem-path>' '<jira-ticket>'
```

The helper requires a KV v2 mount and uses `-cas=0`, so it refuses to overwrite
an existing secret. Do not put PEM contents in an environment variable or
command substitution. Run the command only after confirmation and report the
result.

## Step 7: Verify

Verify the secret without printing its values:

```bash
${CLAUDE_SKILL_DIR}/scripts/vault.sh get APP_ID '<kv-mount>' '<secret-path>'
${CLAUDE_SKILL_DIR}/scripts/vault.sh get INSTALLATION_ID '<kv-mount>' '<secret-path>'
${CLAUDE_SKILL_DIR}/scripts/vault.sh metadata '<kv-mount>' '<secret-path>'
```

Do not retrieve or display `github_app_private_key`. Report the secret path and
the non-secret identifiers and ticket metadata, then confirm success. After the
verification succeeds, confirm once more that the local copy may be removed and
run:

```bash
${CLAUDE_SKILL_DIR}/scripts/vault.sh cleanup-pem '<pem-path>'
```
