#Requires -RunAsAdministrator
<#
  harden-windows.ps1
  Applies a Windows Server security baseline during the AIB build.
  Targets CIS Microsoft Windows Server 2022 Benchmark (Level 1) controls
  that are safe to bake into a generalized image.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step { param([string]$Message) Write-Output "`n[$(Get-Date -Format 'HH:mm:ss')] $Message" }

# ── Disable legacy protocols and features ─────────────────────────────────────
Write-Step "Disabling SMBv1..."
Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force

Write-Step "Disabling NetBIOS over TCP/IP on all adapters..."
Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.TcpipNetbiosOptions -ne $null } | ForEach-Object {
  $_.SetTcpipNetbios(2) | Out-Null  # 2 = Disable NetBIOS
}

Write-Step "Disabling LLMNR..."
$llmnrPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'
if (-not (Test-Path $llmnrPath)) { New-Item -Path $llmnrPath -Force | Out-Null }
Set-ItemProperty -Path $llmnrPath -Name EnableMulticast -Value 0

Write-Step "Disabling WDigest credential caching..."
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' -Name UseLogonCredential -Value 0

# ── Services ──────────────────────────────────────────────────────────────────
Write-Step "Disabling unnecessary services..."
$servicesToDisable = @(
  'RemoteRegistry',   # Remote Registry — attack surface for lateral movement
  'Spooler',          # Print Spooler — PrintNightmare mitigation (disable if not a print server)
  'XblGameSave',      # Xbox services
  'XboxNetApiSvc',
  'XblAuthManager'
)

foreach ($svc in $servicesToDisable) {
  if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
    Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
    Set-Service -Name $svc -StartupType Disabled
    Write-Output "  Disabled: $svc"
  }
}

# ── Windows Firewall ──────────────────────────────────────────────────────────
Write-Step "Enabling Windows Firewall on all profiles..."
Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled True

# ── Registry hardening ────────────────────────────────────────────────────────
Write-Step "Applying registry hardening settings..."

$registrySettings = @(
  # Disable autorun / autoplay
  @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name = 'NoDriveTypeAutoRun'; Value = 255 },
  @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name = 'NoAutorun';           Value = 1 },

  # Restrict anonymous access
  @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; Name = 'RestrictAnonymous';     Value = 1 },
  @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; Name = 'RestrictAnonymousSAM';  Value = 1 },

  # Enforce NTLMv2
  @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; Name = 'LmCompatibilityLevel'; Value = 5 },

  # Disable sending LM and NTLM hashes
  @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; Name = 'NoLMHash'; Value = 1 },

  # Screen lock after 15 minutes
  @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'InactivityTimeoutSecs'; Value = 900 },

  # Disable guest account logon
  @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'EnableGuestAccount'; Value = 0 },

  # Require Ctrl+Alt+Del for interactive logon
  @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'; Name = 'DisableCAD'; Value = 0 }
)

foreach ($setting in $registrySettings) {
  if (-not (Test-Path $setting.Path)) { New-Item -Path $setting.Path -Force | Out-Null }
  Set-ItemProperty -Path $setting.Path -Name $setting.Name -Value $setting.Value -Type DWord
  Write-Output "  Set: $($setting.Path)\$($setting.Name) = $($setting.Value)"
}

# ── Audit policy ──────────────────────────────────────────────────────────────
Write-Step "Configuring audit policies..."
$auditCategories = @(
  'Logon',
  'Logoff',
  'Account Logon',
  'Account Management',
  'Policy Change',
  'Privilege Use',
  'System'
)
foreach ($category in $auditCategories) {
  auditpol /set /category:"$category" /success:enable /failure:enable | Out-Null
}

# ── Windows Defender ──────────────────────────────────────────────────────────
Write-Step "Configuring Windows Defender..."
Set-MpPreference -DisableRealtimeMonitoring $false
Set-MpPreference -MAPSReporting Advanced
Set-MpPreference -SubmitSamplesConsent SendAllSamples

# ── Final validation ──────────────────────────────────────────────────────────
Write-Step "Running post-hardening validation..."

$smb1 = (Get-SmbServerConfiguration).EnableSMB1Protocol
if ($smb1) { throw "SMBv1 is still enabled — hardening failed" }

$remoteReg = (Get-Service -Name RemoteRegistry).StartType
if ($remoteReg -ne 'Disabled') { throw "RemoteRegistry is not disabled — hardening failed" }

Write-Step "Hardening complete — all checks passed."
