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

> **Tip:** The built-in `Owner` role covers both. On a dedicated factory subscription, assigning `Owner` is the simplest approach.

### Register Resource Providers

Azure Image Builder uses resource providers that may not be registered by default. Run the following in Azure CLI:

```bash
az provider register --namespace Microsoft.VirtualMachineImages --wait
az provider register --namespace Microsoft.Compute --wait
az provider register --namespace Microsoft.KeyVault --wait
az provider register --namespace Microsoft.Storage --wait
az provider register --namespace Microsoft.Network --wait
az provider register --namespace Microsoft.ContainerInstance --wait
```

> **Note:** First-time registration can take 5–15 minutes per provider, particularly `Microsoft.VirtualMachineImages`. The `--wait` flag blocks until each provider is fully registered before moving to the next. Subsequent runs are instant.

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

- **A User-Assigned Managed Identity** with the required role assignments
- **An Azure Compute Gallery** with initial image definitions
- **A Storage Account** for build scripts and artifacts
- **An Azure Image Builder image template** (in a disabled/draft state)

### 4. Upload Customization Scripts

Upload the build scripts to the storage account created in the previous step:

```bash
az storage blob upload-batch \
  --account-name staimagefactory \
  --destination scripts \
  --source ./scripts/customization \
  --auth-mode key
```

### 5. Configure GitHub Actions

GitHub Actions authenticates to Azure using OIDC — no client secret required. This requires an app registration in Entra ID with a federated credential, and three repository secrets.

#### Create the App Registration

In the Azure Portal, go to **Entra ID → App registrations → New registration**. Name it (e.g. `sp-image-factory-cicd`) and leave all other defaults. Note the **Application (client) ID** and **Directory (tenant) ID** — you will need them for the secrets below.

#### Add a Federated Credential

On the app registration, go to **Certificates & secrets → Federated credentials → Add credential**.

Set the fields exactly as follows:

| Field | Value |
|---|---|
| Federated credential scenario | GitHub Actions deploying Azure resources |
| Organization | Your GitHub username or org |
| Repository | Your repository name |
| Entity type | Branch |
| Branch | `main` |
| Audience | `api://AzureADTokenExchange` |

> **Critical:** The audience must be `api://AzureADTokenExchange`. This is the only value accepted by `azure/login`. Any other value (including `api://AzureADTokenV2`) will cause an authentication failure.

If your pipeline runs on multiple branches or uses environments, add a separate federated credential for each.

#### Assign the Required Role

The app registration needs **Owner** on the subscription (or the target resource group). Owner is required because the Bicep templates create role assignments for the managed identity — Contributor alone does not have `Microsoft.Authorization/roleAssignments/write`.

```bash
az role assignment create \
  --assignee <application-client-id> \
  --role Owner \
  --scope /subscriptions/<subscription-id>
```

#### Add GitHub Secrets

In your repository go to **Settings → Secrets and variables → Actions → New repository secret** and add:

| Secret | Value |
|---|---|
| `AZURE_CLIENT_ID` | Application (client) ID |
| `AZURE_TENANT_ID` | Directory (tenant) ID |
| `AZURE_SUBSCRIPTION_ID` | Target subscription ID |

#### Workflow Usage

In your workflow, authenticate using `azure/login@v2` with the three secrets. No `auth-type` parameter is needed — the action detects OIDC automatically when a client secret is absent:

```yaml
- uses: azure/login@v2
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

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
