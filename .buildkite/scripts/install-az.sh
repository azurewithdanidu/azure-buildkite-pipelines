#!/bin/bash
set -euo pipefail

echo "--- :package: Installing Azure CLI"

# If already installed, skip
if command -v az >/dev/null 2>&1; then
  echo "✅ Azure CLI already installed: $(az --version | head -1)"
  exit 0
fi

echo "Azure CLI not found, installing..."

if [ -x "$(command -v apt-get)" ]; then
  echo "Detected Debian/Ubuntu"
  sudo apt-get update -y
  sudo apt-get install -y ca-certificates curl apt-transport-https lsb-release gnupg
  curl -sL https://packages.microsoft.com/keys/microsoft.asc \
    | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/microsoft.gpg
  AZ_DIST=$(lsb_release -cs)
  echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ ${AZ_DIST} main" \
    | sudo tee /etc/apt/sources.list.d/azure-cli.list
  sudo apt-get update -y
  sudo apt-get install -y azure-cli

elif [ -x "$(command -v yum)" ]; then
  echo "Detected RHEL/CentOS"
  sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
  sudo sh -c 'echo -e "[azure-cli]\nname=Azure CLI\nbaseurl=https://packages.microsoft.com/yumrepos/azure-cli\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" \
    > /etc/yum.repos.d/azure-cli.repo'
  sudo yum install -y azure-cli

elif [ -x "$(command -v brew)" ]; then
  echo "Detected macOS"
  brew update && brew install azure-cli

else
  echo "❌ Unsupported OS - cannot install Azure CLI automatically"
  exit 1
fi

# Refresh shell command cache
hash -r 2>/dev/null || true

if ! command -v az >/dev/null 2>&1; then
  echo "❌ Azure CLI installation failed - az not found in PATH"
  echo "Current PATH: ${PATH}"
  echo "Searching for az binary:"
  find /usr /opt -name az -type f 2>/dev/null || true
  exit 1
fi

echo "✅ Azure CLI installed successfully"
az version
