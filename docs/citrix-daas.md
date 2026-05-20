---
layout: default
title: Citrix DaaS (MCS)
nav_order: 6
---

# Citrix DaaS — Machine Creation Services Extension
{: .no_toc }

This guide extends the Image Factory for Azure to produce master images for **Citrix DaaS (traditional)** using **Machine Creation Services (MCS)**. MCS consumes images directly from Azure Compute Gallery, making it a natural fit for the factory pipeline.

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## How Citrix DaaS (MCS) Uses the Factory

In the standard Citrix DaaS model on Azure, MCS provisions machine catalogs by cloning a **master image** stored in Azure Compute Gallery. Every VM in the catalog is a thin-clone of that image. When a new image version is published to the gallery, you update the catalog and MCS rolls out the new image on the next machine reset or rebuild cycle.

```
Image Factory for Azure
        │
        ▼
  Azure Compute Gallery
  win2022-citrix-vda  ← master image with Citrix VDA + hardening
        │
        ▼
  Citrix DaaS (MCS)
  ┌──────────────────────────────────────────┐
  │  Machine Catalog (Azure)                 │
  │  • Pulls latest version from gallery     │
  │  • Clones to N VMs on provisioning       │
  │  • Rolls out new versions on next reset  │
  └──────────────────────────────────────────┘
        │
        ▼
  Published Desktops / Apps
  (delivered via Citrix Workspace)
```

---

## What Is Different About the Citrix Image

The Citrix image extends the base hardened image with two additional layers:

| Layer | What It Does |
|---|---|
| **Citrix VDA** | The Virtual Delivery Agent — the core component that enables HDX protocol, session brokering, and communication with Citrix Cloud Connectors |
| **Citrix Optimizer** | Reduces OS overhead for multi-session VDI workloads — disables unnecessary scheduled tasks, services, and visual effects |

The hardening and agent scripts from the base image run in the same build, after the VDA is installed, so the Citrix image inherits the same security baseline.

---

## Prerequisites

Complete the [Setup](./setup) guide first. The Citrix extension uses the same resource group, managed identity, storage account, and gallery.

In addition you need:

### 1. Citrix DaaS Subscription
An active Citrix DaaS (cloud) subscription. The Citrix Cloud Connectors in your Azure subscription handle communication between MCS-provisioned VMs and Citrix Cloud — they do not need to be installed in the image.

### 2. Citrix VDA Installer

Download the **Server OS VDA** installer from the Citrix download portal:

```
https://www.citrix.com/downloads/citrix-virtual-apps-and-desktops/
→ Citrix Virtual Delivery Agent (Server OS)
→ VDAServerSetup_XXXX.exe
```

Rename the file to `VDAServerSetup.exe` and save it to `~/clouddrive/citrix-assets/` in Cloud Shell.

{: .highlight }
> A Citrix account with entitlements is required to download the installer. The file is **not** stored in this repository.

### 3. Citrix Optimizer

Download Citrix Optimizer from the Citrix support portal:

```
https://support.citrix.com/article/CTX224676
```

Rename the archive to `CitrixOptimizer.zip` and save it to `~/clouddrive/citrix-assets/` in Cloud Shell.

---

## Build Steps

### Step 1 — Upload Citrix Assets to Storage

With both files in `~/clouddrive/citrix-assets/`, run:

```bash
bash scripts/setup/citrix/01-upload-citrix-assets.sh
```

This uploads `VDAServerSetup.exe` and `CitrixOptimizer.zip` to the factory storage account. The script verifies both files are present before uploading and confirms the blobs after upload.

### Step 2 — Deploy the Image Template and Trigger the Build

```bash
bash scripts/setup/citrix/02-deploy-citrix-template.sh
```

This script:
1. Deploys the `win2022-citrix-vda` image definition to the gallery
2. Deploys the AIB image template (`tmpl-win2022-citrix-vda`)
3. Verifies both Citrix assets are reachable in storage before triggering
4. Starts the build and streams status every 60 seconds

