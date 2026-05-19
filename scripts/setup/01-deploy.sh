#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# 01-deploy.sh
# Deploys the factory infrastructure: managed identity, storage account,
# and Azure Compute Gallery with the win2022-base image definition.
# Run from Cloud Shell with the repo cloned to ~/clouddrive/aib/
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

RESOURCE_GROUP="rg-imagebuilder"
LOCATION="eastus"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ── Step 1: Confirm subscription ──────────────────────────────────────────────
echo "Detecting active Azure subscription..."
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)

echo ""
echo "  Name : $SUBSCRIPTION_NAME"
echo "  ID   : $SUBSCRIPTION_ID"
echo ""
read -rp "Deploy to this subscription? [Y/n]: " confirm

if [[ "$confirm" =~ ^[Nn] ]]; then
  read -rp "Enter the subscription ID to use: " SUBSCRIPTION_ID
  az account set --subscription "$SUBSCRIPTION_ID"
fi

# ── Step 2: Generate storage account name ─────────────────────────────────────
# Derived from the subscription ID — deterministic and globally unique.
# Format: staib + first 15 chars of subscription ID (dashes removed) = 20 chars
STORAGE_ACCOUNT_NAME="staib$(echo "$SUBSCRIPTION_ID" | tr -d '-' | cut -c1-15)"

echo ""
echo "Deployment settings:"
echo "  Resource group       : $RESOURCE_GROUP"
echo "  Location             : $LOCATION"
echo "  Storage account name : $STORAGE_ACCOUNT_NAME"
echo ""
read -rp "Proceed with deployment? [Y/n]: " proceed
if [[ "$proceed" =~ ^[Nn] ]]; then exit 0; fi

# ── Step 3: Create resource group ─────────────────────────────────────────────
echo ""
echo "Creating resource group: $RESOURCE_GROUP"
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --output none

# ── Step 4: Deploy infrastructure via Bicep ───────────────────────────────────
echo "Deploying factory infrastructure (identity, storage, gallery)..."
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$REPO_ROOT/infra/bicep/main.bicep" \
  --parameters "$REPO_ROOT/infra/bicep/main.parameters.json" \
  --parameters storageAccountName="$STORAGE_ACCOUNT_NAME" location="$LOCATION" \
  --name "deploy-image-factory-infra" \
  --output table

echo ""
echo "Infrastructure deployed. Resources in $RESOURCE_GROUP:"
az resource list --resource-group "$RESOURCE_GROUP" --output table

echo ""
echo "  Storage account name : $STORAGE_ACCOUNT_NAME"
echo ""
echo "Proceed to 02-upload-scripts.sh"
