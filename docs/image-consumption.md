---
layout: default
title: Image Consumption
nav_order: 7
---

# Image Consumption
{: .no_toc }

What the factory delivers, what it deliberately leaves out, and how to wire up the remaining per-environment configuration when deploying VMs from gallery images.

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## What the Factory Delivers

The factory publishes a versioned, hardened Windows Server 2022 image to the Azure Compute Gallery. Every version has gone through:

- Agent installation (monitoring, management)
- Security hardening (services, registry, SMB)
- Fully patched Windows Update at build time
- Post-patch validation confirming hardening survived the update cycle

What the image does **not** contain is anything environment- or tenant-specific — workspace IDs, onboarding keys, domain credentials, or data collection rules. Those belong to the team and environment consuming the image, not to the image itself.

---

## Deploying a VM from the Gallery

### CLI

```bash
# Get the latest image version ID from the gallery
IMAGE_ID=$(az sig image-version list \
  --resource-group rg-image-factory \
  --gallery-name acg_golden_images \
  --gallery-image-definition win2022-base \
  --query "sort_by(@, &publishingProfile.publishedDate)[-1].id" \
  -o tsv)

# Deploy a VM from that image
az vm create \
  --resource-group rg-your-workload \
  --name vm-your-server \
  --image "$IMAGE_ID" \
  --size Standard_D4s_v3 \
  --admin-username azureadmin \
  --generate-ssh-keys
```

### Bicep

Reference the gallery image definition directly in your VM resource. Using `'latest'` always resolves to the newest published version at deployment time:

```bicep
resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  properties: {
    storageProfile: {
      imageReference: {
        id: resourceId(
          imageFactoryResourceGroup,
          'Microsoft.Compute/galleries/images',
          'acg_golden_images',
          'win2022-base'
        )
      }
    }
    // ... rest of VM config
  }
}
```

> Use a specific version ID in production if you need to pin deployments to a known-good build and control when updates roll out.

---

## Baked In vs. Applied at Deployment

The image factory bakes in everything that is **universal and configuration-agnostic**. Everything that needs a per-VM, per-environment, or per-tenant value must be applied after the VM is running.

| What | In the image? | Why not (if no) | How to apply |
|---|---|---|---|
| Security hardening (services, registry, SMB) | Yes | — | Applied by factory |
| Windows patches | Yes (at build time) | — | Applied by factory |
| Monitoring agent binaries | Yes | — | Applied by factory |
| Azure Monitor Agent — Data Collection Rule | No | DCR is workspace/environment-specific | VM extension + DCR association |
| Microsoft Defender for Endpoint | No | Onboarding package is tenant-specific | MDE extension or Intune/Defender for Cloud |
| Domain join | No | Machine-specific credential and OU | VM extension: `JsonADDomainExtension` |
| Microsoft Entra ID join | No | Tenant-specific | VM extension: `AADLoginForWindows` |
| Per-environment config / secrets | No | Varies per workload | Custom Script Extension or cloud-init on first boot |

---

## Common Extensions

### Azure Monitor Agent + Data Collection Rule

The agent binary may already be present from the `InstallAgents` customization step. If not, the extension installs it. Either way, the Data Collection Rule association is always required — it tells the agent what to collect and where to send it.

```bicep
resource amaExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  parent: vm
  name: 'AzureMonitorWindowsAgent'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorWindowsAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
  }
}

resource dcrAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01' = {
  name: 'dcra-${vmName}'
  scope: vm
  properties: {
    dataCollectionRuleId: dataCollectionRuleId
  }
}
```

### Microsoft Defender for Endpoint

The MDE extension handles onboarding automatically when applied. Alternatively, Defender for Cloud with auto-provisioning or Intune can push this without touching Bicep.

```bicep
resource mdeExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  parent: vm
  name: 'MDE.Windows'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.AzureDefenderForServers'
    type: 'MDE.Windows'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    settings: {
      azureResourceId: vm.id
      defenderForServersWorkspaceId: mdeWorkspaceId
    }
  }
}
```

### Domain Join

```bicep
resource domainJoinExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  parent: vm
  name: 'JoinDomain'
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'JsonADDomainExtension'
    typeHandlerVersion: '1.3'
    autoUpgradeMinorVersion: true
    settings: {
      Name: domainFqdn
      OUPath: ouPath
      User: '${domainFqdn}\\${domainJoinUser}'
      Restart: true
      Options: 3
    }
    protectedSettings: {
      Password: domainJoinPassword
    }
  }
}
```

---

## Applying Extensions at Scale

For fleets rather than individual VMs, prefer policy-driven delivery over per-VM Bicep:

- **Azure Policy built-in initiatives** — "Enable Azure Monitor for VMs" and "Configure Microsoft Defender for Endpoint integration" auto-provision AMA and MDE on any VM that doesn't have them, including VMs deployed from the gallery.
- **Defender for Cloud auto-provisioning** — covers MDE and AMA without any VM-level Bicep changes. Enable at the subscription level under **Defender for Cloud → Environment settings**.
- **Microsoft Intune** — for hybrid or Entra-joined VMs, Intune can push MDE onboarding, compliance policies, and configuration profiles post-join without touching ARM.

The factory image is compatible with all three approaches — because nothing environment-specific is baked in, the same gallery image works across dev, staging, and production subscriptions with different extension configurations applied by policy in each.
