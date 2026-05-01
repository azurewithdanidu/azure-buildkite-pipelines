# Bicep Deployment Pipeline

Buildkite pipeline for linting, building, what-if validating, and deploying Azure Bicep templates. Supports all four Azure deployment scopes: **subscription**, **tenant**, **management group**, and **resource group**.

## Pipeline Overview

```
[block] Configure Deployment
    User selects: parameter file, target subscription, location
           ↓
[step] Lint & Build
    az bicep lint → az bicep build → az bicep build-params
    Uploads compiled files as a Buildkite artifact (deploy/)
           ↓  wait
[step] What-If Deploy
    Downloads artifact → az deployment <scope> what-if
           ↓  wait
[block] Approve Deployment        ← manual gate (main branch only)
           ↓
[step] Deploy to Azure
    Downloads artifact → az deployment <scope> create
```

## Files

```
.buildkite/
  pipeline-bicep-landing-zone.yml     ← pipeline definition
  scripts/
    install-az.sh                     ← installs Azure CLI (shared)
    az-login.sh                       ← authenticates with Azure (shared)
    bicep-install.sh                  ← installs Bicep CLI via az bicep install
    bicep-build.sh                    ← lint + build template + convert params
    bicep-whatif.sh                   ← what-if across all 4 deployment scopes
    bicep-deploy.sh                   ← deploy across all 4 deployment scopes
```

## Prerequisites

### 1. Azure credentials as Buildkite Secrets

Go to **Pipeline Settings → Secrets** and add:

| Secret name | Description |
|---|---|
| `AZURE_CLIENT_ID` | Service principal App ID |
| `AZURE_CLIENT_SECRET` | Service principal password |
| `AZURE_TENANT_ID` | Azure Active Directory tenant ID |

Create a service principal:
```bash
az ad sp create-for-rbac \
  --name "buildkite-bicep-agent" \
  --role Contributor \
  --scopes /subscriptions/{subscription-id}
```

For subscription-scope Bicep deployments that assign roles (e.g. landing zone patterns), the service principal also needs the `Owner` role, or `Contributor` plus `User Access Administrator`.

> Buildkite Secrets require agent **v3.27.0 or higher**.

