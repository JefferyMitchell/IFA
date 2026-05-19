targetScope = 'resourceGroup'

@description('Azure region for all resources. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Name of the user-assigned managed identity used by AIB')
param identityName string = 'uami-aib'

@description('Name of the Azure Compute Gallery')
param galleryName string = 'acg_golden_images'

@description('Name of the Windows Server 2022 image definition in the gallery')
param imageDefinitionName string = 'win2022-base'

@minLength(3)
@maxLength(24)
@description('Storage account name for build scripts — must be globally unique, lowercase alphanumeric only')
param storageAccountName string

// ── Managed Identity ──────────────────────────────────────────────────────────
module identity 'modules/managed-identity.bicep' = {
  name: 'deploy-identity'
  params: {
    location: location
    identityName: identityName
  }
}

// ── Storage Account ───────────────────────────────────────────────────────────
module storage 'modules/storage-account.bicep' = {
  name: 'deploy-storage'
  params: {
    location: location
    storageAccountName: storageAccountName
    aibIdentityPrincipalId: identity.outputs.identityPrincipalId
  }
}

// ── Compute Gallery ───────────────────────────────────────────────────────────
module gallery 'modules/compute-gallery.bicep' = {
  name: 'deploy-gallery'
  params: {
    location: location
    galleryName: galleryName
    imageDefinitionName: imageDefinitionName
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────
output identityId string = identity.outputs.identityId
output identityPrincipalId string = identity.outputs.identityPrincipalId
output storageAccountName string = storage.outputs.storageAccountName
output galleryId string = gallery.outputs.galleryId
output imageDefinitionId string = gallery.outputs.imageDefinitionId
