---
layout: default
title: Home
nav_order: 1
description: "Image Factory for Azure — automated, versioned VM image creation with Azure Image Builder and Azure Compute Gallery."
permalink: /
---

# Image Factory for Azure
{: .fs-9 }

An end-to-end reference solution for building, versioning, and distributing hardened VM images across your Azure environment.
{: .fs-6 .fw-300 }

[Get Started](./setup){: .btn .btn-primary .fs-5 .mb-4 .mb-md-0 .mr-2 }
[View on GitHub](https://github.com/JefferyMitchell/IFA){: .btn .fs-5 .mb-4 .mb-md-0 }

---

## What Is the Image Factory?

The Image Factory is an automated pipeline that uses **Azure Image Builder (AIB)** and **Azure Compute Gallery (ACG)** to:

- Build customized, hardened VM images from a known-good source
- Apply scripts, patches, and agents during the build process
- Publish versioned images to a central gallery
- Replicate images across Azure regions for consumption by workloads

Instead of manually configuring VMs or maintaining golden images by hand, the factory produces consistent, auditable images on a schedule or on demand.

---

## Who Is This For?

| Role | How You Use This |
|---|---|
| **Platform / Cloud Engineers** | Deploy and maintain the factory infrastructure |
| **Security Engineers** | Define hardening scripts and compliance baselines applied at build time |
| **DevOps / Automation Engineers** | Integrate factory pipelines into existing CI/CD workflows |
| **Application Teams** | Consume gallery images in VM, VMSS, or AKS deployments |

---

## How It Works

```
Trigger (schedule / PR / manual)
        │
        ▼
  CI/CD Pipeline (GitHub Actions)
        │
        ▼
  Azure Image Builder
  • Pulls source image (Marketplace or Gallery)
  • Runs customization scripts
  • Applies Windows Update / patching
  • Sysprepped and generalized
        │
        ▼
  Azure Compute Gallery
  • Versioned image stored and replicated
  • Consumed by VMs, VMSS, AKS, Citrix DaaS (MCS)
```

---

## Guide Contents

| Section | Description |
|---|---|
| [Architecture](./architecture) | Component overview, design decisions, and layering strategy |
| [Setup](./setup) | Prerequisites and initial deployment of the factory infrastructure |
| [Configuration](./configuration) | Defining images, customization steps, and gallery settings |
| [Management](./management) | Day-to-day operations, triggering builds, and troubleshooting |
| [Citrix DaaS (MCS)](./citrix-daas) | Extending the factory to produce Citrix VDA master images for MCS catalogs |

---

*This project is not affiliated with or endorsed by Microsoft. Azure Image Builder and Azure Compute Gallery are products of Microsoft Corporation.*
