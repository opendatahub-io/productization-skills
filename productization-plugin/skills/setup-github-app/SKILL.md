---
name: setup-github-app
description: Walk through creating a GitHub App and storing its credentials in Vault. Use when the user needs to create or configure a GitHub App for an automation workflow.
disable-model-invocation: true
allowed-tools: Bash(vault status:*),Bash(vault kv put:*),Bash(vault kv get:*),Bash(vault kv metadata put:*),Bash(vault kv metadata get:*),Bash(test:*),Bash(head:*),Read,AskUserQuestion
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
6. Generate a private key from the app's **General** page and save the downloaded `.pem` file locally.

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

Ask the user for the path to the `.pem` private key file. If they have not
generated one, direct them to the app's **General** page to generate and save
one.

Verify the file exists and inspect only its first line:

```bash
test -f "<pem-path>"
head -1 "<pem-path>"
```

The first line should identify a PEM private key, such as
`-----BEGIN RSA PRIVATE KEY-----` or `-----BEGIN PRIVATE KEY-----`. Never print
the full file, include it in a command argument, or log its contents.

## Step 6: Store credentials in Vault

Confirm the following immediately before writing:

- Vault is authenticated and the intended Vault address is configured by the user's environment
- The exact KV mount and secret path
- The App ID and Installation ID
- The request or ticket reference

Check Vault access:

```bash
vault status
```

Write the credentials using Vault's file-value syntax so the private key is
read from disk and is not exposed in shell history:

```bash
vault kv put -mount="<kv-mount>" "<secret-path>" \
  github_app_id="<app-id>" \
  github_app_installation_id="<installation-id>" \
  github_app_private_key=@"<pem-path>"

vault kv metadata put -mount="<kv-mount>" \
  -custom-metadata=jira="<jira-ticket>" \
  "<secret-path>"
```

Do not put the PEM contents in an environment variable or command substitution.
Run the command only after confirmation and report the result.

## Step 7: Verify

Verify the secret without printing its values:

```bash
vault kv get -mount="<kv-mount>" -field=github_app_id "<secret-path>"
vault kv get -mount="<kv-mount>" -field=github_app_installation_id "<secret-path>"
vault kv metadata get -mount="<kv-mount>" "<secret-path>"
```

Do not retrieve or display `github_app_private_key`. Report the secret path and
the non-secret identifiers and ticket metadata, then confirm success.
