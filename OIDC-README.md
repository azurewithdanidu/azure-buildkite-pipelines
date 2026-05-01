# Buildkite ↔ Azure OIDC Setup

This guide explains how to authenticate the Buildkite agent to Azure using
**OpenID Connect (OIDC)** / **Workload Identity Federation** — no client
secret is stored in Buildkite Secrets, environment variables, or anywhere
else.

If you're new to this repo, start with [PIPELINE-README.md](PIPELINE-README.md)
and [BICEP-PIPELINE-README.md](BICEP-PIPELINE-README.md) first. This document
is the OIDC variant of those.

---

## Files added for OIDC

| File | Purpose |
|---|---|
| `.buildkite/scripts/az-login-oidc.sh` | Drop-in replacement for `az-login.sh`. Requests an OIDC token from the Buildkite agent and exchanges it for an Azure access token. |
| `.buildkite/scripts/bootstrap-oidc.sh` | One-shot helper that creates the Azure App Registration, Federated Identity Credential, and RBAC role assignment. |
| `.buildkite/pipeline-oidc.yml` | OIDC variant of `pipeline.yml` (CLI install + login + verify). |
| `.buildkite/pipeline-bicep-landing-zone-oidc.yml` | OIDC variant of `pipeline-bicep-landing-zone.yml`. |

The existing Bicep scripts (`bicep-build.sh`, `bicep-whatif.sh`,
`bicep-deploy.sh`) work unchanged — `az-login-oidc.sh` exports both `ARM_*`
and `AZURE_*` env vars so downstream scripts behave identically.

---

## Requirements

- Buildkite agent **v3.106.0** or later
  (verify with `buildkite-agent --version`)
- Permission to create App Registrations and Federated Identity Credentials
  in your Microsoft Entra tenant
- Permission to assign RBAC roles at the scope you want the pipeline to
  deploy into
- Azure CLI installed locally (for the bootstrap script)

---

## Choose your trust scope

Buildkite supports four "subject claim" options for OIDC tokens. Pick the
one that matches your blast-radius tolerance:

| Subject Claim | One Federated Credential covers... | When to use |
|---|---|---|
| `pipeline_id` *(default)* | A single Buildkite pipeline | Production deploys, tightly-scoped trust |
| `cluster_id` | All pipelines in a Buildkite cluster | Shared infra, fewer credentials to manage |
| `queue_id` | All pipelines using a specific agent queue | Queue-per-environment topologies |
| `organization_id` | Every pipeline in the org | Smallest setup, broadest trust — avoid if you accept PRs from forks |

To find the UUID for the scope you picked:

- **Pipeline UUID** → Pipeline Settings → General → "Pipeline ID"
- **Cluster UUID** → Cluster Settings
- **Queue UUID** → Cluster → Queues
- **Organization UUID** → Organization Settings

---

## Step-by-step setup

### 1. Bootstrap the Azure side

Easiest path is the helper script. Log in to Azure as a user with rights
to create App Registrations and assign RBAC, then run:

```bash
# Pipeline-scoped trust (default)
.buildkite/scripts/bootstrap-oidc.sh \
  --app-name        buildkite-oidc-bicep \
  --subscription-id 00000000-0000-0000-0000-000000000000 \
  --subject         <pipeline-uuid-from-buildkite> \
  --subject-type    pipeline_id \
  --role            Contributor

# Cluster-scoped trust
.buildkite/scripts/bootstrap-oidc.sh \
  --app-name        buildkite-oidc-cluster-prod \
  --subscription-id 00000000-0000-0000-0000-000000000000 \
  --subject         <cluster-uuid-from-buildkite> \
  --subject-type    cluster_id \
  --role            Contributor
```

The script outputs the `ARM_CLIENT_ID`, `ARM_TENANT_ID`, and
`ARM_SUBSCRIPTION_ID` values you need to paste into the pipeline YAML.

> For Bicep deployments at subscription scope that assign roles (e.g. landing
> zone patterns), use `--role Owner` instead of `Contributor`.

### 2. Configure the pipeline YAML

Open `.buildkite/pipeline-oidc.yml` (or `pipeline-bicep-landing-zone-oidc.yml`)
and replace the placeholders in the `env:` block with the values from step 1:

```yaml
env:
  ARM_CLIENT_ID:       "<application-client-id>"
  ARM_TENANT_ID:       "<entra-tenant-id>"
  ARM_SUBSCRIPTION_ID: "<subscription-id>"
  # BUILDKITE_OIDC_SUBJECT_CLAIM: "cluster_id"   # uncomment for non-default
```

