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
├── docs/                        # GitHub Pages documentation (Just the Docs)
│   ├── index.md                 # Home / landing page
│   ├── architecture.md          # Component overview and design decisions
│   ├── setup.md                 # Prerequisites and deployment steps
│   ├── configuration.md         # Image definitions, templates, customization
│   ├── management.md            # Day-to-day operations and troubleshooting
│   ├── citrix-daas.md           # Citrix DaaS MCS extension guide
│   └── pics/                    # Architecture diagrams
│
├── infra/
│   └── bicep/
│       ├── main.bicep                       # Infrastructure (identity, storage, gallery)
│       ├── image-template.bicep             # Base hardened image template
│       ├── image-template-citrix.bicep      # Citrix VDA image template
│       ├── citrix-image-definition.bicep    # Citrix gallery image definition
│       └── modules/                         # Reusable Bicep modules
│
├── scripts/
│   ├── setup/                   # Bash scripts for Cloud Shell deployment (run in order)
│   │   ├── 00-prerequisites.sh
│   │   ├── 01-deploy.sh
│   │   ├── 02-upload-scripts.sh
│   │   ├── 03-deploy-template.sh
│   │   ├── 04-verify.sh
│   │   └── citrix/              # Citrix-specific setup scripts
│   └── customization/           # PowerShell scripts run inside the image build
│
└── .github/
    └── workflows/               # CI/CD pipeline definitions (image build automation)
```

## Getting Started

**Documentation site:** https://jefferymitchell.github.io/AIB

For full setup instructions, see the [Setup guide](https://jefferymitchell.github.io/AIB/setup).

All deployment scripts are designed to run from **Azure Cloud Shell (Bash)**. Clone the repo to your Cloud Shell storage and run the scripts in order from `scripts/setup/`.

## Related Azure Services

- [Azure Image Builder](https://learn.microsoft.com/azure/virtual-machines/image-builder-overview)
- [Azure Compute Gallery](https://learn.microsoft.com/azure/virtual-machines/azure-compute-gallery)
