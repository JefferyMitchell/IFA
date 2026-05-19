targetScope = 'resourceGroup'

@description('Azure region. Must match the region used for main.bicep.')
param location string = resourceGroup().location

@description('Name of the AIB image template resource')
param templateName string = 'tmpl-win2022-base'

@description('Name of the existing user-assigned managed identity (deployed by main.bicep)')
param identityName string = 'uami-aib'

@description('Name of the existing Azure Compute Gallery (deployed by main.bicep)')
param galleryName string = 'acg_golden_images'

@description('Name of the existing image definition in the gallery')
param imageDefinitionName string = 'win2022-base'

@description('Name of the existing storage account holding build scripts')
param storageAccountName string

@description('Regions to replicate the finished image version to')
param replicationRegions array = ['eastus', 'westus2', 'westeurope']

@description('Build VM size — increase if build times out or scripts require more memory')
param buildVmSize string = 'Standard_D2s_v3'

@description('Maximum build time in minutes before AIB times out')
param buildTimeoutMinutes int = 120

// ── Reference existing resources created by main.bicep ───────────────────────
resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: identityName
}

resource gallery 'Microsoft.Compute/galleries@2022-03-03' existing = {
  name: galleryName
}

resource imageDefinition 'Microsoft.Compute/galleries/images@2022-03-03' existing = {
  parent: gallery
  name: imageDefinitionName
}

// ── AIB Image Template ────────────────────────────────────────────────────────
resource imageTemplate 'Microsoft.VirtualMachineImages/imageTemplates@2023-07-01' = {
  name: templateName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identity.id}': {}
    }
  }
  properties: {
    buildTimeoutInMinutes: buildTimeoutMinutes
    vmProfile: {
      vmSize: buildVmSize
      osDiskSizeGB: 128
    }
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
        name: 'InstallAgents'
        scriptUri: 'https://${storageAccountName}.blob.core.windows.net/scripts/install-agents.ps1'
        runElevated: true
      }
      {
        type: 'PowerShell'
        name: 'ApplyHardening'
        scriptUri: 'https://${storageAccountName}.blob.core.windows.net/scripts/harden-windows.ps1'
        runElevated: true
      }
      {
        type: 'WindowsUpdate'
      }
      {
        type: 'WindowsRestart'
        restartTimeout: '10m'
      }
      {
        // Final validation — runs after patching to confirm hardening survived update
        type: 'PowerShell'
        name: 'PostPatchValidation'
        inline: [
          'Write-Output "Validating post-patch state..."'
          'if ((Get-Service -Name RemoteRegistry).StartType -ne "Disabled") { throw "RemoteRegistry not disabled" }'
          'Write-Output "Validation passed — image ready for distribution"'
        ]
        runElevated: true
      }
    ]
    distribute: [
      {
        type: 'SharedImage'
        galleryImageId: imageDefinition.id
        runOutputName: 'output-win2022-base'
        replicationRegions: replicationRegions
        storageAccountType: 'Standard_LRS'
        excludeFromLatest: false
      }
    ]
  }
}

output imageTemplateId string = imageTemplate.id
output imageTemplateName string = imageTemplate.name
