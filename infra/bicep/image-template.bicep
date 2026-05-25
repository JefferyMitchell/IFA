targetScope = 'resourceGroup'

@description('Azure region. Must match the region used for main.bicep.')
param location string = resourceGroup().location

@description('Name prefix for the AIB image template. AVM appends a timestamp, making each deployment a distinct resource.')
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

@description('Resource ID of the Log Analytics workspace for diagnostic logs. Leave empty to skip diagnostics.')
param logAnalyticsWorkspaceId string = ''

// Passed through to the AVM module so both this file and the module agree on the final resource name,
// allowing the diagnostic settings scope to be resolved at deployment start (required by BCP120).
param baseTime string = utcNow('yyyy-MM-dd-HH-mm-ss')

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

// AVM appends baseTime to the name — mirror that here so diagnostics scope is known at start.
var templateFullName = '${templateName}-${baseTime}'

// ── AIB Image Template ────────────────────────────────────────────────────────
module imageTemplate 'br/public:avm/res/virtual-machine-images/image-template:0.6.1' = {
  name: 'avm-image-template'
  params: {
    name: templateName
    baseTime: baseTime
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
      {
        type: 'PowerShell'
        name: 'InstallAgents'
        scriptUri: 'https://${storageAccountName}.blob.${environment().suffixes.storage}/scripts/install-agents.ps1'
        runElevated: true
      }
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
      {
        type: 'PowerShell'
        name: 'ReApplyHardening'
        scriptUri: 'https://${storageAccountName}.blob.${environment().suffixes.storage}/scripts/harden-windows.ps1'
        runElevated: true
      }
      {
        type: 'PowerShell'
        name: 'PostPatchValidation'
        inline: [
          'Write-Output "Validating post-patch state..."'
          'if ((Get-Service -Name RemoteRegistry).StartType -ne "Disabled") { throw "RemoteRegistry not disabled" }'
          'Write-Output "Validation passed - image ready for distribution"'
        ]
        runElevated: true
      }
    ]
    distributions: [
      {
        type: 'SharedImage'
        sharedImageGalleryImageDefinitionResourceId: imageDefinition.id
        runOutputName: 'output-win2022-base'
        replicationRegions: replicationRegions
        storageAccountType: 'Standard_LRS'
        excludeFromLatest: false
      }
    ]
  }
}

// ── Diagnostic Settings (optional) ───────────────────────────────────────────
// AVM image-template does not expose diagnosticSettings; attach via a separate resource.
resource deployedTemplate 'Microsoft.VirtualMachineImages/imageTemplates@2024-02-01' existing = {
  #disable-next-line use-stable-resource-identifiers
  name: templateFullName
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  #disable-next-line use-stable-resource-identifiers
  name: 'diag-${templateFullName}'
  scope: deployedTemplate
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
}

output imageTemplateId string = imageTemplate.outputs.resourceId
output imageTemplateName string = templateFullName
