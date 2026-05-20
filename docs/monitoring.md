---
layout: default
title: Monitoring
parent: Management
nav_order: 2
---

# Monitoring
{: .no_toc }

Native Azure tools for observing image build activity, detecting failures, and tracking image version history.

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Enable Diagnostic Logging

By default, AIB build logs stay inside the temporary staging resource group AIB creates per build. Enabling diagnostic settings sends structured logs to a Log Analytics workspace so they persist, are queryable, and can drive alerts and dashboards.

Deploy with monitoring enabled by adding two parameters to your `main.bicep` deployment:

```bash
az deployment group create \
  --resource-group rg-image-factory \
  --template-file infra/bicep/main.bicep \
  --parameters \
    storageAccountName=staimagefactory \
    enableMonitoring=true \
    alertEmailAddress=ops@yourorg.com
```

This deploys:
- A Log Analytics workspace (`law-image-factory`)
- An Azure Monitor alert rule that fires on build failure
- An Azure Monitor Workbook pre-loaded with build dashboards

Then pass the workspace ID to `image-template.bicep` so AIB logs stream directly to it:

```bash
WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group rg-image-factory \
  --workspace-name law-image-factory \
  --query id -o tsv)

az deployment group create \
  --resource-group rg-image-factory \
  --template-file infra/bicep/image-template.bicep \
  --parameters \
    storageAccountName=staimagefactory \
    logAnalyticsWorkspaceId=$WORKSPACE_ID
```

---

## Azure Monitor Workbook

The factory deploys a pre-built Workbook that visualises build activity without any manual configuration.

**Open it:** Azure Portal → **Monitor** → **Workbooks** → **Image Factory — Build Dashboard**

![Azure Monitor Workbook showing build history tiles, success/fail trend chart, recent builds table, and template deployment history]

The Workbook contains five panels:

| Panel | What It Shows |
|---|---|
| **Build Summary tiles** | Succeeded / Failed / Canceled counts for the last 30 days |
| **Success Rate chart** | Weekly succeeded vs. failed builds over 90 days — shows drift in reliability over time |
| **Recent Builds table** | Last 25 builds with timestamp, status icon, template name, and who triggered it |
| **Template Deployments** | When image templates were updated via Bicep — correlate config changes with build outcomes |
| **Marketplace Source Image Status** | Available versions of `2022-datacenter-azure-edition` in your region, plus when the factory last ran — lets you see at a glance whether a newer patch level is available |

The Workbook reads from Azure Activity Log, which captures all AIB operations with no additional configuration. Once diagnostic settings are enabled, richer per-step build data becomes available in the same workspace.

### Marketplace Status Panel — Setup

The Marketplace Status panel calls the Azure Compute API directly and requires two parameters entered at the top of the Workbook:

| Parameter | What to enter |
|---|---|
| **Subscription ID** | Your Azure subscription GUID (`az account show --query id -o tsv`) |
| **Region** | The Azure region where your image templates run (e.g. `eastus`) |

**Reading the version table:** Marketplace version numbers follow the pattern `build.revision.YYMMDD` — the last six digits encode the publication date. `20348.2762.240416` was published 16 April 2024. Compare the newest version against the **Last Successful Build** tile to determine whether a newer patch level exists. If it does, trigger a manual build or wait for the next scheduled run — the template uses `version: latest`, so it always pulls the newest marketplace image at build time.

---

## Azure Monitor Alerts

The monitoring deployment creates one alert rule out of the box:

**Image Factory — Build Failed**
- Fires within 5 minutes of a Failed or Canceled build run
- Sends email to the address provided at deployment time
- Severity 2 (Warning)

To add additional recipients or connect to Teams or PagerDuty, edit the action group `ag-image-factory-alerts` in the portal under **Monitor → Alerts → Action groups**.

### Add a Build Timeout Alert

Builds that run close to the `buildTimeoutMinutes` limit often indicate Windows Update is taking longer than expected. Create a second alert to catch this pattern:

```bash
az monitor scheduled-query create \
  --resource-group rg-image-factory \
  --name "alert-image-factory-slow-build" \
  --scopes $(az monitor log-analytics workspace show \
    --resource-group rg-image-factory \
    --workspace-name law-image-factory \
    --query id -o tsv) \
  --condition-query \
    "AzureActivity
     | where ResourceProviderValue =~ 'Microsoft.VirtualMachineImages'
     | where OperationNameValue =~ 'Microsoft.VirtualMachineImages/imageTemplates/run/action'
     | where ActivityStatusValue == 'Succeeded'
     | extend DurationMinutes = datetime_diff('minute', TimeGenerated, todatetime(Properties))
     | where DurationMinutes > 100" \
  --condition-time-aggregation Count \
  --condition-operator GreaterThan \
  --condition-threshold 0 \
  --evaluation-frequency PT5M \
  --window-size PT10M \
  --severity 3 \
  --description "Build succeeded but took over 100 minutes — consider increasing buildTimeoutMinutes"
```

