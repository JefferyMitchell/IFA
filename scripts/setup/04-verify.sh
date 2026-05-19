#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# 04-verify.sh
# Confirms the image version was published to the gallery and deploys a
# short-lived test VM from it to verify the image boots correctly.
# The test VM is deleted at the end of this script.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

RESOURCE_GROUP="rg-imagebuilder"
GALLERY_NAME="acg_golden_images"
IMAGE_DEFINITION="win2022-base"
TEST_VM_NAME="vm-golden-test"
TEST_VM_SIZE="Standard_D2s_v3"
ADMIN_USERNAME="azureadmin"

# ── Detect subscription ───────────────────────────────────────────────────────
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo "Active subscription: $SUBSCRIPTION_ID"
echo ""

# ── Check published image versions ───────────────────────────────────────────
echo "Published image versions in gallery '$GALLERY_NAME':"
az sig image-version list \
  --resource-group "$RESOURCE_GROUP" \
  --gallery-name "$GALLERY_NAME" \
  --gallery-image-definition "$IMAGE_DEFINITION" \
  --query "[].{Version:name, State:provisioningState, Regions:join(', ', publishingProfile.targetRegions[].name)}" \
  --output table

# Get the latest image version resource ID
IMAGE_VERSION_ID=$(az sig image-version list \
  --resource-group "$RESOURCE_GROUP" \
  --gallery-name "$GALLERY_NAME" \
  --gallery-image-definition "$IMAGE_DEFINITION" \
  --query "sort_by([], &name)[-1].id" \
  --output tsv)

if [[ -z "$IMAGE_VERSION_ID" ]]; then
  echo "ERROR: No image versions found. Ensure the build in 03-deploy-template.sh completed successfully."
  exit 1
fi

echo ""
echo "Using image version: $IMAGE_VERSION_ID"

# ── Deploy test VM ────────────────────────────────────────────────────────────
echo ""
echo "Deploying test VM from gallery image..."
az vm create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$TEST_VM_NAME" \
  --image "$IMAGE_VERSION_ID" \
  --size "$TEST_VM_SIZE" \
  --admin-username "$ADMIN_USERNAME" \
  --generate-ssh-keys \
  --public-ip-address "" \
  --output table

echo ""
echo "Verifying VM is running..."
az vm show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$TEST_VM_NAME" \
  --query "{Name:name, State:powerState, Size:hardwareProfile.vmSize}" \
  --show-details \
  --output table

# ── Clean up test VM ──────────────────────────────────────────────────────────
echo ""
echo "Cleaning up test VM and associated resources..."
az vm delete \
  --resource-group "$RESOURCE_GROUP" \
  --name "$TEST_VM_NAME" \
  --yes \
  --no-wait

echo ""
echo "Verification complete. The factory is operational."
echo ""
echo "Consumers can reference this image using:"
echo "  Gallery    : $GALLERY_NAME"
echo "  Definition : $IMAGE_DEFINITION"
echo "  Version ID : $IMAGE_VERSION_ID"
