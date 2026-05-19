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

### Build Fails at Customization Step

Check the packer logs in the AIB staging resource group (see [Monitoring a Build](#monitoring-a-build)). The logs show which customization step failed and the error output from the script.

Common causes:

| Symptom | Likely Cause |
|---|---|
| Script exits with non-zero code | Script error — test the script locally before using in AIB |
| Script URI not accessible | Storage account firewall blocking AIB; ensure the managed identity has `Storage Blob Data Reader` on the container |
| Windows Update times out | Increase `buildTimeoutInMinutes` in the template |
| Sysprep fails | A running service is preventing generalization — check the script for services that shouldn't persist |

### Build VM Quota Exceeded

If the build fails with a quota error, request a quota increase for the VM SKU used by AIB (`Standard_D2s_v3` by default) in the subscription and region.

### Image Version Not Replicating

Replication to secondary regions happens asynchronously after the build. Check replication status:

```bash
az sig image-version show \
  --resource-group rg-image-factory \
  --gallery-name acg_image_factory \
  --gallery-image-definition windows-server-hardened \
  --gallery-image-version 2026.05.19.01 \
  --query publishingProfile.targetRegions
```

---

## Routine Maintenance Checklist

Run this checklist monthly (ideally after each successful build cycle):

- [ ] Confirm latest image version published and replicated to all target regions
- [ ] Review and deprecate image versions older than 3 months
- [ ] Audit managed identity role assignments — remove any excess permissions
- [ ] Review customization script logs for warnings or deprecated commands
- [ ] Verify storage account containing scripts has not exceeded retention policy
- [ ] Check GitHub Actions workflow runs for any flaky or slow steps
