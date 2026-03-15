#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# bicep-whatif.sh
# Runs az deployment what-if for any of the four Azure deployment scopes:
#   subscription | tenant | managementgroup | resourcegroup
#
# Configuration (env vars or Buildkite meta-data from block step):
#   AZURE_DEPLOYMENT_TYPE      - required - subscription|tenant|managementgroup|resourcegroup
#   AZURE_LOCATION             - required - e.g. australiaeast
#   AZURE_SUBSCRIPTION_ID      - required for scope: subscription, resourcegroup
#   AZURE_MANAGEMENT_GROUP_ID  - required for scope: managementgroup
#   AZURE_RESOURCE_GROUP_NAME  - required for scope: resourcegroup
#   BICEP_DEPLOYMENT_NAME      - required - name of the ARM deployment
#   BICEP_TEMPLATE_FILE_PATH   - required - path to the .bicep file (to derive JSON name)
#
# Expects the compiled deploy/ artifact to already be present in the workspace
# (downloaded by the pipeline step before calling this script).
# ---------------------------------------------------------------------------

BUILD_DIR="deploy"

# ---------------------------------------------------------------------------
# Read config: env var takes priority, then Buildkite meta-data.
# ---------------------------------------------------------------------------
AZURE_DEPLOYMENT_TYPE="${AZURE_DEPLOYMENT_TYPE:-subscription}"
BICEP_DEPLOYMENT_NAME="${BICEP_DEPLOYMENT_NAME:?BICEP_DEPLOYMENT_NAME env var is required}"
BICEP_TEMPLATE_FILE_PATH="${BICEP_TEMPLATE_FILE_PATH:?BICEP_TEMPLATE_FILE_PATH env var is required}"

if [ -z "${AZURE_LOCATION:-}" ]; then
  AZURE_LOCATION="$(buildkite-agent meta-data get location 2>/dev/null || echo '')"
fi
if [ -z "${AZURE_SUBSCRIPTION_ID:-}" ]; then
  AZURE_SUBSCRIPTION_ID="$(buildkite-agent meta-data get subscription_id 2>/dev/null || echo '')"
fi

AZURE_MANAGEMENT_GROUP_ID="${AZURE_MANAGEMENT_GROUP_ID:-}"
AZURE_RESOURCE_GROUP_NAME="${AZURE_RESOURCE_GROUP_NAME:-}"

# ---------------------------------------------------------------------------
# Locate compiled template and parameter file
# ---------------------------------------------------------------------------
TEMPLATE_JSON="${BUILD_DIR}/$(basename "${BICEP_TEMPLATE_FILE_PATH%.bicep}").json"

if [ ! -f "${TEMPLATE_JSON}" ]; then
  echo "❌ Compiled template not found: ${TEMPLATE_JSON}"
  echo "Contents of ${BUILD_DIR}/:"
  ls -la "${BUILD_DIR}/" || echo "(directory not found)"
  exit 1
fi

PARAM_PATH="$(find "${BUILD_DIR}" -name "*.parameters.json" | head -1 || echo '')"

echo "--- :information_source: What-If configuration"
echo "  Deployment type: ${AZURE_DEPLOYMENT_TYPE}"
echo "  Deployment name: ${BICEP_DEPLOYMENT_NAME}"
echo "  Location:        ${AZURE_LOCATION}"
echo "  Template:        ${TEMPLATE_JSON}"
echo "  Parameters:      ${PARAM_PATH:-<none>}"

# Build optional parameters argument
PARAM_ARG=()
if [ -n "${PARAM_PATH}" ]; then
  PARAM_ARG=(--parameters "@${PARAM_PATH}")
fi

echo "--- :mag: Running What-If deployment"

case "${AZURE_DEPLOYMENT_TYPE}" in

  subscription)
    if [ -z "${AZURE_SUBSCRIPTION_ID}" ]; then
      echo "❌ AZURE_SUBSCRIPTION_ID is required for subscription-scope deployments"
      exit 1
    fi
    az account set --subscription "${AZURE_SUBSCRIPTION_ID}"
    az deployment sub what-if \
      --name     "${BICEP_DEPLOYMENT_NAME}" \
      --location "${AZURE_LOCATION}" \
      --subscription "${AZURE_SUBSCRIPTION_ID}" \
      --template-file "${TEMPLATE_JSON}" \
      "${PARAM_ARG[@]+"${PARAM_ARG[@]}"}"
    ;;

  tenant)
    az deployment tenant what-if \
      --name     "${BICEP_DEPLOYMENT_NAME}" \
      --location "${AZURE_LOCATION}" \
      --template-file "${TEMPLATE_JSON}" \
      "${PARAM_ARG[@]+"${PARAM_ARG[@]}"}"
    ;;

  managementgroup)
    if [ -z "${AZURE_MANAGEMENT_GROUP_ID}" ]; then
      echo "❌ AZURE_MANAGEMENT_GROUP_ID is required for managementgroup-scope deployments"
      exit 1
    fi
    az deployment mg what-if \
      --name                "${BICEP_DEPLOYMENT_NAME}" \
      --location            "${AZURE_LOCATION}" \
      --management-group-id "${AZURE_MANAGEMENT_GROUP_ID}" \
      --template-file       "${TEMPLATE_JSON}" \
      "${PARAM_ARG[@]+"${PARAM_ARG[@]}"}"
    ;;

  resourcegroup)
    if [ -z "${AZURE_SUBSCRIPTION_ID}" ] || [ -z "${AZURE_RESOURCE_GROUP_NAME}" ]; then
      echo "❌ AZURE_SUBSCRIPTION_ID and AZURE_RESOURCE_GROUP_NAME are required for resourcegroup-scope deployments"
      exit 1
    fi
    az account set --subscription "${AZURE_SUBSCRIPTION_ID}"
    az deployment group what-if \
      --name           "${BICEP_DEPLOYMENT_NAME}" \
      --resource-group "${AZURE_RESOURCE_GROUP_NAME}" \
      --template-file  "${TEMPLATE_JSON}" \
      "${PARAM_ARG[@]+"${PARAM_ARG[@]}"}"
    ;;

  *)
    echo "❌ Unknown deployment type: '${AZURE_DEPLOYMENT_TYPE}'"
    echo "   Valid values: subscription | tenant | managementgroup | resourcegroup"
    exit 1
    ;;

esac

buildkite-agent annotate --style info --context bicep-whatif <<EOF
### :mag: What-If Complete

**Deployment type:** \`${AZURE_DEPLOYMENT_TYPE}\`
**Template:** \`${TEMPLATE_JSON}\`
**Deployment name:** \`${BICEP_DEPLOYMENT_NAME}\`

Review the what-if output above, then approve the deployment block step to proceed.
EOF

echo "✅ What-If complete"
