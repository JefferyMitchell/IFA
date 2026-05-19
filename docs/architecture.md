---
layout: default
title: Architecture
nav_order: 2
---

# Azure Image Creation Factory

An image factory with Azure Image Builder (AIB) is a pipeline that automatically creates, tests, and distributes hardened/customized VM images across your organization.

![Azure Image Factory architecture diagram showing triggers, sources, AIB build process, Compute Gallery distribution, and consumers](<pics/AIB Factory.png>)

---

## Core Components

### Azure Image Builder (AIB)

The build engine. You define an image template (JSON/Bicep) that specifies:

- **A source image** (marketplace, existing managed image, or another gallery image)
- **Customization steps** (PowerShell scripts, Shell scripts, file uploads, Windows Update, restarts)
- **A distribution target** (where the finished image goes)

### Azure Compute Gallery (ACG)

*(formerly Shared Image Gallery)*

The distribution and versioning layer. Stores image definitions and versions, replicates them across regions, and controls access via RBAC. Acts as a private Marketplace for your organization.

### Supporting Services

| Service | Role |
|---|---|
| **Managed Identity** | Grants AIB permission to write to the gallery and read from source storage |
| **Azure DevOps / GitHub Actions** | Orchestrates the factory pipeline (trigger → build → test → publish) |
| **Key Vault** | Stores secrets used during customization (certificates, join passwords, etc.) |
| **Storage Account** | Hosts customization scripts and artifacts AIB downloads during the build |

---

## Factory Architecture

A schedule, Event Grid event, or CI/CD pipeline triggers AIB, which pulls a source image, runs customization steps inside a temporary build VM, then distributes the finished image to Azure Compute Gallery for multi-region consumption.

---

## Key Design Decisions

### 1. Image Versioning Strategy

Use date-stamped versions (`2026.05.19.01`) so consumers can pin to a known-good version while the factory publishes new ones. ACG supports `latest` as a floating pointer.

### 2. Layered Images (Chaining)

Build a hierarchy to avoid rebuilding everything from scratch each time:

```
Marketplace Base
    └── Golden Base (OS hardening, agents, certs)
            └── App-Specific Image (your runtime, config)
```

Each layer references the previous gallery version as its source. Only the changed layer needs to be rebuilt.

### 3. Replication Regions

Define which regions ACG replicates to based on where workloads run. Replication is async and billed per replica stored.

### 4. RBAC for Consumption

Grant subscription teams `Reader` on the gallery or specific image definitions so they can deploy from it but cannot modify it.

---

## Minimal AIB Template (Bicep)

```bicep
resource imageTemplate 'Microsoft.VirtualMachineImages/imageTemplates@2023-07-01' = {
  name: 'win2022-hardened-${timestamp}'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${managedIdentityId}': {} }
  }
  properties: {
    source: {
      type: 'PlatformImage'
      publisher: 'MicrosoftWindowsServer'
      offer: 'WindowsServer'
      sku: '2022-datacenter-azure-edition'
      version: 'latest'
    }
    customize: [
      {
        type: 'PowerShell'
        name: 'ApplyHardening'
        scriptUri: 'https://<storage>.blob.core.windows.net/scripts/harden.ps1'
      }
      { type: 'WindowsUpdate' }
      { type: 'WindowsRestart' }
    ]
    distribute: [
      {
        type: 'SharedImage'
        galleryImageId: '${gallery.id}/images/windows-server-hardened'
        runOutputName: 'win2022-output'
        replicationRegions: ['eastus', 'westeurope']
      }
    ]
    buildTimeoutInMinutes: 120
  }
}
```

---

## Common Factory Patterns

| Pattern | How |
|---|---|
| **Monthly patch cycle** | Cron-triggered pipeline rebuilds images on Patch Tuesday |
| **Zero-trust baseline** | Customization scripts apply CIS benchmarks, disable legacy protocols |
| **Agent injection** | Install monitoring (AMA), security (Defender), or management agents in the golden base |
| **AVD image factory** | Produce images consumed directly by AVD host pool updates |
| **Multi-OS** | Separate gallery definitions for Windows, RHEL, Ubuntu — same pipeline structure |

---

## Deployed Resource View

Once the factory is running, this is what exists inside your resource group — a managed identity, an image template, a Compute Gallery replicating across regions, and a temporary staging resource group that AIB auto-creates and deletes for each build.

![ Deployed resource view showing uami-aib managed identity, tmpl-win2022 image template, acg_golden_images Compute Gallery with multi-region replication, and auto-deleted staging RG](<pics/end result.png>)

---

## Next Steps

- **Pipeline code** — GitHub Actions or Azure DevOps YAML for end-to-end automation
- **Bicep/ARM templates** — Full gallery + AIB infrastructure setup
- **Customization scripts** — Hardening or agent installation during build
- **Networking** — Running AIB in a private VNet with proxy egress
- **Testing strategy** — VM compliance testing before publishing a new image version