---

## Useful KQL Queries

Run these in **Monitor → Logs** against your Log Analytics workspace.

### Last 10 builds with status

```kql
AzureActivity
| where ResourceProviderValue =~ 'Microsoft.VirtualMachineImages'
| where OperationNameValue =~ 'Microsoft.VirtualMachineImages/imageTemplates/run/action'
| project Time = TimeGenerated, Status = ActivityStatusValue, Template = tostring(split(ResourceId, '/')[-1]), TriggeredBy = Caller
| order by Time desc
| take 10
```

### Build failure rate by week

```kql
AzureActivity
| where ResourceProviderValue =~ 'Microsoft.VirtualMachineImages'
| where OperationNameValue =~ 'Microsoft.VirtualMachineImages/imageTemplates/run/action'
| where TimeGenerated > ago(90d)
| summarize
    Total = count(),
    Failed = countif(ActivityStatusValue == 'Failed'),
    FailureRate = round(100.0 * countif(ActivityStatusValue == 'Failed') / count(), 1)
    by Week = bin(TimeGenerated, 7d)
| order by Week desc
```

### All operations on image templates today

```kql
AzureActivity
| where ResourceProviderValue =~ 'Microsoft.VirtualMachineImages'
| where TimeGenerated > ago(24h)
| project Time = TimeGenerated, Operation = OperationNameValue, Status = ActivityStatusValue, Resource = tostring(split(ResourceId, '/')[-1])
| order by Time desc
```

---

## Event Grid — Reactive Automation

Event Grid lets you react to AIB build outcomes automatically rather than polling. Two useful patterns:

### Pattern 1 — Notify on Build Completion

AIB publishes events to Event Grid when a build succeeds or fails. Subscribe to these events to trigger a Teams message, open a ticket, or kick off a downstream pipeline without polling.

**Event types:**
- `Microsoft.VirtualMachineImages.ImageTemplateRunSucceeded`
- `Microsoft.VirtualMachineImages.ImageTemplateRunFailed`

Create a system topic on the image template resource and subscribe your endpoint:

```bash
# Create a system topic for the image template
az eventgrid system-topic create \
  --resource-group rg-image-factory \
  --name evgt-image-factory \
  --source $(az image builder show \
    --resource-group rg-image-factory \
    --name tmpl-win2022-base \
    --query id -o tsv) \
  --topic-type Microsoft.VirtualMachineImages.ImageTemplates \
  --location eastus

# Subscribe — replace the endpoint with your webhook, Logic App, or Function URL
az eventgrid system-topic event-subscription create \
  --resource-group rg-image-factory \
  --system-topic-name evgt-image-factory \
  --name sub-build-notifications \
  --endpoint https://your-receiver-endpoint \
  --included-event-types \
    Microsoft.VirtualMachineImages.ImageTemplateRunSucceeded \
    Microsoft.VirtualMachineImages.ImageTemplateRunFailed
```

### Pattern 2 — Trigger a Build When a New Marketplace Image Is Published

Microsoft publishes events to Azure Event Grid when new platform images become available in the Marketplace. Subscribing to these events lets you automatically trigger a factory build the moment a new Windows Server 2022 patch level is available — without waiting for your scheduled cron.

**Architecture:**

```
Microsoft Marketplace
  publishes new image version
        │
        ▼
Event Grid (Azure subscription system topic)
  event type: Microsoft.Compute.Gallery.ImageVersionCreated
        │
        ▼
Azure Logic App or Function
  receives webhook, calls GitHub REST API
        │
        ▼
GitHub Actions — repository_dispatch event
  triggers build-image.yml
        │
        ▼
AIB picks up latest marketplace version
  (source.version = 'latest' in image-template.bicep)
```

> **When is this worth it?** For most teams the cron schedule is sufficient — `version: 'latest'` in the template always pulls the newest marketplace image at build time. Event Grid for marketplace triggers adds complexity and is best suited for teams with strict patch SLAs (e.g. 48-hour time-to-patch requirements) where waiting for the weekly cron is too slow.

---

## Azure Dashboard (Quick Reference)

For a lightweight status view without a full Workbook, pin the following to an Azure Dashboard:

1. Open the image template in the portal → **Overview** → pin **Last run status** to your dashboard
2. Open the gallery → pin **Image versions** count
3. Open the storage account → pin **Blob count** (confirms scripts are present)

The dashboard gives an at-a-glance health check accessible to anyone with Reader on the resource group.
