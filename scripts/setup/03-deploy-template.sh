#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# 03-deploy-template.sh
# Deploys the AIB image template and immediately triggers the first build.
# The build takes 30–90 minutes. Progress is streamed to the terminal.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-imagebuilder}"
LOCATION="eastus"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

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

# ── Deploy image template ─────────────────────────────────────────────────────
echo "Deploying AIB image template..."
deployment_output=$(az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$REPO_ROOT/infra/bicep/image-template.bicep" \
  --parameters "$REPO_ROOT/infra/bicep/image-template.parameters.json" \
  --parameters storageAccountName="$STORAGE_ACCOUNT_NAME" location="$LOCATION" \
  --name "deploy-image-template" \
  --query properties.outputs \
  --output json)

# AVM appends a UTC timestamp to the template name — retrieve the actual deployed name
TEMPLATE_NAME=$(echo "$deployment_output" | jq -r '.imageTemplateName.value')
echo "  Deployed template : $TEMPLATE_NAME"

# ── Trigger build ─────────────────────────────────────────────────────────────
echo ""
echo "Starting image build (30–90 minutes)..."
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
    echo "Build succeeded. Proceed to 04-verify.sh"
    break
  elif [[ "$STATUS" == "Failed" || "$STATUS" == "Canceled" ]]; then
    echo ""
    echo "ERROR: Build ended with status: $STATUS"
    echo "Check AIB logs in the staging resource group (IT_${RESOURCE_GROUP}_*) for details."
    exit 1
  fi

  sleep 60
done
