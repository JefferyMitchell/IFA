---
layout: default
title: Management
nav_order: 5
---

# Management
{: .no_toc }

Day-to-day operations for running, monitoring, and maintaining the Azure Image Factory.

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Triggering a Build

### Via GitHub Actions (Manual)

1. Navigate to your repository on GitHub
2. Go to **Actions** → **Build Image**
3. Click **Run workflow**
4. Select the branch and (optionally) the image template name
5. Click **Run workflow**

### Via Azure CLI

Trigger an AIB image template build directly:

```bash
az image builder run \
  --resource-group rg-image-factory \
  --name tmpl-windows-server-hardened \
  --no-wait
```

The `--no-wait` flag returns immediately. Use the monitoring commands below to track progress.

### Via Scheduled Pipeline

Builds configured with a cron schedule in `.github/workflows/build-image.yml` run automatically. No manual action is required unless you need to force an out-of-cycle build.

---

## Monitoring a Build

### Check Build Status (Azure CLI)

```bash
az image builder show \
  --resource-group rg-image-factory \
  --name tmpl-windows-server-hardened \
  --query lastRunStatus
```

Possible states:

| State | Meaning |
|---|---|
| `Running` | Build is in progress |
| `Succeeded` | Build completed and image was published |
| `Failed` | Build failed — check the error message |
| `Canceled` | Build was manually canceled |

### View Build Logs

Detailed logs are written to a storage account created by AIB in a staging resource group. The resource group is named `IT_<your-rg>_<template-name>_<guid>` and exists only during the build.

To retrieve logs:

```bash
# Find the staging resource group
az group list --query "[?starts_with(name, 'IT_rg-image-factory')].name" -o tsv

# List log blobs
az storage blob list \
  --account-name <staging-storage-account> \
  --container-name packerlogs \
  --output table
```

Alternatively, view logs in the Azure Portal under **Azure Image Builder** → select the template → **Run output**.

### GitHub Actions Run Logs

For pipeline-triggered builds, view full step-by-step logs directly in the GitHub Actions run summary under **Actions** → select the run.

---

## Publishing and Managing Image Versions

### View Published Versions

```bash
az sig image-version list \
  --resource-group rg-image-factory \
  --gallery-name acg_image_factory \
  --gallery-image-definition windows-server-hardened \
  --output table
```

### Deprecate an Old Version

Mark an older version as deprecated so consumers are warned away from it while it remains available for rollback:

```bash
az sig image-version update \
  --resource-group rg-image-factory \
  --gallery-name acg_image_factory \
  --gallery-image-definition windows-server-hardened \
  --gallery-image-version 2026.04.01.00 \
  --set publishingProfile.excludeFromLatest=true
```

### Delete an Old Version

Only delete versions after confirming no workloads depend on them:

```bash
az sig image-version delete \
  --resource-group rg-image-factory \
  --gallery-name acg_image_factory \
  --gallery-image-definition windows-server-hardened \
  --gallery-image-version 2026.01.01.00
```

> **Caution:** Deleting a version is permanent. Any VM deployed from that version will continue to run, but the image cannot be redeployed.

---

## Updating Customization Scripts

To update a script used during the build:

1. Edit the script locally in the `scripts/` folder
2. Upload the updated file to the storage account:

```bash
az storage blob upload \
  --account-name staimagefactory \
  --container-name scripts \
  --name harden-windows.ps1 \
  --file ./scripts/harden-windows.ps1 \
  --overwrite
```

3. Trigger a new build. The next run will pick up the updated script automatically.

---

## Updating the Image Template

If you need to change the template itself (e.g., add a customization step, change the VM size, or update replication regions):

1. Edit the Bicep template in `infra/bicep/`
2. Redeploy:

```bash
az deployment group create \
  --resource-group rg-image-factory \
  --template-file infra/bicep/main.bicep \
  --parameters location=eastus galleryName=acg_image_factory
```

> **Note:** You cannot update a template while a build is in progress. Wait for the current build to complete or cancel it first.

---

## Troubleshooting

### Step 1 — Get the Full Error Message

When a build fails, the first thing to check is the `lastRunStatus` on the image template. This gives you the error message without digging into logs:

```bash
az image builder show \
  --resource-group rg-image-factory \
  --name tmpl-win2022-base \
  --query lastRunStatus
```

The response includes `runState`, `runSubState`, and `message`. The `message` field usually identifies which customization step failed and why.

---

### Step 2 — Read the Packer Log

For script-level failures, the packer log has line-by-line output from every customization step.

**Find the AIB staging resource group:**

```bash
az group list \
  --query "[?starts_with(name, 'IT_rg-image-factory')].name" \
  -o tsv
```

The staging group is created by AIB at build start and deleted after the build (success or failure). If the build is still running or freshly failed, it will still be present.

**Find the storage account inside the staging group:**

```bash
STAGING_RG="IT_rg-image-factory_tmpl-win2022-base_<guid>"

az storage account list \
  --resource-group $STAGING_RG \
  --query "[].name" -o tsv
```

