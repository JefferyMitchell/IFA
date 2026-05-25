@description('Azure region')
param location string

@description('Name of the Azure Compute Gallery')
param galleryName string

@description('Name of the Windows Server 2022 image definition')
param imageDefinitionName string = 'win2022-base'

module gallery 'br/public:avm/res/compute/gallery:0.9.5' = {
  name: 'gallery'
  params: {
    name: galleryName
    location: location
    images: [
      {
        name: imageDefinitionName
        osType: 'Windows'
        osState: 'Generalized'
        hyperVGeneration: 'V2'
        architecture: 'x64'
        identifier: {
          publisher: 'MyOrg'
          offer: 'WindowsServer'
          sku: '2022-hardened'
        }
        vCPUs: { min: 2, max: 8 }
        memory: { min: 4, max: 32 }
      }
    ]
  }
}

output galleryId string = gallery.outputs.resourceId
output galleryName string = gallery.outputs.name
output imageDefinitionId string = gallery.outputs.imageResourceIds[0]
output imageDefinitionName string = imageDefinitionName
