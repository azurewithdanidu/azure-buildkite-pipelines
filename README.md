# Azure Buildkite Pipelines

Buildkite CI/CD pipeline templates for Azure — from simple Azure CLI authentication through to full Bicep template deployment. All logic lives in reusable bash scripts; the pipeline YAML stays clean and declarative.

The `sample/` folder contains the original GitHub Actions workflows these pipelines were converted from.

---

## Table of Contents

- [What is Buildkite](#what-is-buildkite)
- [Getting Started with Buildkite](#getting-started-with-buildkite)
- [Repository Structure](#repository-structure)
- [Authentication — Service Principal with Buildkite Secrets](#authentication--service-principal-with-buildkite-secrets)
- [A Note on OIDC](#a-note-on-oidc)
- [Pipeline 1 — Azure CLI Login](#pipeline-1--azure-cli-login)
- [Pipeline 2 — Bicep Template Deployment](#pipeline-2--bicep-template-deployment)
- [Design Principles](#design-principles)
- [Scripts Reference](#scripts-reference)
- [Learn More](#learn-more)

---

## What is Buildkite

Buildkite is a CI/CD platform that runs pipelines on your own infrastructure. Unlike fully hosted platforms, Buildkite splits responsibilities:

- **Buildkite SaaS** — orchestrates builds, stores pipeline definitions, shows build results in the web UI
- **Buildkite Agent** — a small process you run on your own machines (VMs, containers, laptops) that picks up and executes jobs

This means your code and credentials never leave your own environment, which is a key advantage for Azure deployments that need access to private networks or sensitive credentials.

### Free Plan and Limits

Buildkite offers a free tier suitable for getting started:

| Feature | Free Plan |
|---|---|
| Users | Up to 3 users |
| Pipelines | Unlimited |
| Builds | Unlimited |
| Agents | Unlimited (self-hosted) |
| Build history retention | 90 days |
| Secrets | Included |
| Clusters | 1 cluster |
| Support | Community forum |

The free plan does not include SSO, audit logs, or priority support. For teams larger than 3 or with enterprise compliance requirements, a paid plan is needed.

Free plan details: https://buildkite.com/pricing

---

## Getting Started with Buildkite

### 1. Create an account

Sign up at https://buildkite.com. The free plan requires no credit card.

### 2. Create a pipeline

In the Buildkite UI, create a new pipeline and point it at this repository. Set the pipeline steps source to "Read from repository" — Buildkite will look for `.buildkite/pipeline.yml` automatically.

### 3. Install the Buildkite Agent

The agent runs on your own machine and executes pipeline jobs. Install it on any Linux, macOS, or Windows machine that has network access to Azure.

**Linux (Debian/Ubuntu):**
```bash
echo "deb https://apt.buildkite.com/buildkite-agent stable main" \
  | sudo tee /etc/apt/sources.list.d/buildkite-agent.list
curl -fsSL https://keys.openpgp.org/vks/v1/by-fingerprint/32A37959C2FA5C3C99EFBC32A79206696452D198 \
  | sudo gpg --dearmor -o /etc/apt/keyrings/buildkite-agent-archive-keyring.gpg
sudo apt-get update && sudo apt-get install -y buildkite-agent
```

**macOS:**
```bash
brew install buildkite/buildkite/buildkite-agent
```

**Windows:**
Download the installer from https://buildkite.com/docs/agent/v3/windows

Minimum required agent version for Buildkite Secrets: **v3.27.0**

Check your version:
```bash
buildkite-agent --version
```

### 4. Configure the agent token

When you create a pipeline, Buildkite gives you an agent token. Set it in the agent config:

```bash
# /etc/buildkite-agent/buildkite-agent.cfg (Linux)
token="your-agent-token-here"
```

Then start the agent:
```bash
sudo systemctl enable buildkite-agent && sudo systemctl start buildkite-agent
```

The agent will appear as online in the Buildkite UI under Agents.

### 5. Trigger your first build

Push a commit or click "New Build" in the Buildkite UI. The agent will pick up the job and run the pipeline steps.

---

## Repository Structure

```
.
├── .buildkite/
│   ├── pipeline.yml                       # Pipeline 1: Azure CLI install + login
│   ├── pipeline-with-fallback.yml         # Pipeline 1 variant: env var fallback
│   ├── pipeline-bicep-landing-zone.yml    # Pipeline 2: Bicep lint, build, what-if, deploy
│   └── scripts/
│       ├── install-az.sh                  # Installs Azure CLI (shared, idempotent)
│       ├── az-login.sh                    # Authenticates via Buildkite Secrets
│       ├── az-login-with-fallback.sh      # Authenticates with env var fallback
│       ├── verify-access.sh               # Lists account and resource groups
│       ├── bicep-install.sh               # Installs Bicep CLI
│       ├── bicep-build.sh                 # Lints and compiles Bicep, outputs to deploy/
│       ├── bicep-whatif.sh                # What-if across all 4 deployment scopes
│       └── bicep-deploy.sh                # Deploy across all 4 deployment scopes
├── sample/
│   ├── landing-zone.yml                   # Original GitHub Actions workflow (reference)
│   ├── build-action.yml                   # Original GitHub Actions build action (reference)
│   └── deploy-action.yml                  # Original GitHub Actions deploy action (reference)
├── .github/
│   └── instructions/
│       └── .buildkite.instructions.md    # Buildkite reference used by GitHub Copilot
├── BICEP-PIPELINE-README.md              # Full documentation for Pipeline 2
└── README.md                             # This file
```

---

## Authentication — Service Principal with Buildkite Secrets

These pipelines authenticate to Azure using a **service principal** with a client secret. Credentials are stored in **Buildkite Secrets**, which are encrypted at rest and injected at runtime by the agent — they are never exposed in logs or pipeline YAML.

### Step 1 — Create a service principal in Azure

```bash
az ad sp create-for-rbac \
  --name "buildkite-agent" \
  --role Contributor \
  --scopes /subscriptions/{your-subscription-id}
```

The output will contain:
```json
{
  "appId":       "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "password":    "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "tenant":      "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

Use `appId` as `AZURE_CLIENT_ID`, `password` as `AZURE_CLIENT_SECRET`, and `tenant` as `AZURE_TENANT_ID`.

For Bicep deployments at subscription scope, the service principal also needs the `Owner` role (to assign roles during deployment) or at minimum `Contributor` plus `User Access Administrator`.

### Step 2 — Store credentials as Buildkite Secrets

1. In Buildkite, go to your pipeline
2. Click **Settings** then **Secrets**
3. Add each of the following as a secret:

| Secret name | Value |
|---|---|
| `AZURE_CLIENT_ID` | Service principal App ID (`appId`) |
| `AZURE_CLIENT_SECRET` | Service principal password (`password`) |
| `AZURE_TENANT_ID` | Azure AD tenant ID (`tenant`) |

Secrets are retrieved at runtime inside scripts using:

```bash
AZURE_CLIENT_ID=$(buildkite-agent secret get AZURE_CLIENT_ID)
```

The agent fetches the value from the Buildkite API over a local socket — the secret is never written to disk or printed to stdout by the agent.

Buildkite Secrets documentation: https://buildkite.com/docs/pipelines/security/secrets/buildkite-secrets

---

## A Note on OIDC

The original GitHub Actions workflows used **OpenID Connect (OIDC)** for passwordless authentication — no client secret is stored anywhere; Azure trusts GitHub's identity token directly.

Buildkite also supports OIDC. The agent can request a short-lived OIDC token from Buildkite, and Azure can be configured to trust it via a federated identity credential on the app registration.

**However, getting Buildkite OIDC to work with Azure requires several non-trivial steps:**

1. Creating an app registration in Azure with a federated identity credential pointing to Buildkite's OIDC issuer (`https://agent.buildkite.com`)
2. Configuring the correct subject claim, which must match the Buildkite organization slug, pipeline slug, and optionally the branch
3. Ensuring the agent version and cluster configuration support OIDC token generation
4. The federated credential subject format is not well-documented for Buildkite specifically

Due to these complexities, these pipelines use service principal + client secret stored in Buildkite Secrets instead. This is a well-understood, reliable approach and is secure when used with Buildkite Secrets (not hardcoded env vars).

If you want to attempt OIDC in the future, refer to:
- https://buildkite.com/docs/agent/v3/cli-oidc
- https://learn.microsoft.com/azure/active-directory/workload-identities/workload-identity-federation

---

## Pipeline 1 — Azure CLI Login

A simple foundation pipeline. Installs Azure CLI on the agent and authenticates with Azure using the service principal credentials stored in Buildkite Secrets.

### Flow

```
Step 1 — Install Azure CLI and Login
  install-az.sh         detects OS, installs Azure CLI, skips if already present
  az-login.sh           fetches secrets from Buildkite, runs az login --service-principal

Step 2 — Verify Azure Access
  install-az.sh         idempotent, safe to call in every step
  az-login.sh           re-authenticate (each step runs in a clean environment)
  verify-access.sh      az account show, az group list, creates a build annotation
```

Each step re-runs `install-az.sh` and `az-login.sh` because Buildkite steps run in completely isolated environments — nothing persists between them.

### Upload the pipeline

```bash
buildkite-agent pipeline upload .buildkite/pipeline.yml
```

### Variants

| Pipeline file | When to use |
|---|---|
| `pipeline.yml` | Buildkite Secrets are configured. Fails immediately if any secret is missing. |
| `pipeline-with-fallback.yml` | Testing without secrets, or migrating from environment variables. Falls back to env vars if secrets are unavailable. |

---

## Pipeline 2 — Bicep Template Deployment

A full CI/CD pipeline for deploying Azure Bicep templates. Converted from the GitHub Actions workflows in the `sample/` folder.

### Flow

```
Block step — Configure Deployment
  User selects: parameter file, target subscription, location
  Values are stored as Buildkite meta-data for later steps to read.

Step — Lint and Build
  az bicep lint          validates the template
  az bicep build         compiles .bicep to .json
  az bicep build-params  converts .bicepparam to .parameters.json
  Uploads deploy/ as a Buildkite artifact

Wait

Step — What-If Deploy
  Downloads deploy/ artifact
  az deployment <scope> what-if
  Shows what would change without making any changes

Wait

Block step — Approve Deployment (main branch only)
  Reviewer checks the what-if output and manually approves

Step — Deploy to Azure (main branch only)
  Downloads deploy/ artifact
  az deployment <scope> create
```

Supports all four Azure deployment scopes: `subscription`, `tenant`, `managementgroup`, `resourcegroup`.

### Upload the pipeline

```bash
buildkite-agent pipeline upload .buildkite/pipeline-bicep-landing-zone.yml
```

Before running, update the block step `options` in the pipeline file with your real subscription names and IDs.

Full documentation: [BICEP-PIPELINE-README.md](./BICEP-PIPELINE-README.md)

---

## Design Principles

**Scripts over inline YAML**

All logic lives in `.sh` files under `.buildkite/scripts/`. The pipeline YAML only defines the step order and calls scripts. This means:
- No `$$` escaping of bash variables inside YAML
- No heredocs or multi-line strings in YAML
- Every script can be tested locally with `bash .buildkite/scripts/script-name.sh`

**Each step is self-contained**

Buildkite steps run in completely fresh environments. Nothing installed or set in one step is available in the next. The `install-az.sh` and `az-login.sh` scripts are designed to be called at the top of every step that needs Azure. They complete quickly if the tool is already installed or the account is already authenticated in that session.

**Reusable scripts**

The `bicep-*.sh` scripts are driven entirely by environment variables. To deploy a different Bicep template, create a new pipeline YAML file and set `BICEP_TEMPLATE_FILE_PATH` and related env vars — no changes to the scripts are needed.

---

## Scripts Reference

| Script | Used by | Description |
|---|---|---|
| `install-az.sh` | All pipelines | Detects OS (Debian/Ubuntu, RHEL/CentOS, macOS) and installs Azure CLI. Skips if already present. |
| `az-login.sh` | Pipeline 1 and 2 | Fetches `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID` from Buildkite Secrets and runs `az login --service-principal`. |
| `az-login-with-fallback.sh` | Fallback pipeline | Same as `az-login.sh` but falls back to environment variables if Buildkite Secrets are unavailable. |
| `verify-access.sh` | Pipeline 1 | Runs `az account show` and `az group list`, creates a Buildkite build annotation. |
| `bicep-install.sh` | Pipeline 2 | Runs `az bicep install`. Skips if already present. |
| `bicep-build.sh` | Pipeline 2 | Lints the template, compiles `.bicep` to `.json`, converts `.bicepparam` to `.parameters.json`. Outputs to `deploy/`. |
| `bicep-whatif.sh` | Pipeline 2 | Runs `az deployment what-if` for any of the four Azure deployment scopes. |
| `bicep-deploy.sh` | Pipeline 2 | Runs `az deployment create` for any of the four Azure deployment scopes. |

---

## Learn More

- [BICEP-PIPELINE-README.md](./BICEP-PIPELINE-README.md) — full documentation for the Bicep pipeline
- [Buildkite Getting Started](https://buildkite.com/docs/pipelines/getting-started)
- [Buildkite Agent Installation](https://buildkite.com/docs/agent/v3/installation)
- [Buildkite Secrets](https://buildkite.com/docs/pipelines/security/secrets/buildkite-secrets)
- [Buildkite Block Steps](https://buildkite.com/docs/pipelines/block-step)
- [Buildkite Pricing](https://buildkite.com/pricing)
- [Azure CLI Documentation](https://learn.microsoft.com/cli/azure/)
- [Azure Bicep Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)

---

## License

MIT


## 📁 Repository Structure

```
.
├── .buildkite/
│   ├── pipeline.yml                       # Simple: Azure CLI install + login
│   ├── pipeline-with-fallback.yml         # Simple: login with env var fallback
│   ├── pipeline-bicep-landing-zone.yml    # Complex: Bicep lint → build → what-if → deploy
│   └── scripts/
│       ├── install-az.sh                  # Installs Azure CLI (shared, idempotent)
│       ├── az-login.sh                    # Authenticates via Buildkite Secrets
│       ├── az-login-with-fallback.sh      # Authenticates with env var fallback
│       ├── verify-access.sh               # Lists account + resource groups
│       ├── bicep-install.sh               # Installs Bicep CLI
│       ├── bicep-build.sh                 # Lints + compiles Bicep → deploy/
│       ├── bicep-whatif.sh                # What-if across all 4 deployment scopes
│       └── bicep-deploy.sh                # Deploy across all 4 deployment scopes
├── sample/
│   ├── landing-zone.yml                   # Original GitHub Actions workflow
│   ├── build-action.yml                   # Original GitHub Actions build action
│   └── deploy-action.yml                  # Original GitHub Actions deploy action
├── .github/
│   ├── agents/
│   │   └── build-kite-agent.agent.md     # GitHub Copilot agent definition
│   └── instructions/
│       └── .buildkite.instructions.md    # Comprehensive Buildkite reference
├── BICEP-PIPELINE-README.md              # Full guide for the Bicep pipeline
└── README.md                             # This file
```

---

## Pipeline 1 — Simple Azure CLI Login

> **Start here.** Installs Azure CLI and authenticates with a service principal. A foundation you can build on.

### What it does

```
Step 1: Install Azure CLI & Login
  → install-az.sh       # detects OS, installs az, skips if already present
  → az-login.sh         # fetches secrets from Buildkite + runs az login

Step 2: Verify Azure Access
  → install-az.sh       # idempotent — safe to call in every step
  → az-login.sh         # re-authenticate (each step is a clean environment)
  → verify-access.sh    # az account show + group list + annotation
```

### Setup

**1. Create a service principal:**
```bash
az ad sp create-for-rbac --name "buildkite-agent" \
  --role Contributor \
  --scopes /subscriptions/{subscription-id}
```

**2. Add credentials as Buildkite Secrets** (Pipeline Settings → Secrets):

| Secret | Description |
|---|---|
| `AZURE_CLIENT_ID` | Service principal App ID |
| `AZURE_CLIENT_SECRET` | Service principal password |
| `AZURE_TENANT_ID` | Azure AD tenant ID |

> Requires Buildkite agent **v3.27.0+**.

**3. Upload the pipeline:**
```bash
buildkite-agent pipeline upload .buildkite/pipeline.yml
```

### Variants

| Pipeline | Use when |
|---|---|
| `pipeline.yml` | Secrets are configured — fails fast if missing |
| `pipeline-with-fallback.yml` | Migrating from env vars, or testing without secrets |

---

## Pipeline 2 — Bicep Template Deployment

> **Full CI/CD for Azure Bicep.** Converts the GitHub Actions landing-zone workflow into a Buildkite pipeline with lint, build, what-if validation, manual approval gate, and deployment.

### What it does

```
[block] Configure Deployment    ← user picks parameter file, subscription, location
[step]  Lint & Build            ← az bicep lint → build → build-params → upload artifact
        ↓ wait
[step]  What-If Deploy          ← download artifact → az deployment what-if
        ↓ wait
[block] Approve Deployment      ← manual gate (main branch only)
[step]  Deploy to Azure         ← download artifact → az deployment create
```

Supports all four Azure deployment scopes: `subscription`, `tenant`, `managementgroup`, `resourcegroup`.

### Quick start

**1.** Follow the same service principal + Buildkite Secrets setup as Pipeline 1 above.

**2.** Update `pipeline-bicep-landing-zone.yml` — set your real subscription names/IDs in the block step `options`, and set `BICEP_TEMPLATE_FILE_PATH` in `env` to match your repo.

**3.** Upload:
```bash
buildkite-agent pipeline upload .buildkite/pipeline-bicep-landing-zone.yml
```

📖 **Full documentation:** [BICEP-PIPELINE-README.md](./BICEP-PIPELINE-README.md)

---

## 🔑 Key Design Principles

**Scripts over inline YAML**
All logic lives in `.sh` files under `.buildkite/scripts/`. The pipeline YAML only orchestrates — no bash escaping, no heredocs. Every script can be run locally for testing.

**Clean environment awareness**
Each Buildkite step runs in a fresh shell. `install-az.sh` and `az-login.sh` are designed to be called at the top of every step that needs Azure — they're fast and idempotent.

**Reusable across pipelines**
The `bicep-*.sh` scripts are driven entirely by env vars. To deploy a different Bicep template, create a new pipeline YAML and point `BICEP_TEMPLATE_FILE_PATH` at it — no script changes needed.

---

## 📜 Scripts Reference

| Script | Used by | Description |
|---|---|---|
| `install-az.sh` | All pipelines | Installs Azure CLI. Detects Debian/Ubuntu, RHEL/CentOS, macOS. |
| `az-login.sh` | All pipelines | Reads secrets from Buildkite and runs `az login --service-principal`. |
| `az-login-with-fallback.sh` | Fallback pipeline | Same as above but falls back to env vars. |
| `verify-access.sh` | Simple pipeline | Lists account and resource groups, creates annotation. |
| `bicep-install.sh` | Bicep pipeline | Runs `az bicep install`. Skips if already present. |
| `bicep-build.sh` | Bicep pipeline | Lints, compiles template, converts `.bicepparam` → `.parameters.json`. |
| `bicep-whatif.sh` | Bicep pipeline | `az deployment <scope> what-if` for all 4 scopes. |
| `bicep-deploy.sh` | Bicep pipeline | `az deployment <scope> create` for all 4 scopes. |

---

## 📖 Learn More

- [BICEP-PIPELINE-README.md](./BICEP-PIPELINE-README.md) — full Bicep pipeline guide
- [Buildkite Secrets](https://buildkite.com/docs/pipelines/security/secrets/buildkite-secrets)
- [Buildkite Pipeline Docs](https://buildkite.com/docs/pipelines)
- [Azure CLI Docs](https://learn.microsoft.com/cli/azure/)
- [Bicep Docs](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)

## 📄 License

MIT