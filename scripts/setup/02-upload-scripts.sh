#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# 02-upload-scripts.sh
# Uploads the PowerShell customization scripts from scripts/customization/
# to the 'scripts' container in the storage account. AIB pulls these during
# the build using the managed identity (no SAS token required).
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-imagebuilder}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts/customization"

# ── Detect subscription ───────────────────────────────────────────────────────
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo "Active subscription: $SUBSCRIPTION_ID"

# ── Retrieve storage account name from deployment output ──────────────────────
echo "Retrieving storage account name from deployment..."
STORAGE_ACCOUNT_NAME=$(az deployment group show \
  --resource-group "$RESOURCE_GROUP" \
  --name "deploy-image-factory-infra" \
  --query "properties.outputs.storageAccountName.value" -o tsv)

echo "  Storage account : $STORAGE_ACCOUNT_NAME"
echo ""

# ── Upload scripts ────────────────────────────────────────────────────────────
echo "Uploading customization scripts..."
az storage blob upload-batch \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --destination "scripts" \
  --source "$SCRIPTS_DIR" \
  --pattern "*.ps1" \
  --auth-mode login \
  --overwrite true \
  --output table

echo ""
echo "Verifying uploaded blobs:"
az storage blob list \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --container-name "scripts" \
  --auth-mode login \
  --query "[].{Name:name, Size:properties.contentLength, Modified:properties.lastModified}" \
  --output table

echo ""
echo "Scripts uploaded. Proceed to 03-deploy-template.sh"
