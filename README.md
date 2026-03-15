# Azure Buildkite Pipelines

Buildkite CI/CD pipeline examples and templates for Azure deployments and Azure CLI integration.

## 📁 Repository Structure

```
.
├── .buildkite/
│   ├── pipeline.yml          # Multi-OS pipeline with Azure CLI
│   ├── pipeline-windows.yml  # Windows-specific pipeline
│   └── pipeline-linux.yml    # Linux-specific pipeline
├── .github/
│   ├── agents/
│   │   └── build-kite-agent.agent.md  # Buildkite agent definition
│   └── instructions/
│       └── .buildkite.instructions.md  # Comprehensive Buildkite reference
├── PIPELINE-README.md        # Detailed pipeline usage guide
└── README.md                 # This file
```

## 🚀 Quick Start

### Option 1: Use the Multi-OS Pipeline (Recommended)

This pipeline works on Linux, macOS, and Windows:

```bash
buildkite-agent pipeline upload .buildkite/pipeline.yml
```

### Option 2: Use Platform-Specific Pipelines

**For Windows agents:**
```bash
buildkite-agent pipeline upload .buildkite/pipeline-windows.yml
```

**For Linux agents:**
```bash
buildkite-agent pipeline upload .buildkite/pipeline-linux.yml
```

## 🎯 What These Pipelines Do

All pipelines:
1. ✅ Install Azure CLI on the agent
2. ✅ Verify the installation
3. ✅ Authenticate with Azure using service principal (if credentials provided)
4. ✅ Use the default Buildkite queue

## 📚 Documentation

- **[PIPELINE-README.md](./PIPELINE-README.md)** - Comprehensive guide on using these pipelines
- **[.buildkite.instructions.md](./.github/instructions/.buildkite.instructions.md)** - Complete Buildkite reference guide
- **[.agent.md](./.agent.md)** - Buildkite agent configuration

## 🔑 Azure Authentication

To enable Azure login, configure these environment variables in your Buildkite pipeline settings:

```bash
AZURE_CLIENT_ID=<your-client-id>
AZURE_CLIENT_SECRET=<your-client-secret>
AZURE_TENANT_ID=<your-tenant-id>
```

**Create a service principal:**
```bash
az ad sp create-for-rbac --name "buildkite-agent" --role Contributor
```

## 🛠️ Features

- **Multi-OS Support**: Works on Linux, macOS, and Windows
- **Automatic Installation**: Azure CLI installed automatically
- **Secure Authentication**: Service principal support
- **Default Queue**: Uses standard Buildkite queue
- **GitHub Copilot Integration**: Custom agent and instructions for AI assistance

## 📖 Learn More

- [Buildkite Documentation](https://buildkite.com/docs/pipelines)
- [Azure CLI Documentation](https://docs.microsoft.com/cli/azure/)
- [Buildkite Plugins](https://buildkite.com/plugins)

## 🤝 Contributing

Contributions welcome! This repository demonstrates:
- Buildkite pipeline best practices
- Azure CLI integration patterns
- GitHub Copilot agent customization

## 📄 License

MIT