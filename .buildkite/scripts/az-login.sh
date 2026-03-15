#!/bin/bash
set -euo pipefail

echo "--- :key: Retrieving Azure credentials from Buildkite Secrets"

AZURE_CLIENT_ID=$(buildkite-agent secret get AZURE_CLIENT_ID)
AZURE_CLIENT_SECRET=$(buildkite-agent secret get AZURE_CLIENT_SECRET)
AZURE_TENANT_ID=$(buildkite-agent secret get AZURE_TENANT_ID)

echo "✅ All secrets retrieved successfully"

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

Azure CLI is authenticated and ready for use.
EOF
