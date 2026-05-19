# Azure Image Factory

A reference solution for building an automated VM image creation pipeline using **Azure Image Builder (AIB)** and **Azure Compute Gallery (ACG)**. This repo contains both the documentation and the deployable infrastructure code.

## What This Does

Provides an end-to-end factory that:

- Builds hardened, customized VM images from a source (Marketplace or existing gallery image)
- Applies customization steps — scripts, Windows Update, agent installation, CIS hardening
- Publishes versioned images to Azure Compute Gallery
- Replicates images across regions for consumption by VMs, VMSS, AVD, and AKS

## Repository Structure

```
├── docs/                        # Architecture and concept documentation
│   └── azure-image-factory.md   # Factory overview, design decisions, patterns
│
├── infra/                       # Deployable infrastructure code
│   └── bicep/                   # Bicep templates for AIB, ACG, identities, storage
│
├── scripts/                     # Customization scripts run inside the image build
│
└── .github/
    └── workflows/               # CI/CD pipeline definitions (image build automation)
```

## Getting Started

> Prerequisites and deployment steps will be added as the solution is built out.

## Documentation

- [Azure Image Factory — Overview](docs/azure-image-factory.md)

## Related Azure Services

- [Azure Image Builder](https://learn.microsoft.com/azure/virtual-machines/image-builder-overview)
- [Azure Compute Gallery](https://learn.microsoft.com/azure/virtual-machines/azure-compute-gallery)
