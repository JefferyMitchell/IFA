#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# citrix/01-upload-citrix-assets.sh
# Uploads the Citrix VDA installer and Citrix Optimizer to the factory
# storage account before the image build runs.
#
# Before running this script you must download both files from Citrix:
#
#   VDA Installer:
#     https://www.citrix.com/downloads/citrix-virtual-apps-and-desktops/
#     → Citrix Virtual Delivery Agent (Server OS) → VDAServerSetup_XXXX.exe
#     Rename to: VDAServerSetup.exe
#
#   Citrix Optimizer:
#     https://support.citrix.com/article/CTX224676
#     Rename to: CitrixOptimizer.zip
#
# Upload both files to ~/clouddrive/citrix-assets/ in Cloud Shell, then run
# this script.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

RESOURCE_GROUP="rg-imagebuilder"
ASSETS_DIR="${HOME}/clouddrive/citrix-assets"

# ── Detect subscription ───────────────────────────────────────────────────────
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo "Active subscription: $SUBSCRIPTION_ID"

# ── Retrieve storage account name from infrastructure deployment ──────────────
echo "Retrieving storage account name from deployment..."
STORAGE_ACCOUNT_NAME=$(az deployment group show \
  --resource-group "$RESOURCE_GROUP" \
  --name "deploy-image-factory-infra" \
  --query "properties.outputs.storageAccountName.value" -o tsv)

echo "  Storage account : $STORAGE_ACCOUNT_NAME"
echo ""

# ── Verify assets are present ─────────────────────────────────────────────────
echo "Checking for Citrix assets in: $ASSETS_DIR"

if [[ ! -f "$ASSETS_DIR/VDAServerSetup.exe" ]]; then
  echo ""
  echo "ERROR: VDAServerSetup.exe not found in $ASSETS_DIR"
  echo ""
  echo "Download the Citrix VDA Server installer from:"
  echo "  https://www.citrix.com/downloads/citrix-virtual-apps-and-desktops/"
  echo "  → Citrix Virtual Delivery Agent (Server OS)"
  echo ""
  echo "Rename the file to VDAServerSetup.exe and place it in ~/clouddrive/citrix-assets/"
  exit 1
fi

if [[ ! -f "$ASSETS_DIR/CitrixOptimizer.zip" ]]; then
  echo ""
  echo "ERROR: CitrixOptimizer.zip not found in $ASSETS_DIR"
  echo ""
  echo "Download Citrix Optimizer from:"
  echo "  https://support.citrix.com/article/CTX224676"
  echo ""
  echo "Rename the file to CitrixOptimizer.zip and place it in ~/clouddrive/citrix-assets/"
  exit 1
fi

echo "  Found: VDAServerSetup.exe ($(du -h "$ASSETS_DIR/VDAServerSetup.exe" | cut -f1))"
echo "  Found: CitrixOptimizer.zip ($(du -h "$ASSETS_DIR/CitrixOptimizer.zip" | cut -f1))"
echo ""

# ── Upload to storage account ─────────────────────────────────────────────────
echo "Uploading Citrix assets to storage account..."
az storage blob upload-batch \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --destination "scripts" \
  --source "$ASSETS_DIR" \
  --pattern "VDAServerSetup.exe" \
  --auth-mode login \
  --overwrite true \
  --output table

az storage blob upload-batch \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --destination "scripts" \
  --source "$ASSETS_DIR" \
  --pattern "CitrixOptimizer.zip" \
  --auth-mode login \
  --overwrite true \
  --output table

echo ""
echo "Verifying uploaded blobs:"
az storage blob list \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --container-name "scripts" \
  --auth-mode login \
  --query "[?contains(name, 'VDA') || contains(name, 'Citrix')].{Name:name, Size:properties.contentLength, Modified:properties.lastModified}" \
  --output table

echo ""
echo "Citrix assets uploaded. Proceed to 02-deploy-citrix-template.sh"
