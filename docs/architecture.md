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

### 5. Subscription Strategy

Most organizations should run the factory across **two subscriptions** rather than one:

| Subscription | Purpose | Recommended Role |
|---|---|---|
| **Non-prod** | Dev and test image builds, pipeline experimentation, template development | `Owner` |
| **Prod** | Golden images consumed by production workloads | `Contributor` + `User Access Administrator` |

A single subscription is acceptable for small teams or pure dev/test environments. Consider adding more subscriptions when:

- **Compliance boundaries** require production workloads to be isolated with stricter audit logging and policy enforcement
- **Cost attribution** needs to be split across teams or cost centers without complex tagging
- **Regional isolation** is required for data residency — one subscription per geography keeps images and build artifacts within the required boundary
- **Scale limits** are reached — Azure caps concurrent AIB builds and gallery replications per subscription; high-volume environments may need to spread across subscriptions

> **Tip:** `Owner` covers both `Contributor` and `User Access Administrator`. On a dedicated non-prod factory subscription it is the simplest starting point. Tighten to explicit roles on production.

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

## Cost Considerations

AIB itself has no licensing fee — you pay only for the Azure resources consumed during a build. The table below shows real-world costs from a single end-to-end build of a Windows Server 2022 image with hardening scripts, Windows Update, and single-region replication to East US.

| Resource | Details | Cost per build |
|---|---|---|
| **Build VM** | Standard_D2s_v3, ~75 min | ~$0.12 |
| **OS disk** | 128 GB managed disk during build | ~$0.01 |
| **Storage** | Scripts container (< 10 MB) | < $0.01 |
| **Gallery storage** | One image version, East US | ~$0.05 / month |
| **Replication** | Each additional region adds ~$0.04–0.08 per version depending on image size | Per region |

**Typical single-region build: under $0.20.**

Costs that grow with scale:
- **Number of image definitions** — each version stored in the gallery adds storage cost (~$0.05/month per version per region)
- **Replication regions** — each region is a full copy; 3-region replication triples gallery storage cost
- **Build frequency** — a weekly patch cycle (52 builds/year) on a single definition costs roughly $10/year in compute

> **Cost tip:** Set a retention policy on gallery image versions. Keeping only the last 3–5 versions per definition avoids unbounded storage growth as the factory matures.

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
