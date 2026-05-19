---
layout: default
title: Configuration
nav_order: 4
---

# Configuration
{: .no_toc }

This guide covers configuring the factory: defining image types in Azure Compute Gallery, creating AIB image templates, and customizing the build process.

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Azure Compute Gallery

### Image Definitions

An **image definition** describes a class of image — its OS, architecture, and lifecycle policy. Actual built images are stored as **image versions** under a definition.

Create a definition for each distinct image type you want to produce:

```bash
az sig image-definition create \
  --resource-group rg-image-factory \
  --gallery-name acg_image_factory \
  --gallery-image-definition windows-server-hardened \
  --publisher MyOrg \
  --offer WindowsServer \
  --sku 2022-hardened \
  --os-type Windows \
  --os-state Generalized \
  --hyper-v-generation V2
```

**Key fields:**

| Field | Notes |
|---|---|
| `--os-state Generalized` | Required — AIB always produces generalized images |
| `--hyper-v-generation V2` | Recommended for modern workloads; must match your source image |
| `--publisher / --offer / --sku` | Used internally to identify the image — choose a consistent naming convention |

### Replication Regions

Replication is defined on each **image version** at publish time, not on the definition. Plan your target regions based on where workloads run and account for the per-replica storage cost.

---

## AIB Image Templates

An **image template** defines the full build — source, customization steps, and distribution target. Templates are deployed as ARM/Bicep resources and can be triggered on demand or via pipeline.

### Template Structure

```bicep
resource imageTemplate 'Microsoft.VirtualMachineImages/imageTemplates@2023-07-01' = {
  name: 'tmpl-windows-server-hardened'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${managedIdentity.id}': {} }
  }
  properties: {
    buildTimeoutInMinutes: 120
    vmProfile: {
      vmSize: 'Standard_D2s_v3'
      osDiskSizeGB: 128
    }
    source: {
      type: 'PlatformImage'
      publisher: 'MicrosoftWindowsServer'
      offer: 'WindowsServer'
      sku: '2022-datacenter-azure-edition'
      version: 'latest'
    }
    customize: [ /* see below */ ]
    distribute: [
      {
        type: 'SharedImage'
        galleryImageId: '${gallery.id}/images/windows-server-hardened'
        runOutputName: 'output-windows-server-hardened'
        replicationRegions: ['eastus', 'westeurope']
        storageAccountType: 'Standard_LRS'
      }
    ]
  }
}
```

---

## Customization Steps

Customization steps run sequentially inside the build VM. AIB supports several step types:

### PowerShell (Windows)

Run an inline script or a script hosted in storage:

```bicep
{
  type: 'PowerShell'
  name: 'ApplyCISHardening'
  scriptUri: 'https://${storageAccount.name}.blob.core.windows.net/scripts/harden-windows.ps1'
  runElevated: true
}
```

### Shell (Linux)

```bicep
{
  type: 'Shell'
  name: 'InstallAgents'
  scriptUri: 'https://${storageAccount.name}.blob.core.windows.net/scripts/install-agents.sh'
}
```

### Windows Update

Runs Windows Update and restarts the VM automatically. Always include this for Windows images:

```bicep
{ type: 'WindowsUpdate' }
```

### Restart

Forces a restart between steps — required after driver installs or major configuration changes:

```bicep
{
  type: 'WindowsRestart'
  restartTimeout: '10m'
}
```

### File

Copies a file from storage into the build VM:

```bicep
{
  type: 'File'
  name: 'CopyCertificate'
  sourceUri: 'https://${storageAccount.name}.blob.core.windows.net/certs/root-ca.cer'
  destination: 'C:\\Windows\\Temp\\root-ca.cer'
}
```

### Recommended Step Order (Windows)

```
1. File        — copy any required certs or config files
2. PowerShell  — install software and agents
3. WindowsUpdate
4. WindowsRestart
5. PowerShell  — apply OS hardening (post-patch)
6. WindowsRestart
```

---

## Layered Image Strategy

To reduce build time and avoid duplicating work, chain images so each layer builds on the previous:

```
Marketplace Base
    └── Golden Base image definition
            • OS hardening (CIS)
            • Monitoring agent (AMA)
            • Defender for Endpoint
            └── App-Specific image definition
                    • Application runtime
                    • App-specific configuration
```

In each downstream template, set the source to a gallery image version rather than a marketplace image:

```bicep
source: {
  type: 'SharedImageVersion'
  imageVersionId: '${gallery.id}/images/golden-base/versions/latest'
}
```

---

## Pipeline Configuration

The GitHub Actions workflow in `.github/workflows/build-image.yml` controls when builds are triggered.

### Scheduled Build (Monthly Patch Cycle)

```yaml
on:
  schedule:
    - cron: '0 6 * * 3'   # Every Wednesday at 06:00 UTC (Patch Tuesday + 1 day)
  workflow_dispatch:        # Also allow manual trigger
```

### Build VM Size

For images requiring more memory or faster builds, override the VM size in the template:

```bicep
vmProfile: {
  vmSize: 'Standard_D4s_v3'
  osDiskSizeGB: 256
}
```

---

## Next Steps

With templates and customization configured, see [Management](./management) for how to trigger builds, monitor progress, and operate the factory day-to-day.
