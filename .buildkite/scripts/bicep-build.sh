#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# bicep-build.sh
# Lints and compiles a Bicep template, then converts the parameter file.
# Outputs compiled files into ./deploy/ (uploaded as a Buildkite artifact).
#
# Configuration (env vars or Buildkite meta-data from block step):
#   BICEP_TEMPLATE_FILE_PATH   - required - path to the .bicep file
#   BICEP_PARAMETER_FILE_PATH  - optional - path to .bicepparam or .json file
# ---------------------------------------------------------------------------

BUILD_DIR="deploy"

# ---------------------------------------------------------------------------
# Read config: env var takes priority, then Buildkite meta-data, then fail.
# ---------------------------------------------------------------------------
BICEP_TEMPLATE_FILE_PATH="${BICEP_TEMPLATE_FILE_PATH:?BICEP_TEMPLATE_FILE_PATH env var is required}"

if [ -z "${BICEP_PARAMETER_FILE_PATH:-}" ]; then
  BICEP_PARAMETER_FILE_PATH="$(buildkite-agent meta-data get parameter_file_path 2>/dev/null || echo '')"
fi

echo "--- :information_source: Build configuration"
echo "  Template:       ${BICEP_TEMPLATE_FILE_PATH}"
echo "  Parameter file: ${BICEP_PARAMETER_FILE_PATH:-<none>}"
echo "  Output dir:     ${BUILD_DIR}/"

# ---------------------------------------------------------------------------
# Validate inputs
# ---------------------------------------------------------------------------
if [ ! -f "${BICEP_TEMPLATE_FILE_PATH}" ]; then
  echo "❌ Template file not found: ${BICEP_TEMPLATE_FILE_PATH}"
  exit 1
fi

mkdir -p "${BUILD_DIR}"

# ---------------------------------------------------------------------------
# Lint
# ---------------------------------------------------------------------------
echo "--- :mag: Linting Bicep template"
az bicep lint --file "${BICEP_TEMPLATE_FILE_PATH}"
echo "✅ Lint passed"

# ---------------------------------------------------------------------------
# Build template → JSON
# ---------------------------------------------------------------------------
echo "--- :hammer: Building Bicep template"
az bicep build --file "${BICEP_TEMPLATE_FILE_PATH}" --outdir "${BUILD_DIR}"

TEMPLATE_JSON="${BUILD_DIR}/$(basename "${BICEP_TEMPLATE_FILE_PATH%.bicep}").json"
if [ ! -f "${TEMPLATE_JSON}" ]; then
  echo "❌ Expected compiled template not found: ${TEMPLATE_JSON}"
  ls -la "${BUILD_DIR}/"
  exit 1
fi
echo "✅ Template compiled: ${TEMPLATE_JSON}"

# ---------------------------------------------------------------------------
# Build / copy parameter file
# ---------------------------------------------------------------------------
if [ -n "${BICEP_PARAMETER_FILE_PATH}" ]; then
  if [ ! -f "${BICEP_PARAMETER_FILE_PATH}" ]; then
    echo "❌ Parameter file not found: ${BICEP_PARAMETER_FILE_PATH}"
    exit 1
  fi

  echo "--- :page_facing_up: Processing parameter file: ${BICEP_PARAMETER_FILE_PATH}"

  if [[ "${BICEP_PARAMETER_FILE_PATH}" == *.bicepparam ]]; then
    PARAM_OUT="${BUILD_DIR}/$(basename "${BICEP_PARAMETER_FILE_PATH%.bicepparam}").parameters.json"
    az bicep build-params --file "${BICEP_PARAMETER_FILE_PATH}" --outfile "${PARAM_OUT}"
    echo "✅ Parameter file compiled: ${PARAM_OUT}"
  elif [[ "${BICEP_PARAMETER_FILE_PATH}" == *.json ]]; then
    cp "${BICEP_PARAMETER_FILE_PATH}" "${BUILD_DIR}/"
    echo "✅ Parameter file copied: $(basename "${BICEP_PARAMETER_FILE_PATH}")"
  else
    echo "⚠️  Unrecognised parameter file extension, skipping: ${BICEP_PARAMETER_FILE_PATH}"
  fi
else
  echo "ℹ️  No parameter file specified, skipping."
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "--- :white_check_mark: Build artifacts"
ls -la "${BUILD_DIR}/"
echo "✅ Bicep build complete"
