#Requires -RunAsAdministrator
<#
  install-agents.ps1
  Installs monitoring and management agents during the AIB build.
  Agents installed here are baked into every image version produced by the factory.

  Note: Azure Monitor Agent (AMA) is typically installed as a VM extension
  post-deployment rather than baked into the image. This script installs
  any agents that must be present before first boot (e.g., Qualys, custom tooling).
  Add or remove agent blocks below to match your organisation's requirements.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step { param([string]$Message) Write-Output "`n[$(Get-Date -Format 'HH:mm:ss')] $Message" }

function Install-FromWeb {
  param(
    [string]$Url,
    [string]$Destination,
    [string]$Arguments
  )
  Write-Output "  Downloading: $Url"
  Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
  Write-Output "  Installing..."
  Start-Process -FilePath $Destination -ArgumentList $Arguments -Wait -NoNewWindow
  Remove-Item -Path $Destination -Force
}

# ── Azure Connected Machine Agent (Arc) ───────────────────────────────────────
# Install only if this image will be used outside of Azure (hybrid/Arc scenarios).
# Comment out if images are Azure-only.
#
# Write-Step "Installing Azure Connected Machine Agent..."
# Install-FromWeb `
#   -Url "https://aka.ms/AzureConnectedMachineAgent" `
#   -Destination "$env:TEMP\AzureConnectedMachineAgent.msi" `
#   -Arguments "/i $env:TEMP\AzureConnectedMachineAgent.msi /qn /l*v $env:TEMP\arc-install.log"

# ── Azure Monitor Agent (AMA) ─────────────────────────────────────────────────
# AMA is best deployed as a VM extension via policy or Bicep post-deployment.
# If your workload requires AMA to be present before the extension framework
# is available, uncomment and adapt the block below.
#
# Write-Step "Installing Azure Monitor Agent..."
# $amaUrl = "https://aka.ms/installazuremonitorwindowsagent"
# Install-FromWeb -Url $amaUrl -Destination "$env:TEMP\AMASetup.msi" -Arguments "/i $env:TEMP\AMASetup.msi /qn"

# ── Custom tooling placeholder ─────────────────────────────────────────────────
# Add your organisation-specific agent installations here.
# Example pattern:
#
# Write-Step "Installing Qualys Cloud Agent..."
# Install-FromWeb `
#   -Url "https://your-internal-repo/qualys-agent.exe" `
#   -Destination "$env:TEMP\QualysAgent.exe" `
#   -Arguments "/s /e"

# ── Verify .NET runtime (required by many agents) ─────────────────────────────
Write-Step "Checking .NET runtime..."
$dotnetVersion = [System.Runtime.InteropServices.RuntimeEnvironment]::GetSystemVersion()
Write-Output "  .NET version: $dotnetVersion"

# ── Configure Windows Update client settings ──────────────────────────────────
# Ensures the image does not point to a stale WSUS server from the source image.
Write-Step "Resetting Windows Update client configuration..."
$wuPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
if (Test-Path $wuPath) {
  Remove-Item -Path $wuPath -Recurse -Force
  Write-Output "  Cleared stale Windows Update policy keys"
}

Write-Step "Agent installation complete."
