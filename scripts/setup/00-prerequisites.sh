#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# 00-prerequisites.sh
# Run once per subscription before any other setup step.
# Detects your active subscription, registers required resource providers,
# and grants the AIB service principal the Contributor role so it can
# create staging resource groups during builds.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Step 1: Detect active subscription ───────────────────────────────────────
echo "Detecting active Azure subscription..."
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)

echo ""
echo "  Name : $SUBSCRIPTION_NAME"
echo "  ID   : $SUBSCRIPTION_ID"
echo ""
read -rp "Use this subscription? [Y/n]: " confirm

if [[ "$confirm" =~ ^[Nn] ]]; then
  echo ""
  echo "Available subscriptions:"
  az account list --query "[].{Name:name, ID:id, State:state}" --output table
  echo ""
  read -rp "Enter the subscription ID to use: " SUBSCRIPTION_ID
  az account set --subscription "$SUBSCRIPTION_ID"
  echo "Switched to: $SUBSCRIPTION_ID"
fi

# ── Step 2: Register resource providers ──────────────────────────────────────
echo ""
echo "Registering resource providers (this may take a few minutes)..."
az provider register --namespace Microsoft.VirtualMachineImages --wait
az provider register --namespace Microsoft.Compute --wait
az provider register --namespace Microsoft.KeyVault --wait
az provider register --namespace Microsoft.Storage --wait
az provider register --namespace Microsoft.Network --wait
az provider register --namespace Microsoft.ManagedIdentity --wait

echo ""
echo "Verifying AIB provider registration..."
REGISTRATION=$(az provider show --namespace Microsoft.VirtualMachineImages --query registrationState -o tsv)
echo "  Microsoft.VirtualMachineImages: $REGISTRATION"

if [[ "$REGISTRATION" != "Registered" ]]; then
  echo "ERROR: Provider not yet registered. Wait a moment and re-run this script."
  exit 1
fi

# ── Step 3: Grant AIB service principal Contributor on the subscription ───────
# AIB needs this to create and delete the temporary staging resource group
# it provisions automatically during each build run.
echo ""
echo "Looking up Azure Image Builder service principal..."
AIB_SP_ID=$(az ad sp show --id cf32a0cc-373c-47c9-9156-0db11f6a6dfc --query id -o tsv 2>/dev/null || true)

if [[ -z "$AIB_SP_ID" ]]; then
  echo "ERROR: AIB service principal not found. Ensure the provider is fully registered and retry."
  exit 1
fi

echo "Assigning Contributor role to AIB service principal..."
az role assignment create \
  --assignee-object-id "$AIB_SP_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Contributor" \
  --scope "/subscriptions/${SUBSCRIPTION_ID}" \
  --output none

echo ""
echo "Prerequisites complete."
echo "  Subscription ID : $SUBSCRIPTION_ID"
echo ""
echo "Proceed to 01-deploy.sh"
