targetScope = 'resourceGroup'

@description('Azure region. Must match the region used for main.bicep.')
param location string = resourceGroup().location

@description('Name prefix for the AIB image template. AVM appends a timestamp, making each deployment a distinct resource.')
param templateName string = 'tmpl-win2022-citrix-vda'

@description('Name of the existing user-assigned managed identity (deployed by main.bicep)')
param identityName string = 'uami-aib'

@description('Name of the existing Azure Compute Gallery (deployed by main.bicep)')
param galleryName string = 'acg_golden_images'

@description('Name of the Citrix VDA image definition (deployed by citrix-image-definition.bicep)')
param imageDefinitionName string = 'win2022-citrix-vda'

@description('Name of the existing storage account holding build scripts and Citrix installers')
param storageAccountName string

@description('Regions to replicate the finished image version to')
param replicationRegions array = ['eastus', 'westus2', 'westeurope']

@description('Build VM size — D4s_v3 recommended as VDA install and optimizer are memory-intensive')
param buildVmSize string = 'Standard_D4s_v3'

@description('Maximum build time in minutes. VDA + optimizer + Windows Update needs more headroom.')
param buildTimeoutMinutes int = 180

// ── Reference existing resources ──────────────────────────────────────────────
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
module imageTemplate 'br/public:avm/res/virtual-machine-images/image-template:0.6.1' = {
  name: 'deploy-image-template-citrix'
  params: {
    name: templateName
    location: location
    buildTimeoutInMinutes: buildTimeoutMinutes
    vmSize: buildVmSize
    osDiskSizeGB: 128
    managedIdentities: {
      userAssignedResourceIds: [identity.id]
    }
    imageSource: {
      type: 'PlatformImage'
      publisher: 'MicrosoftWindowsServer'
      offer: 'WindowsServer'
      sku: '2022-datacenter-azure-edition'
      version: 'latest'
    }
    customizationSteps: [
      // Stage binaries into the build VM first using the File customizer.
      // AIB authenticates to storage via the managed identity — no SAS token needed.
      {
        type: 'File'
        name: 'StageVDAInstaller'
        sourceUri: 'https://${storageAccountName}.blob.${environment().suffixes.storage}/scripts/VDAServerSetup.exe'
        destination: 'C:\\Windows\\Temp\\VDAServerSetup.exe'
      }
      {
        type: 'File'
        name: 'StageCitrixOptimizer'
        sourceUri: 'https://${storageAccountName}.blob.${environment().suffixes.storage}/scripts/CitrixOptimizer.zip'
        destination: 'C:\\Windows\\Temp\\CitrixOptimizer.zip'
      }
      // Install agents before VDA to ensure monitoring is in place from first boot
      {
        type: 'PowerShell'
        name: 'InstallAgents'
        scriptUri: 'https://${storageAccountName}.blob.${environment().suffixes.storage}/scripts/install-agents.ps1'
        runElevated: true
      }
      // Install Citrix VDA with MCS optimisation flags
      {
        type: 'PowerShell'
        name: 'InstallCitrixVDA'
        scriptUri: 'https://${storageAccountName}.blob.${environment().suffixes.storage}/scripts/install-citrix-vda.ps1'
        runElevated: true
      }
      // VDA installation requires a restart before optimizer can run
      {
        type: 'WindowsRestart'
        restartTimeout: '15m'
      }
      // Citrix Optimizer reduces OS noise and improves VDI density
      {
        type: 'PowerShell'
        name: 'RunCitrixOptimizer'
        scriptUri: 'https://${storageAccountName}.blob.${environment().suffixes.storage}/scripts/run-citrix-optimizer.ps1'
        runElevated: true
      }
      // Hardening runs after VDA so it can account for VDA-specific services
      {
        type: 'PowerShell'
        name: 'ApplyHardening'
        scriptUri: 'https://${storageAccountName}.blob.${environment().suffixes.storage}/scripts/harden-windows.ps1'
        runElevated: true
      }
      {
        type: 'WindowsUpdate'
      }
      {
        type: 'WindowsRestart'
        restartTimeout: '10m'
      }
      // Re-apply hardening after Windows Update — patching can reset service startup types
      {
        type: 'PowerShell'
        name: 'ReApplyHardening'
        scriptUri: 'https://${storageAccountName}.blob.${environment().suffixes.storage}/scripts/harden-windows.ps1'
        runElevated: true
      }
      // Validate VDA is intact after patching before distributing
      {
        type: 'PowerShell'
        name: 'PostBuildValidation'
        inline: [
          'Write-Output "Validating Citrix VDA installation..."'
          '$broker = Get-Service -Name "BrokerAgent" -ErrorAction SilentlyContinue'
          'if (-not $broker) { throw "BrokerAgent service not found — VDA installation failed or did not survive Windows Update" }'
          '$picaSvc = Get-Service -Name "picaSvc2" -ErrorAction SilentlyContinue'
          'if (-not $picaSvc) { throw "picaSvc2 not found — VDA HDX stack is incomplete" }'
          'Write-Output "Citrix VDA validation passed — image ready for MCS distribution"'
        ]
        runElevated: true
      }
    ]
    distributions: [
      {
        type: 'SharedImage'
        sharedImageGalleryImageDefinitionResourceId: imageDefinition.id
        runOutputName: 'output-win2022-citrix-vda'
        replicationRegions: replicationRegions
        storageAccountType: 'Standard_LRS'
        excludeFromLatest: false
      }
    ]
  }
}

output imageTemplateId string = imageTemplate.outputs.resourceId
output imageTemplateName string = imageTemplate.outputs.name