These three values are **identifiers, not secrets** — they're safe to commit.

### 3. Point the Buildkite pipeline at the OIDC YAML

In the Buildkite UI:

1. Pipeline → **Settings** → **Steps**
2. Set the steps source to read from your repository
3. Set the path to `.buildkite/pipeline-oidc.yml` (or the Bicep variant)

Or upload it dynamically from a top-level `.buildkite/pipeline.yml`:

```yaml
steps:
  - command: "buildkite-agent pipeline upload .buildkite/pipeline-oidc.yml"
```

### 4. Trigger a build

That's it. No client secret to rotate, no Buildkite Secrets to manage.

---

## How `az-login-oidc.sh` works

```bash
# Inside each pipeline step:
BUILDKITE_OIDC_TOKEN=$(buildkite-agent oidc request-token \
  --audience "api://AzureADTokenExchange" \
  [--subject-claim cluster_id])

az login --service-principal \
  --username        "$ARM_CLIENT_ID" \
  --tenant          "$ARM_TENANT_ID" \
  --federated-token "$BUILDKITE_OIDC_TOKEN"
```

Each step calls this script independently — OIDC tokens are short-lived
(~5 minutes) and cannot be passed between steps. That's a Buildkite design
choice and a security feature.

---

## Switching trust scope without changing scripts

Set `BUILDKITE_OIDC_SUBJECT_CLAIM` in the pipeline `env:` block:

```yaml
env:
  BUILDKITE_OIDC_SUBJECT_CLAIM: "cluster_id"   # or queue_id, organization_id
```

The same `az-login-oidc.sh` works for all four scopes — just make sure the
matching Federated Identity Credential exists in Azure with the correct
Subject identifier.

---

## Sovereign clouds

Set `AZURE_OIDC_AUDIENCE` in the pipeline `env:`:

| Cloud | Audience |
|---|---|
| Azure Commercial *(default)* | `api://AzureADTokenExchange` |
| Azure US Government | `api://AzureADTokenExchangeUSGov` |
| Azure China (21Vianet) | `api://AzureADTokenExchangeChina` |

Don't change to a custom audience — Azure will reject the token.

---

## Monitoring

OIDC sign-ins appear in **Microsoft Entra admin center → Identity →
Monitoring & health → Sign-in logs → Service principal sign-ins**. Filter
by your App Registration name.

---

## Troubleshooting

| Error | Likely cause |
|---|---|
| `AADSTS70021: No matching federated identity record found` | The token's `sub` doesn't match the FIC's Subject identifier. Double-check the UUID. |
| `AADSTS700016: Application not found in the directory` | Wrong `ARM_CLIENT_ID`, or the App Reg is in a different tenant. |
| `AuthorizationFailed` | Authentication worked, but RBAC didn't. Add the right role at the right scope. |
| `Storage account key access is disabled` | Need **Storage Blob Data Contributor**, not just Contributor. |
| Token expired | A step is reusing a token from earlier. Each step must call `az-login-oidc.sh`. |

---

## Security notes

OIDC removes credential storage but does **not** remove the "untrusted code
in your pipeline" problem. If your pipeline accepts pull requests from
forks, anyone who can open a PR could potentially request an OIDC token.

To reduce that risk:

- Separate CI (tests) from CD (deploys). Only put OIDC on the deploy pipeline.
- Scope RBAC tightly — resource group, not subscription, when possible.
- Use Buildkite [pipeline-level permissions](https://buildkite.com/docs/pipelines/security/permissions) to control who can trigger deploy builds.
- For Entra ID P1/P2: apply [Conditional Access for workload identities](https://learn.microsoft.com/entra/identity/conditional-access/workload-identity).

---

## References

- [Buildkite — OIDC with Azure](https://buildkite.com/docs/pipelines/security/oidc/azure)
- [Buildkite — `buildkite-agent oidc` CLI](https://buildkite.com/docs/agent/v3/cli-oidc)
- [Buildkite — Custom subject claims](https://buildkite.com/docs/agent/v3/cli-oidc#custom-subject-claims)
- [Microsoft Learn — Workload identity federation](https://learn.microsoft.com/entra/workload-id/workload-identity-federation)
- Blog post: *Buildkite OIDC with Azure — Passwordless Pipelines, Pipeline vs Cluster Scoped Trust*
