# Infrastructure — Bicep Templates

Bicep templates for deploying the Image Factory for Azure infrastructure.

## Planned Templates

| Template | Purpose |
|---|---|
| `managed-identity.bicep` | User-assigned managed identity for AIB with role assignments |
| `compute-gallery.bicep` | Azure Compute Gallery, image definitions |
| `storage-account.bicep` | Storage account for build scripts and artifacts |
| `image-template.bicep` | AIB image template (parameterized per image type) |
| `main.bicep` | Orchestration template deploying all components |