**Download the packer log:**

```bash
STAGING_SA="<staging-storage-account-name>"

# List available log blobs
az storage blob list \
  --account-name $STAGING_SA \
  --container-name packerlogs \
  --auth-mode login \
  --output table

# Download the log
az storage blob download \
  --account-name $STAGING_SA \
  --container-name packerlogs \
  --name "pkr-build.log" \
  --file ./packer-build.log \
  --auth-mode login
```

Open `packer-build.log` and search for `ERR` or the name of the failing customization step to find the exact failure point.

> **Tip:** If the staging resource group is already gone, enable **Azure Image Builder Logs** in the template's `distribute` section to send logs to a Log Analytics workspace for post-mortem analysis.

---

### Common Failure Scenarios

#### Build Fails at a Customization Script

| Symptom | Likely Cause | Fix |
|---|---|---|
| Script exits with non-zero code | Error in the PowerShell script | Run the script manually in a test VM first |
| `403 Forbidden` accessing script URI | Managed identity missing `Storage Blob Data Reader` on the scripts container | Re-run `az role assignment create` from `00-prerequisites.sh` |
| Script URI resolves but download fails | Storage account firewall blocking AIB build subnet | Add AIB's subnet to the storage account network rules, or disable the firewall for the build |
| `Windows Update` step times out | Too many patches queued for the timeout window | Increase `buildTimeoutMinutes` in `image-template.bicep` (default: 120) |
| Sysprep fails at generalization | A running service or scheduled task is blocking sysprep | Check the packer log for the sysprep error; disable the offending service in a customization step before sysprep |

#### Permission / Role Assignment Errors

If the template deploys but the build fails immediately with an authorization error:

```bash
# Confirm the managed identity has Contributor on the resource group
az role assignment list \
  --assignee <identity-principal-id> \
  --resource-group rg-image-factory \
  --output table

# Confirm the AIB service principal has Contributor at subscription scope
az role assignment list \
  --assignee cf32a0cc-373c-47c9-9156-0db11f6a6dfc \
  --scope /subscriptions/<subscription-id> \
  --output table
```

If either assignment is missing, re-run `scripts/setup/00-prerequisites.sh`.

#### Template Deployment Fails (Before Build Starts)

Use `what-if` to validate the template before deploying:

```bash
az deployment group what-if \
  --resource-group rg-image-factory \
  --template-file infra/bicep/image-template.bicep \
  --parameters storageAccountName=<your-storage-account>
```

Common causes: referencing a gallery or image definition that doesn't exist yet (run `01-deploy.sh` first), or a template with the same name already in a `Running` state.

#### Build VM Quota Exceeded

The build VM SKU (`Standard_D2s_v3` by default) must have quota available in the target region. If the build fails with a quota error:

```bash
# Check current quota for the SKU
az vm list-usage --location eastus \
  --query "[?contains(name.value, 'standardDSv3Family')]" \
  --output table
```

Request a quota increase in the Azure Portal under **Subscriptions → Usage + Quotas**, or change `buildVmSize` in the template to a SKU with available quota.

#### Image Version Not Replicating

Replication to secondary regions happens asynchronously after a successful build. Check per-region replication status:

```bash
az sig image-version show \
  --resource-group rg-image-factory \
  --gallery-name acg_golden_images \
  --gallery-image-definition win2022-base \
  --gallery-image-version 2026.05.19.01 \
  --query publishingProfile.targetRegions
```

Each region entry shows a `regionalReplicaCount` and `storageAccountType`. If a region is stuck in `Replicating`, check that the subscription has sufficient storage quota in that region.

#### Citrix VDA Build Failures

| Symptom | Likely Cause | Fix |
|---|---|---|
| VDA installer not found at `C:\Windows\Temp\` | File customizer failed to stage the installer | Confirm the blob exists in storage and the identity has `Storage Blob Data Reader` |
| VDA install exits with code other than 0 or 3 | Install error | Check packer log for the VDA installer output; common causes are missing prerequisites or incompatible OS version |
| Citrix Optimizer template not found | Wrong template filename or path inside the zip | Verify the XML filename in `run-citrix-optimizer.ps1` matches what is inside `CitrixOptimizer.zip` |
| BrokerAgent or picaSvc2 not running post-build | VDA install succeeded but validation step failed | Review VDA install log at `C:\Windows\Temp\VDA\` in the packer output |

---

---

## Routine Maintenance Checklist

Run this checklist monthly (ideally after each successful build cycle):

- [ ] Confirm latest image version published and replicated to all target regions
- [ ] Review and deprecate image versions older than 3 months
- [ ] Audit managed identity role assignments — remove any excess permissions
- [ ] Review customization script logs for warnings or deprecated commands
- [ ] Verify storage account containing scripts has not exceeded retention policy
- [ ] Check GitHub Actions workflow runs for any flaky or slow steps
