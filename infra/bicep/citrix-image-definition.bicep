targetScope = 'resourceGroup'

@description('Azure region. Must match the region used for main.bicep.')
param location string = resourceGroup().location

@description('Name of the existing Azure Compute Gallery (deployed by main.bicep)')
param galleryName string = 'acg_golden_images'

@description('Name of the Citrix VDA image definition')
param imageDefinitionName string = 'win2022-citrix-vda'

resource gallery 'Microsoft.Compute/galleries@2022-03-03' existing = {
  name: galleryName
}

resource citrixImageDefinition 'Microsoft.Compute/galleries/images@2022-03-03' = {
  parent: gallery
  name: imageDefinitionName
  location: location
  properties: {
    osType: 'Windows'
    osState: 'Generalized'
    hyperVGeneration: 'V2'
    architecture: 'x64'
    identifier: {
      publisher: 'MyOrg'
      offer: 'CitrixVDA'
      sku: 'win2022-vda'
    }
    recommended: {
      vCPUs: { min: 2, max: 16 }
      memory: { min: 4, max: 64 }
    }
  }
}

output imageDefinitionId string = citrixImageDefinition.id
output imageDefinitionName string = citrixImageDefinition.name
