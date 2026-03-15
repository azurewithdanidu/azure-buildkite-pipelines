#!/bin/bash
set -euo pipefail

echo "--- :key: Retrieving Azure credentials"

USE_SECRETS=true

# Try Buildkite Secrets first
if AZURE_CLIENT_ID=$(buildkite-agent secret get AZURE_CLIENT_ID 2>/dev/null) && [ -n "${AZURE_CLIENT_ID}" ]; then
  echo "✅ AZURE_CLIENT_ID from Buildkite Secrets"
else
  echo "⚠️  AZURE_CLIENT_ID not found in Buildkite Secrets"
  USE_SECRETS=false
fi

if AZURE_CLIENT_SECRET=$(buildkite-agent secret get AZURE_CLIENT_SECRET 2>/dev/null) && [ -n "${AZURE_CLIENT_SECRET}" ]; then
  echo "✅ AZURE_CLIENT_SECRET from Buildkite Secrets"
else
  echo "⚠️  AZURE_CLIENT_SECRET not found in Buildkite Secrets"
  USE_SECRETS=false
fi

if AZURE_TENANT_ID=$(buildkite-agent secret get AZURE_TENANT_ID 2>/dev/null) && [ -n "${AZURE_TENANT_ID}" ]; then
  echo "✅ AZURE_TENANT_ID from Buildkite Secrets"
else
  echo "⚠️  AZURE_TENANT_ID not found in Buildkite Secrets"
  USE_SECRETS=false
fi

# Fall back to environment variables if secrets failed
if [ "${USE_SECRETS}" = "false" ]; then
  echo "--- :warning: Falling back to environment variables"

  if [ -z "${AZURE_CLIENT_ID:-}" ] || [ -z "${AZURE_CLIENT_SECRET:-}" ] || [ -z "${AZURE_TENANT_ID:-}" ]; then
    echo "❌ No credentials found in Buildkite Secrets or environment variables"
    buildkite-agent annotate --style error --context azure-login <<EOF
### :x: Azure Credentials Not Found

**Option 1 - Buildkite Secrets (recommended):**
Go to Pipeline Settings → Secrets and add:
- \`AZURE_CLIENT_ID\`
- \`AZURE_CLIENT_SECRET\`
- \`AZURE_TENANT_ID\`

Note: Agent must be v3.27.0+ to support secrets.

**Option 2 - Environment Variables (for testing only):**
Go to Pipeline Settings → Environment Variables and add the same keys.
EOF
    exit 1
  fi

  echo "✅ Using credentials from environment variables"
  buildkite-agent annotate --style warning --context azure-login <<EOF
### :warning: Using Environment Variables Instead of Secrets

Buildkite Secrets were not found. Using environment variables as fallback.

For production, configure Buildkite Secrets (Pipeline Settings → Secrets).
Agent must be v3.27.0+ to read secrets.
EOF
fi

echo "--- :azure: Logging in to Azure"

az login --service-principal \
  --username "${AZURE_CLIENT_ID}" \
  --password "${AZURE_CLIENT_SECRET}" \
  --tenant "${AZURE_TENANT_ID}" \
  --output none

echo "✅ Login successful"

ACCOUNT_NAME=$(az account show --query name -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

echo "Account:         ${ACCOUNT_NAME}"
echo "Subscription ID: ${SUBSCRIPTION_ID}"

buildkite-agent annotate --style success --context azure-login <<EOF
### :white_check_mark: Azure Authentication Successful

**Account:** \`${ACCOUNT_NAME}\`
**Subscription ID:** \`${SUBSCRIPTION_ID}\`
**Credentials source:** $([ "${USE_SECRETS}" = "true" ] && echo "Buildkite Secrets" || echo "Environment Variables")
EOF
