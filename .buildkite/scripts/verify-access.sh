#!/bin/bash
set -euo pipefail

echo "--- :mag: Verifying Azure access"

echo "Current account:"
az account show --output table

echo ""
echo "Available resource groups:"
az group list --output table

RG_COUNT=$(az group list --query "length([])" --output tsv)

buildkite-agent annotate --style info --context azure-verify <<EOF
### :mag: Azure Access Verified

**Resource Groups Found:** ${RG_COUNT}

You can now use Azure CLI in subsequent pipeline steps.
EOF
