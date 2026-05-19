#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# citrix/02-deploy-citrix-template.sh
# Deploys the Citrix VDA image definition to the gallery, then deploys the
# AIB image template and triggers the build.
# Build time is typically 60–120 minutes (VDA install + optimizer + Windows Update).
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

RESOURCE_GROUP="rg-imagebuilder"
LOCATION="eastus"
TEMPLATE_NAME="tmpl-win2022-citrix-vda"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

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

# ── Verify Citrix assets are in storage before triggering build ───────────────
echo "Verifying Citrix assets are present in storage..."
VDA_EXISTS=$(az storage blob exists \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --container-name "scripts" \
  --name "VDAServerSetup.exe" \
  --auth-mode login \
  --query "exists" -o tsv)

OPT_EXISTS=$(az storage blob exists \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --container-name "scripts" \
  --name "CitrixOptimizer.zip" \
  --auth-mode login \
  --query "exists" -o tsv)

if [[ "$VDA_EXISTS" != "true" || "$OPT_EXISTS" != "true" ]]; then
  echo "ERROR: Citrix assets missing from storage."
  echo "  VDAServerSetup.exe : $VDA_EXISTS"
  echo "  CitrixOptimizer.zip : $OPT_EXISTS"
  echo ""
  echo "Run 01-upload-citrix-assets.sh first."
  exit 1
fi

echo "  VDAServerSetup.exe  : found"
echo "  CitrixOptimizer.zip : found"
echo ""

# ── Deploy Citrix image definition ────────────────────────────────────────────
echo "Deploying Citrix VDA image definition to gallery..."
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$REPO_ROOT/infra/bicep/citrix-image-definition.bicep" \
  --parameters location="$LOCATION" \
  --name "deploy-citrix-image-definition" \
  --output table

# ── Deploy Citrix image template ──────────────────────────────────────────────
echo ""
echo "Deploying Citrix AIB image template: $TEMPLATE_NAME"
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$REPO_ROOT/infra/bicep/image-template-citrix.bicep" \
  --parameters "$REPO_ROOT/infra/bicep/image-template-citrix.parameters.json" \
  --parameters storageAccountName="$STORAGE_ACCOUNT_NAME" location="$LOCATION" \
  --name "deploy-citrix-image-template" \
  --output table

# ── Trigger build ─────────────────────────────────────────────────────────────
echo ""
echo "Starting Citrix VDA image build (60–120 minutes)..."
az image builder run \
  --resource-group "$RESOURCE_GROUP" \
  --name "$TEMPLATE_NAME" \
  --no-wait

echo "Build triggered. Streaming status every 60 seconds (Ctrl+C to detach — build continues in Azure):"
echo ""

while true; do
  STATUS=$(az image builder show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$TEMPLATE_NAME" \
    --query "lastRunStatus.runState" -o tsv 2>/dev/null || echo "Unknown")

  MESSAGE=$(az image builder show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$TEMPLATE_NAME" \
    --query "lastRunStatus.message" -o tsv 2>/dev/null || echo "")

  echo "[$(date '+%H:%M:%S')] $STATUS — $MESSAGE"

  if [[ "$STATUS" == "Succeeded" ]]; then
    echo ""
    echo "Citrix VDA image build succeeded."
    echo "The image is now available in gallery 'acg_golden_images' under definition 'win2022-citrix-vda'."
    echo ""
    echo "Use this image as the master image when creating MCS machine catalogs in Citrix DaaS."
    break
  elif [[ "$STATUS" == "Failed" || "$STATUS" == "Canceled" ]]; then
    echo ""
    echo "ERROR: Build ended with status: $STATUS"
    echo "Check AIB logs in the staging resource group (IT_${RESOURCE_GROUP}_*) for details."
    exit 1
  fi

  sleep 60
done