For full authentication setup and OIDC considerations, see the [Authentication section in README.md](./README.md#authentication--service-principal-with-buildkite-secrets).

### 2. Agent requirements

The pipeline uses **Linux bash** scripts. Your Buildkite agent must have:
- `curl` and `sudo` access
- `apt-get` (Debian/Ubuntu), `yum` (RHEL/CentOS), or `brew` (macOS)

Azure CLI and Bicep CLI are installed automatically by the scripts if not already present.

## Pipeline Configuration

### Pipeline-level env vars

Set these at the top of `pipeline-bicep-landing-zone.yml` or in Buildkite Pipeline Settings → Environment Variables:

| Variable | Required | Default | Description |
|---|---|---|---|
| `BICEP_TEMPLATE_FILE_PATH` | Yes | `bicep/patterns/landing-zone/landing-zone.bicep` | Path to the `.bicep` template |
| `BICEP_DEPLOYMENT_NAME` | Yes | `deploy_landing_zone` | Name of the ARM deployment |
| `AZURE_DEPLOYMENT_TYPE` | Yes | `subscription` | Scope: `subscription` \| `tenant` \| `managementgroup` \| `resourcegroup` |
| `AZURE_MANAGEMENT_GROUP_ID` | Conditional | — | Required when `AZURE_DEPLOYMENT_TYPE=managementgroup` |
| `AZURE_RESOURCE_GROUP_NAME` | Conditional | — | Required when `AZURE_DEPLOYMENT_TYPE=resourcegroup` |

### Block step (runtime inputs)

When the pipeline runs, the first block step prompts for:

| Field | Description |
|---|---|
| **Parameter File** | Which `.bicepparam` file to use |
| **Target Subscription** | Azure subscription ID to deploy into |
| **Location** | Azure region for the deployment |

Update the `options` in the block step to match your subscriptions and parameter files.

## Deployment Scopes

### Subscription scope (default)
```yaml
env:
  AZURE_DEPLOYMENT_TYPE: "subscription"
```
Requires `AZURE_SUBSCRIPTION_ID` (collected from block step).

### Tenant scope
```yaml
env:
  AZURE_DEPLOYMENT_TYPE: "tenant"
```
Requires appropriate tenant-level RBAC on the service principal.

### Management Group scope
```yaml
env:
  AZURE_DEPLOYMENT_TYPE: "managementgroup"
  AZURE_MANAGEMENT_GROUP_ID: "your-mg-id"
```

### Resource Group scope
```yaml
env:
  AZURE_DEPLOYMENT_TYPE: "resourcegroup"
  AZURE_RESOURCE_GROUP_NAME: "your-rg-name"
```
Requires `AZURE_SUBSCRIPTION_ID` (collected from block step).

## Expected Repo Structure

The pipeline assumes your Bicep files live in your target repository like this (paths are configurable):

```
bicep/
  patterns/
    landing-zone/
      landing-zone.bicep
      landing-zone.workload1.bicepparam
      landing-zone.workload2.bicepparam
      landing-zone.workload3.bicepparam
      landing-zone.workload4.bicepparam
```

## Running the Pipeline

### Upload the pipeline:
```bash
buildkite-agent pipeline upload .buildkite/pipeline-bicep-landing-zone.yml
```

### Or trigger via Buildkite UI:
1. Go to your pipeline in Buildkite
2. Click **New Build**
3. The first step will prompt you for deployment parameters

## Scripts Reference

All scripts can be tested locally (requires Azure CLI + Buildkite agent installed):

### `bicep-install.sh`
Installs the Bicep CLI extension via `az bicep install`. Skips if already installed.

```bash
bash .buildkite/scripts/bicep-install.sh
```

### `bicep-build.sh`
Lints and compiles the Bicep template. Converts `.bicepparam` → `.parameters.json`. Outputs to `deploy/`.

```bash
BICEP_TEMPLATE_FILE_PATH="bicep/patterns/landing-zone/landing-zone.bicep" \
BICEP_PARAMETER_FILE_PATH="bicep/patterns/landing-zone/landing-zone.workload1.bicepparam" \
bash .buildkite/scripts/bicep-build.sh
```

### `bicep-whatif.sh`
Runs `az deployment what-if` using the compiled artifact in `deploy/`.

```bash
AZURE_DEPLOYMENT_TYPE="subscription" \
BICEP_DEPLOYMENT_NAME="deploy_landing_zone" \
BICEP_TEMPLATE_FILE_PATH="bicep/patterns/landing-zone/landing-zone.bicep" \
AZURE_LOCATION="australiaeast" \
AZURE_SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000" \
bash .buildkite/scripts/bicep-whatif.sh
```

### `bicep-deploy.sh`
Runs `az deployment create` using the compiled artifact in `deploy/`. Same env vars as above.

```bash
AZURE_DEPLOYMENT_TYPE="subscription" \
BICEP_DEPLOYMENT_NAME="deploy_landing_zone" \
BICEP_TEMPLATE_FILE_PATH="bicep/patterns/landing-zone/landing-zone.bicep" \
AZURE_LOCATION="australiaeast" \
AZURE_SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000" \
bash .buildkite/scripts/bicep-deploy.sh
```

## Customising for Other Bicep Templates

To reuse these scripts for a different Bicep template, create a new pipeline file (e.g. `pipeline-bicep-my-template.yml`) and update the `env` block:

```yaml
env:
  BICEP_TEMPLATE_FILE_PATH: "bicep/modules/my-template/my-template.bicep"
  BICEP_DEPLOYMENT_NAME: "deploy_my_template"
  AZURE_DEPLOYMENT_TYPE: "resourcegroup"
  AZURE_RESOURCE_GROUP_NAME: "my-resource-group"
```

The scripts (`bicep-build.sh`, `bicep-whatif.sh`, `bicep-deploy.sh`) are reusable with no changes.

## Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| `az: command not found` | Azure CLI not installed | `install-az.sh` handles this; check agent OS compatibility |
| `Bicep CLI not found` | Bicep not installed | `bicep-install.sh` runs `az bicep install`; ensure az is auth'd first |
| `No artifacts found` / `Compiled template not found` | Build artifact not downloaded or wrong glob pattern | Use `buildkite-agent artifact download 'deploy/**' .` (not `deploy/**/*`) in whatif and deploy steps |
| `AZURE_SUBSCRIPTION_ID is required` | Block step value not set | Check the block step field key is exactly `subscription_id` |
| Block step not appearing | Pipeline not on `main` | Block steps appear for all branches; the deploy step is `main`-only |

## References

- [Buildkite Block Steps](https://buildkite.com/docs/pipelines/block-step)
- [Buildkite Artifacts](https://buildkite.com/docs/pipelines/artifacts)
- [Buildkite Secrets](https://buildkite.com/docs/pipelines/security/secrets/buildkite-secrets)
- [az bicep build](https://learn.microsoft.com/cli/azure/bicep#az-bicep-build)
- [az deployment sub create](https://learn.microsoft.com/cli/azure/deployment/sub#az-deployment-sub-create)
