# Azure Buildkite Pipelines

Buildkite CI/CD pipeline templates for Azure — from simple Azure CLI authentication through to full Bicep template deployment. All logic lives in reusable bash scripts; the pipeline YAML stays clean and declarative.

---

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