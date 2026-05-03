#!/bin/bash
# bootstrap-oidc.sh
#
# One-shot helper to set up an Azure App Registration with a Federated
# Identity Credential trusting a Buildkite pipeline (or cluster / queue / org).
#
# Usage:
#   ./bootstrap-oidc.sh \
#       --app-name           buildkite-oidc-bicep \
#       --subscription-id    00000000-0000-0000-0000-000000000000 \
#       --subject            <pipeline-uuid-or-cluster-uuid> \
#       --subject-type       pipeline_id \
#       --role               Contributor \
#       --scope              /subscriptions/00000000-0000-0000-0000-000000000000
#
# Flags:
#   --app-name        Display name for the App Registration. Created if missing.
#   --subscription-id Subscription that the SP will be assigned a role in.
#   --subject         The UUID that will go in the Federated Credential
#                     "Subject identifier" field. Must match what the
#                     Buildkite OIDC token's `sub` claim resolves to.
#   --subject-type    pipeline_id | cluster_id | queue_id | organization_id
#                     (used only to label the Federated Credential)
#   --role            RBAC role to assign (default: Contributor).
#   --scope           Scope to assign the role at (default: subscription).
#   --audience        OIDC audience (default: api://AzureADTokenExchange).
#
# Requires: az CLI logged in as a user with permission to create App
# Registrations and assign RBAC at the chosen scope.

set -euo pipefail

APP_NAME=""
SUBSCRIPTION_ID=""
SUBJECT=""
SUBJECT_TYPE="pipeline_id"
ROLE="Contributor"
SCOPE=""
AUDIENCE="api://AzureADTokenExchange"
ISSUER="https://agent.buildkite.com"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-name)        APP_NAME="$2"; shift 2 ;;
    --subscription-id) SUBSCRIPTION_ID="$2"; shift 2 ;;
    --subject)         SUBJECT="$2"; shift 2 ;;
    --subject-type)    SUBJECT_TYPE="$2"; shift 2 ;;
    --role)            ROLE="$2"; shift 2 ;;
    --scope)           SCOPE="$2"; shift 2 ;;
    --audience)        AUDIENCE="$2"; shift 2 ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

: "${APP_NAME:?--app-name is required}"
: "${SUBSCRIPTION_ID:?--subscription-id is required}"
: "${SUBJECT:?--subject is required (pipeline/cluster/queue/org UUID)}"

if [ -z "${SCOPE}" ]; then
  SCOPE="/subscriptions/${SUBSCRIPTION_ID}"
fi

echo "==> Configuring Buildkite OIDC trust for Azure"
echo "    App Registration : ${APP_NAME}"
echo "    Subject          : ${SUBJECT} (${SUBJECT_TYPE})"
echo "    Audience         : ${AUDIENCE}"
echo "    Role             : ${ROLE}"
echo "    Scope            : ${SCOPE}"
echo

# --- 1. Create or reuse the App Registration ----------------------------
APP_ID=$(az ad app list --display-name "${APP_NAME}" --query "[0].appId" -o tsv 2>/dev/null || echo "")

if [ -z "${APP_ID}" ]; then
  echo "==> Creating App Registration"
  APP_ID=$(az ad app create --display-name "${APP_NAME}" --query appId -o tsv)
else
  echo "==> App Registration already exists: ${APP_ID}"
fi

# --- 2. Create or reuse the service principal ---------------------------
SP_OBJECT_ID=$(az ad sp show --id "${APP_ID}" --query id -o tsv 2>/dev/null || echo "")

if [ -z "${SP_OBJECT_ID}" ]; then
  echo "==> Creating service principal for App Registration"
  SP_OBJECT_ID=$(az ad sp create --id "${APP_ID}" --query id -o tsv)
else
  echo "==> Service principal already exists: ${SP_OBJECT_ID}"
fi

# --- 3. Add the Federated Identity Credential ---------------------------
FIC_NAME="buildkite-${SUBJECT_TYPE}-$(echo "${SUBJECT}" | cut -c1-8)"

EXISTING_FIC=$(az ad app federated-credential list --id "${APP_ID}" \
  --query "[?name=='${FIC_NAME}'].name" -o tsv)

if [ -z "${EXISTING_FIC}" ]; then
  echo "==> Adding Federated Identity Credential: ${FIC_NAME}"
  az ad app federated-credential create --id "${APP_ID}" --parameters - <<EOF
{
  "name": "${FIC_NAME}",
  "issuer": "${ISSUER}",
  "subject": "${SUBJECT}",
  "audiences": ["${AUDIENCE}"],
  "description": "Buildkite OIDC trust (subject claim: ${SUBJECT_TYPE})"
}
EOF
else
  echo "==> Federated Identity Credential already exists: ${FIC_NAME}"
fi

# --- 4. Assign RBAC -----------------------------------------------------
echo "==> Assigning role '${ROLE}' at scope ${SCOPE}"
az role assignment create \
  --assignee-object-id      "${SP_OBJECT_ID}" \
  --assignee-principal-type ServicePrincipal \
  --role                    "${ROLE}" \
  --scope                   "${SCOPE}" \
  --output none || echo "    (role assignment may already exist — continuing)"

# --- 5. Output the values needed by the pipeline ------------------------
TENANT_ID=$(az account show --query tenantId -o tsv)

cat <<EOF

✅ Setup complete.

Add the following to your pipeline YAML env block:

env:
  ARM_CLIENT_ID:       "${APP_ID}"
  ARM_TENANT_ID:       "${TENANT_ID}"
  ARM_SUBSCRIPTION_ID: "${SUBSCRIPTION_ID}"
EOF

if [ "${SUBJECT_TYPE}" != "pipeline_id" ]; then
  cat <<EOF
  BUILDKITE_OIDC_SUBJECT_CLAIM: "${SUBJECT_TYPE}"
EOF
fi
