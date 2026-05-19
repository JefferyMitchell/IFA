---
layout: default
title: Setup
nav_order: 3
---

# Setup
{: .no_toc }

This guide walks through the prerequisites and initial deployment of the Azure Image Factory infrastructure.

![ High-level setup flow: you run commands in Cloud Shell, Azure Image Builder builds and customises the golden image, Compute Gallery stores and replicates it, and VMs deploy from the gallery](<pics/build the enviorment.png>)

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Prerequisites

### Azure Subscription

You need an active Azure subscription with sufficient quota for:

- **Standard_D2s_v3** (or equivalent) — used as the temporary build VM during image creation
- **Managed Disks** — used to store image snapshots during build

### Required Permissions

The user or service principal deploying the factory needs the following roles:

| Scope | Role |
|---|---|
| Subscription | `Contributor` (for resource group and resource creation) |
| Subscription | `User Access Administrator` (to assign roles to the managed identity) |

### Register Resource Providers

Azure Image Builder uses resource providers that may not be registered by default. Run the following in Azure CLI:

```bash
az provider register --namespace Microsoft.VirtualMachineImages
az provider register --namespace Microsoft.Compute
az provider register --namespace Microsoft.KeyVault
az provider register --namespace Microsoft.Storage
az provider register --namespace Microsoft.Network
```

Verify registration status:

```bash
az provider show --namespace Microsoft.VirtualMachineImages --query registrationState
```

Wait until the output returns `Registered` before proceeding.

### Tools

Install the following locally or use Azure Cloud Shell:

| Tool | Version | Purpose |
|---|---|---|
| [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) | 2.50+ | Deploying infrastructure and managing resources |
| [Bicep CLI](https://learn.microsoft.com/azure/azure-resource-manager/bicep/install) | Latest | Compiling and deploying Bicep templates |
| [Git](https://git-scm.com/) | Any | Cloning this repository |

---

## Deployment Steps

The following diagram maps each step you run to the Azure resources it creates:

![ Step-by-step deployment map: Prerequisites through Step 5, showing each action on the left and the Azure resources created on the right — from resource group and managed identity through to a verified test VM](<pics/drive from cloud shell.png>)

### 1. Clone the Repository

```bash
git clone https://github.com/<your-org>/azure-image-factory.git
cd azure-image-factory
```

### 2. Create a Resource Group

```bash
az group create \
  --name rg-image-factory \
  --location eastus
```

> **Tip:** Choose a region that supports Azure Image Builder. Check the [supported regions list](https://learn.microsoft.com/azure/virtual-machines/image-builder-overview#regions) before proceeding.

### 3. Deploy the Infrastructure

Deploy all factory components using the main Bicep orchestration template:

```bash
az deployment group create \
  --resource-group rg-image-factory \
  --template-file infra/bicep/main.bicep \
  --parameters \
      location=eastus \
      galleryName=acg_image_factory \
      storageAccountName=staimagefactory
```

This deploys:

- A **User-Assigned Managed Identity** with the required role assignments
- An **Azure Compute Gallery** with initial image definitions
- A **Storage Account** for build scripts and artifacts
- An **Azure Image Builder image template** (in a disabled/draft state)

### 4. Upload Customization Scripts

Upload the build scripts to the storage account created in the previous step:

```bash
az storage blob upload-batch \
  --account-name staimagefactory \
  --destination scripts \
  --source ./scripts
```

### 5. Configure GitHub Actions

To enable the automated pipeline, add the following secrets to your GitHub repository:

| Secret | Value |
|---|---|
| `AZURE_CLIENT_ID` | App registration client ID |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target subscription ID |
| `AZURE_RESOURCE_GROUP` | `rg-image-factory` |

Configure OIDC federated credentials on the app registration so GitHub Actions can authenticate without storing a client secret. See [GitHub's guide on Azure OIDC](https://docs.github.com/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-azure).

---

## Verify the Deployment

After deployment, confirm the core resources exist:

```bash
az resource list \
  --resource-group rg-image-factory \
  --output table
```

You should see resources of the following types:

- `Microsoft.ManagedIdentity/userAssignedIdentities`
- `Microsoft.Compute/galleries`
- `Microsoft.Storage/storageAccounts`
- `Microsoft.VirtualMachineImages/imageTemplates`

---

## Next Steps

With the factory infrastructure deployed, proceed to [Configuration](./configuration) to define your image templates and customization steps.