**Expected build time: 60–120 minutes.** The build is longer than the base image because it includes VDA installation, a mid-build restart, Citrix Optimizer, and Windows Update.

---

## What Happens During the Build

The customization sequence in order:

| Step | Type | Description |
|---|---|---|
| StageVDAInstaller | File | AIB copies `VDAServerSetup.exe` from storage into the build VM |
| StageCitrixOptimizer | File | AIB copies `CitrixOptimizer.zip` from storage into the build VM |
| InstallAgents | PowerShell | Monitoring and management agents |
| InstallCitrixVDA | PowerShell | Silent VDA install with MCS flags — no DDC/Cloud Connector addresses baked in |
| WindowsRestart | Restart | Required after VDA installation |
| RunCitrixOptimizer | PowerShell | Applies Windows Server 2022 optimization template |
| ApplyHardening | PowerShell | CIS baseline hardening — runs after VDA so VDA services are accounted for |
| WindowsUpdate | Update | OS patches applied |
| WindowsRestart | Restart | Restart after patching |
| ReApplyHardening | PowerShell | Re-runs hardening script — Windows Update can reset service startup types set by the earlier hardening step |
| PostBuildValidation | PowerShell | Confirms `BrokerAgent` and `picaSvc2` services exist |

---

## Key VDA Install Flags

The VDA is installed with flags that make it suitable for MCS without requiring reconfiguration:

| Flag | Purpose |
|---|---|
| `/mastermcsimage` | MCS-specific optimisations. Disables write-cache persistence and configures identity disk handling. **Required for MCS catalogs.** |
| `/masterimage` | Marks the VM as a template. Suppresses machine-specific configuration. |
| `/noreboot` | Defers all restarts to AIB's `WindowsRestart` steps. |
| `/enable_hdx_ports` | Opens firewall rules for HDX (TCP 1494, 2598; UDP 16500–16509). |

Cloud Connector addresses are intentionally **not** specified in the image. MCS injects the correct connector registration when it provisions each catalog VM.

---

## Consuming the Image in Citrix DaaS

Once the build completes and the image version is replicated to the gallery, point a new MCS machine catalog at it:

1. In **Citrix Studio** (or Citrix Cloud → DaaS → Machine Catalogs), create a new catalog
2. Select **Microsoft Azure** as the hosting connection
3. For the master image, select **Azure Compute Gallery** and choose:
   - Gallery: `acg_golden_images`
   - Image definition: `win2022-citrix-vda`
   - Version: select `latest` or pin to a specific version
4. Complete the catalog wizard — MCS handles all provisioning from the gallery image

### Updating the Catalog After a New Build

When a new image version is published:

1. In Citrix Studio, select the machine catalog
2. Choose **Change Master Image**
3. Select the new gallery image version
4. Choose a rollout strategy:
   - **On next shutdown** — machines update as users log off (minimal disruption)
   - **Immediately** — forces session termination and immediate update

---

## Troubleshooting

### VDA Validation Fails at End of Build

The post-build validation checks for `BrokerAgent` and `picaSvc2`. If either is missing:

- Check the VDA install log at `C:\Windows\Temp\VDAInstall.log` in the AIB staging resource group logs
- Confirm `VDAServerSetup.exe` is the Server OS variant (not the Workstation/VDI variant)
- Ensure the `/components VDA` flag is not excluding a required sub-component

### Citrix Optimizer Template Not Found

The optimizer script expects `Citrix_Windows_Server_2022_2203.xml` inside the zip. If the template name differs in your downloaded version:

1. Update the `$TemplateName` variable at the top of [scripts/customization/run-citrix-optimizer.ps1](../scripts/customization/run-citrix-optimizer.ps1)
2. Re-upload the script and re-run the build

### MCS Catalog Fails to Provision from Gallery Image

Confirm the managed identity has `Contributor` on the resource group (assigned by the factory infrastructure). MCS uses the Citrix hosting connection service principal — ensure it has at minimum `Reader` on the gallery and `Virtual Machine Contributor` on the catalog resource group.
