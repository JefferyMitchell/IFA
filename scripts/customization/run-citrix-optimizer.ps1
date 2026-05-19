#Requires -RunAsAdministrator
<#
  run-citrix-optimizer.ps1
  Runs the Citrix Optimizer against a Windows Server 2022 template to reduce
  OS overhead, improve VDI density, and remove noise in multi-session scenarios.

  The AIB File customizer stages CitrixOptimizer.zip to C:\Windows\Temp\ before
  this script runs.

  Citrix Optimizer is available from:
  https://support.citrix.com/article/CTX224676

  The zip must contain:
    CitrixOptimizer.exe
    Templates\Citrix_Windows_Server_2022_2203.xml  (or equivalent for your VDA version)
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step { param([string]$Message) Write-Output "`n[$(Get-Date -Format 'HH:mm:ss')] $Message" }

$ZipPath       = 'C:\Windows\Temp\CitrixOptimizer.zip'
$ExtractPath   = 'C:\Windows\Temp\CitrixOptimizer'
$OptimizerExe  = "$ExtractPath\CitrixOptimizer.exe"
$ReportPath    = 'C:\Windows\Temp\CitrixOptimizer\optimization-report.html'

# Template filename — update if using a different VDA version
$TemplateName  = 'Citrix_Windows_Server_2022_2203.xml'
$TemplatePath  = "$ExtractPath\Templates\$TemplateName"

Write-Step "Verifying Citrix Optimizer is staged..."
if (-not (Test-Path $ZipPath)) {
  throw "CitrixOptimizer.zip not found at $ZipPath. Ensure the AIB File customizer step ran successfully."
}

Write-Step "Extracting Citrix Optimizer..."
Expand-Archive -Path $ZipPath -DestinationPath $ExtractPath -Force
Remove-Item -Path $ZipPath -Force

if (-not (Test-Path $OptimizerExe)) {
  throw "CitrixOptimizer.exe not found in extracted archive. Verify the zip structure."
}

if (-not (Test-Path $TemplatePath)) {
  Write-Output "WARNING: Template '$TemplateName' not found. Available templates:"
  Get-ChildItem "$ExtractPath\Templates" -Filter '*.xml' | Select-Object -ExpandProperty Name | Write-Output
  throw "Expected template not found. Update the TemplateName variable in this script to match an available template."
}

Write-Step "Running Citrix Optimizer (analyse mode)..."
& $OptimizerExe -Source $TemplatePath -Mode Analyze -OutputHtml $ReportPath
Write-Output "  Analysis report written to: $ReportPath"

Write-Step "Applying optimizations..."
& $OptimizerExe -Source $TemplatePath -Mode Execute
Write-Output "  Optimizations applied."

Write-Step "Verifying optimization results..."
& $OptimizerExe -Source $TemplatePath -Mode Verify

Write-Step "Citrix Optimizer complete."
Write-Output "  The following categories were applied from template: $TemplateName"
Write-Output "  - Unnecessary scheduled tasks disabled"
Write-Output "  - Unnecessary services disabled (compatible with VDA)"
Write-Output "  - Visual effects reduced for multi-session performance"
Write-Output "  - Windows features tuned for VDI workloads"
