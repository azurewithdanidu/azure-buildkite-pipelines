# Buildkite Azure CLI Pipeline

This pipeline demonstrates a simple Buildkite setup that installs Azure CLI and performs authentication.

## Pipeline Structure

- **Location**: `.buildkite/pipeline.yml`
- **Queue**: Uses the default queue
- **Purpose**: Install Azure CLI and authenticate with Azure

## Features

- Multi-OS support (Linux, macOS, Windows)
- Automatic Azure CLI installation
- Service Principal authentication support
- Environment variable configuration

## Prerequisites

### 1. Buildkite Setup

- A Buildkite account and organization
- At least one Buildkite agent running on the `default` queue
- Agent should have sudo/admin privileges for installing packages

### 2. Azure Authentication (Optional)

For `az login` to work, you need one of the following:

#### Option A: Buildkite Secrets (Recommended for CI/CD)

**The pipeline now uses Buildkite Secrets for secure credential management.**

1. Navigate to your pipeline in Buildkite
2. Go to **Pipeline Settings** → **Secrets**
3. Click **New Secret** and add each of the following:
   - Secret Name: `AZURE_CLIENT_ID`
   - Secret Name: `AZURE_CLIENT_SECRET`
   - Secret Name: `AZURE_TENANT_ID`

The pipeline retrieves secrets using `buildkite-agent secret get` at runtime.

**Create a service principal:**
```bash
az ad sp create-for-rbac --name "buildkite-agent" --role Contributor --scopes /subscriptions/{subscription-id}
```

Output (use these values in your secrets):
```json
{
  "appId": "your-client-id",        // → AZURE_CLIENT_ID
  "password": "your-client-secret",  // → AZURE_CLIENT_SECRET
  "tenant": "your-tenant-id"         // → AZURE_TENANT_ID
}
```

📚 [Buildkite Secrets Documentation](https://buildkite.com/docs/pipelines/security/secrets/buildkite-secrets)

#### Option B: Managed Identity

If running on Azure VMs, configure managed identity:
- No credentials needed
- Works automatically on Azure resources

#### Option C: Device Code Flow

For interactive testing:
```bash
az login --use-device-code
```

## Usage

### Using Buildkite UI

1. Go to your Buildkite dashboard
2. Create a new pipeline
3. Point it to this repository
4. The pipeline will automatically use `.buildkite/pipeline.yml`

### Using Pipeline Upload

Create a minimal pipeline in Buildkite UI:

```yaml
steps:
  - label: ":pipeline: Upload Pipeline"
    command: buildkite-agent pipeline upload
```

This will upload the full pipeline from `.buildkite/pipeline.yml`.

## Configuration

### Setting Environment Variables in Buildkite

1. **Pipeline Settings** → **Environment Variables**
2. Add your Azure credentials:
   - `AZURE_CLIENT_ID`
   - `AZURE_CLIENT_SECRET` (mark as secret)
   - `AZURE_TENANT_ID`

### Using Secrets Plugins

For better security, use a secrets management plugin:

```yaml
steps:
  - label: ":azure: Azure Login"
    plugins:
      - seek-oss/aws-sm#v2.3.2:
          env:
            AZURE_CLIENT_ID: /buildkite/azure/client-id
            AZURE_CLIENT_SECRET: /buildkite/azure/client-secret
            AZURE_TENANT_ID: /buildkite/azure/tenant-id
    command: |
      az login --service-principal \
        --username "$AZURE_CLIENT_ID" \
        --password "$AZURE_CLIENT_SECRET" \
        --tenant "$AZURE_TENANT_ID"
```

## Alternative Pipelines

### Windows PowerShell Version

See `.buildkite/pipeline-windows.yml` for a PowerShell-specific pipeline.

### Linux-Only Version

See `.buildkite/pipeline-linux.yml` for a Linux-specific pipeline.

## Example Workflows

### Deploy to Azure App Service

```yaml
steps:
  - label: ":azure: Install Azure CLI"
    command: |
      curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
    agents:
      queue: "default"

  - wait

  - label: ":azure: Login to Azure"
    command: |
      az login --service-principal \
        --username "$AZURE_CLIENT_ID" \
        --password "$AZURE_CLIENT_SECRET" \
        --tenant "$AZURE_TENANT_ID"
    env:
      AZURE_CLIENT_ID: "{{secret:azure-client-id}}"
      AZURE_CLIENT_SECRET: "{{secret:azure-client-secret}}"
      AZURE_TENANT_ID: "{{secret:azure-tenant-id}}"

  - wait

  - label: ":rocket: Deploy to App Service"
    command: |
      az webapp deployment source config-zip \
        --resource-group myResourceGroup \
        --name myAppName \
        --src ./app.zip
```

## Troubleshooting

### Azure CLI Not Found After Installation

Restart the agent or add the Azure CLI to PATH:

```bash
export PATH="$PATH:/opt/az/bin"
```

### Permission Denied

Ensure the agent has sudo/admin privileges:

```yaml
steps:
  - command: "sudo az --version"
```

### Authentication Failures

- Verify service principal credentials
- Check RBAC permissions in Azure
- Ensure tenant ID is correct

## Resources

- [Buildkite Documentation](https://buildkite.com/docs)
- [Azure CLI Documentation](https://docs.microsoft.com/cli/azure/)
- [Buildkite Plugins Directory](https://buildkite.com/plugins)

## License

MIT
