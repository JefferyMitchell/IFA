@description('Azure region')
param location string

@description('Name of the Azure Compute Gallery')
param galleryName string

@description('Name of the Windows Server 2022 image definition')
param imageDefinitionName string = 'win2022-base'

resource gallery 'Microsoft.Compute/galleries@2022-03-03' = {
  name: galleryName
  location: location
  properties: {
    description: 'Azure Image Factory — golden image gallery'
  }
}

resource imageDefinition 'Microsoft.Compute/galleries/images@2022-03-03' = {
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
      offer: 'WindowsServer'
      sku: '2022-hardened'
    }
    recommended: {
      vCPUs: { min: 2, max: 8 }
      memory: { min: 4, max: 32 }
    }
  }
}

output galleryId string = gallery.id
output galleryName string = gallery.name
output imageDefinitionId string = imageDefinition.id
output imageDefinitionName string = imageDefinition.name
