#!/bin/bash
# az-login-oidc.sh
#
# Authenticates the Buildkite agent to Azure using OpenID Connect (OIDC) /
# Workload Identity Federation. No client secret is stored anywhere — the
# Buildkite agent issues a short-lived JWT, which is exchanged for an Azure
# access token.
#
# Required environment variables (NOT secrets — these are identifiers):
#   ARM_CLIENT_ID       The App Registration's Application (client) ID.
#   ARM_TENANT_ID       The Microsoft Entra Directory (tenant) ID.
#   ARM_SUBSCRIPTION_ID The target Azure subscription ID.
#
# Optional:
#   BUILDKITE_OIDC_SUBJECT_CLAIM
#       Override the default subject claim. Allowed values:
#         pipeline_id (default — one FIC per pipeline)
#         cluster_id  (one FIC per Buildkite cluster)
#         queue_id    (one FIC per agent queue)
#         organization_id (one FIC for the whole org)
#       The corresponding Federated Identity Credential's "Subject identifier"
#       in Azure must match the resolved UUID.
#
#   AZURE_OIDC_AUDIENCE
#       Override the audience. Defaults to api://AzureADTokenExchange.
#       Use api://AzureADTokenExchangeUSGov for Azure Government, or
#       api://AzureADTokenExchangeChina for Azure China (21Vianet).
#
# Requires Buildkite agent v3.106.0 or later.

set -euo pipefail

: "${ARM_CLIENT_ID:?ARM_CLIENT_ID env var is required}"
: "${ARM_TENANT_ID:?ARM_TENANT_ID env var is required}"
: "${ARM_SUBSCRIPTION_ID:?ARM_SUBSCRIPTION_ID env var is required}"

AUDIENCE="${AZURE_OIDC_AUDIENCE:-api://AzureADTokenExchange}"

echo "--- :key: Requesting OIDC token from Buildkite"
echo "Audience:        ${AUDIENCE}"

OIDC_ARGS=(--audience "${AUDIENCE}")

if [ -n "${BUILDKITE_OIDC_SUBJECT_CLAIM:-}" ]; then
  echo "Subject claim:   ${BUILDKITE_OIDC_SUBJECT_CLAIM}"
  OIDC_ARGS+=(--subject-claim "${BUILDKITE_OIDC_SUBJECT_CLAIM}")
else
  echo "Subject claim:   pipeline_id (default)"
fi

BUILDKITE_OIDC_TOKEN=$(buildkite-agent oidc request-token "${OIDC_ARGS[@]}")
export BUILDKITE_OIDC_TOKEN

echo "✅ OIDC token issued"

echo "--- :azure: Logging in to Azure with federated token"

az login --service-principal \
  --username        "${ARM_CLIENT_ID}" \
  --tenant          "${ARM_TENANT_ID}" \
  --federated-token "${BUILDKITE_OIDC_TOKEN}" \
  --output none

az account set --subscription "${ARM_SUBSCRIPTION_ID}"

# Mirror the env vars used by the existing scripts (which read AZURE_*).
# This lets the OIDC login script drop in alongside the existing Bicep
# scripts without touching them.
export AZURE_CLIENT_ID="${ARM_CLIENT_ID}"
export AZURE_TENANT_ID="${ARM_TENANT_ID}"
export AZURE_SUBSCRIPTION_ID="${ARM_SUBSCRIPTION_ID}"

echo "✅ Federated login successful"

ACCOUNT_NAME=$(az account show --query name -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

echo "Account:         ${ACCOUNT_NAME}"
echo "Subscription ID: ${SUBSCRIPTION_ID}"

buildkite-agent annotate --style success --context azure-oidc-login <<EOF
### :white_check_mark: Azure OIDC Authentication Successful

**Account:** \`${ACCOUNT_NAME}\`
**Subscription ID:** \`${SUBSCRIPTION_ID}\`
**Subject claim:** \`${BUILDKITE_OIDC_SUBJECT_CLAIM:-pipeline_id (default)}\`
**Audience:** \`${AUDIENCE}\`

No client secret was used — authenticated via Workload Identity Federation.
EOF
