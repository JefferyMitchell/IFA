#Requires -RunAsAdministrator
<#
  install-citrix-vda.ps1
  Installs the Citrix Virtual Delivery Agent (VDA) from a pre-staged installer.
  The AIB File customizer stages VDAServerSetup.exe to C:\Windows\Temp\ before
  this script runs — no download logic required here.

  Flags used:
    /mastermcsimage  — MCS-specific optimisations (disables write cache persistence,
                       configures identity disk handling). Required for MCS catalogs.
    /masterimage     — Marks as a master/template image. Suppresses machine-specific config.
    /components VDA  — Installs VDA component only. Excludes StoreFront, Director, etc.
    /noreboot        — AIB controls all restarts via WindowsRestart customizer steps.
    /enable_hdx_ports — Opens Windows Firewall rules for HDX (TCP 1494, 2598, UDP 16500-16509).
    /enable_remote_assistance — Enables Remote Assistance for Citrix Director shadowing.
    /includeadditional — Citrix UPM for profile management across sessions.
    /exclude         — Removes components not needed in a VDI image (WEM, telemetry, App-V).

  Do NOT specify /controllers or /xendesktopcloud.
  MCS injects Cloud Connector registration at catalog provisioning time.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step { param([string]$Message) Write-Output "`n[$(Get-Date -Format 'HH:mm:ss')] $Message" }

$InstallerPath = 'C:\Windows\Temp\VDAServerSetup.exe'
$LogPath       = 'C:\Windows\Temp\VDAInstall.log'

Write-Step "Verifying VDA installer is staged..."
if (-not (Test-Path $InstallerPath)) {
  throw "VDA installer not found at $InstallerPath. Ensure the AIB File customizer step ran successfully."
}

$fileInfo = Get-Item $InstallerPath
Write-Output "  File : $($fileInfo.Name)"
Write-Output "  Size : $([math]::Round($fileInfo.Length / 1MB, 1)) MB"

Write-Step "Installing Citrix Virtual Delivery Agent..."
$installArgs = (
  '/quiet',
  '/noreboot',
  '/masterimage',
  '/mastermcsimage',
  '/enable_hdx_ports',
  '/enable_remote_assistance',
  '/components VDA',
  '/includeadditional "Citrix User Profile Manager","Citrix User Profile Manager WMI Plugin"',
  '/exclude "Citrix WEM Agent","Citrix Telemetry Service","Citrix Personalization for App-V - VDA"',
  "/logpath `"$LogPath`""
) -join ' '

$process = Start-Process `
  -FilePath $InstallerPath `
  -ArgumentList $installArgs `
  -Wait `
  -PassThru `
  -NoNewWindow

Write-Output "  Exit code: $($process.ExitCode)"

# 0 = success, 3 = success with reboot pending (expected with /noreboot)
if ($process.ExitCode -notin @(0, 3)) {
  Write-Output "`nLast 50 lines of install log:"
  Get-Content $LogPath -Tail 50 -ErrorAction SilentlyContinue | Write-Output
  throw "VDA installation failed with exit code $($process.ExitCode). See log: $LogPath"
}

Write-Step "Cleaning up installer..."
Remove-Item -Path $InstallerPath -Force

Write-Step "Citrix VDA installation complete. AIB will restart the VM before the next step."
