@description('Azure region')
param location string

@description('Resource ID of the Log Analytics workspace')
param workspaceId string

@description('Email address to notify on build failure')
param alertEmailAddress string

@description('Name prefix for monitoring resources')
param namePrefix string = 'image-factory'

// ── Action Group ──────────────────────────────────────────────────────────────
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-${namePrefix}-alerts'
  location: 'global'
  properties: {
    groupShortName: 'AIBAlerts'
    enabled: true
    emailReceivers: [
      {
        name: 'BuildFailureEmail'
        emailAddress: alertEmailAddress
        useCommonAlertSchema: true
      }
    ]
  }
}

// ── Alert Rule — Build Failure ────────────────────────────────────────────────
// Fires when an AIB image template run ends in a Failed or Canceled state.
resource buildFailureAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-${namePrefix}-build-failure'
  location: location
  properties: {
    displayName: 'Image Factory — Build Failed'
    description: 'Fires when an AIB image template run ends in a Failed or Canceled state.'
    enabled: true
    severity: 2
    evaluationFrequency: 'PT5M'
    windowSize: 'PT10M'
    scopes: [workspaceId]
    criteria: {
      allOf: [
        {
          query: '''
            AzureActivity
            | where ResourceProviderValue =~ "Microsoft.VirtualMachineImages"
            | where OperationNameValue =~ "Microsoft.VirtualMachineImages/imageTemplates/run/action"
            | where ActivityStatusValue in ("Failed", "Canceled")
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroup.id]
    }
  }
}

// ── Azure Monitor Workbook ────────────────────────────────────────────────────
resource workbook 'Microsoft.Insights/workbooks@2022-04-01' = {
  name: guid(resourceGroup().id, '${namePrefix}-workbook')
  location: location
  kind: 'shared'
  properties: {
    displayName: 'Image Factory — Build Dashboard'
    category: 'workbook'
    sourceId: workspaceId
    serializedData: string(loadJsonContent('../workbooks/image-factory.json'))
  }
}

output actionGroupId string = actionGroup.id
output alertRuleId string = buildFailureAlert.id
output workbookId string = workbook.id
