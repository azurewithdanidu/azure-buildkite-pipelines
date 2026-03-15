# Azure Buildkite Pipelines

Buildkite CI/CD pipeline templates for Azure CLI installation and authentication using service principals and Buildkite Secrets.

## 📁 Repository Structure

```
.
├── .buildkite/
│   ├── pipeline.yml                      # Main pipeline (Buildkite Secrets)
│   ├── pipeline-with-fallback.yml        # Pipeline with env var fallback
│   └── scripts/
│       ├── install-az.sh                 # Installs Azure CLI (idempotent)
│       ├── az-login.sh                   # Login via Buildkite Secrets
│       ├── az-login-with-fallback.sh     # Login with env var fallback
│       └── verify-access.sh              # Verifies Azure subscription access
├── .github/
│   ├── agents/
│   │   └── build-kite-agent.agent.md    # GitHub Copilot agent definition
│   └── instructions/
│       └── .buildkite.instructions.md   # Comprehensive Buildkite reference
└── README.md
```

## 🚀 Quick Start

### 1. Configure Azure credentials as Buildkite Secrets

Go to **Pipeline Settings → Secrets** and add:

| Secret name | Description |
|---|---|
| `AZURE_CLIENT_ID` | Service principal App ID |
| `AZURE_CLIENT_SECRET` | Service principal password |
| `AZURE_TENANT_ID` | Azure Active Directory tenant ID |

> **Note:** Buildkite Secrets require agent **v3.27.0 or higher**.

**Create a service principal:**
```bash
az ad sp create-for-rbac --name "buildkite-agent" \
  --role Contributor \
  --scopes /subscriptions/{subscription-id}
```

### 2. Upload the pipeline

```bash
buildkite-agent pipeline upload .buildkite/pipeline.yml
```

Or use the fallback pipeline (supports env vars if secrets aren't configured yet):

```bash
buildkite-agent pipeline upload .buildkite/pipeline-with-fallback.yml
```

## 🎯 How It Works

Each pipeline step calls reusable shell scripts — no logic lives in the YAML:

```
Step: Install Azure CLI & Login
  → bash .buildkite/scripts/install-az.sh       # installs az (skips if already present)
  → bash .buildkite/scripts/az-login.sh         # fetches secrets + az login

Step: Verify Azure Access
  → bash .buildkite/scripts/install-az.sh       # idempotent - safe to call again
  → bash .buildkite/scripts/az-login.sh         # re-authenticate (clean environment)
  → bash .buildkite/scripts/verify-access.sh    # az account show + group list
```

> Each Buildkite step runs in a **completely clean environment** — the scripts handle install and login in every step that needs them.

## 📜 Scripts Reference

| Script | Purpose |
|---|---|
| `install-az.sh` | Detects OS (Debian/Ubuntu/RHEL/macOS) and installs Azure CLI. Skips if already installed. |
| `az-login.sh` | Reads `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID` from Buildkite Secrets and runs `az login`. |
| `az-login-with-fallback.sh` | Same as above but falls back to environment variables if secrets are unavailable. |
| `verify-access.sh` | Lists the current account and resource groups, and creates a Buildkite annotation. |

Scripts can be tested locally:
```bash
bash .buildkite/scripts/install-az.sh
```

## 🔑 Pipeline Variants

### `pipeline.yml` — Production (Buildkite Secrets only)

Uses `buildkite-agent secret get` exclusively. Fails fast if secrets are not configured.

### `pipeline-with-fallback.yml` — Development / Migration

Tries Buildkite Secrets first, falls back to environment variables. Useful when migrating from env vars to secrets.

## 🛠️ Features

- **Script-based**: All logic in `.sh` files — no YAML escaping, testable locally
- **Idempotent install**: `install-az.sh` skips if Azure CLI is already present
- **OS detection**: Supports Debian/Ubuntu (apt), RHEL/CentOS (yum), and macOS (brew)
- **Secure by default**: Credentials fetched from Buildkite Secrets at runtime
- **Buildkite annotations**: Rich build output with success/warning/error styles
- **GitHub Copilot integration**: Custom agent for Buildkite pipeline assistance

## 📖 Learn More

- [Buildkite Secrets Documentation](https://buildkite.com/docs/pipelines/security/secrets/buildkite-secrets)
- [Buildkite Pipeline Documentation](https://buildkite.com/docs/pipelines)
- [Azure CLI Documentation](https://learn.microsoft.com/cli/azure/)

## 📄 License

MIT