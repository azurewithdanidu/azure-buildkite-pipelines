#!/bin/bash
set -euo pipefail

echo "--- :bicep: Installing Bicep CLI"

if az bicep version >/dev/null 2>&1; then
  echo "✅ Bicep already installed: $(az bicep version)"
  exit 0
fi

az bicep install

echo "✅ Bicep installed successfully"
az bicep version
