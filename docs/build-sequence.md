---
layout: default
title: Build Sequence
parent: Management
nav_order: 1
---

# Build Sequence
{: .no_toc }

Step ordering, what to bake into the image, and package installation patterns for AIB customization scripts.

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Recommended Sequence

```
1. PowerShell  — install agents and software
2. WindowsUpdate
3. WindowsRestart
4. PowerShell  — apply OS hardening
5. PowerShell  — validate hardening
```

The critical rule: **hardening always runs after patching, never before.**

---

## Why Hardening Must Run After Windows Update

Windows Update can reset service startup types. If you disable a service (such as RemoteRegistry) in a hardening step and then run Windows Update, the update may silently restore that service to its default startup type before your image is finalized.

### What causes the reset

**Update packages re-register their services.** When a patch updates a binary that belongs to a Windows service, the update installer re-registers that service using its default configuration — overwriting whatever startup type was set beforehand.

**Component-Based Servicing (CBS) enforces its own baseline.** Modern Windows patches apply changes through CBS, which knows the expected state of each component and enforces it. If a service's default startup type is baked into the component manifest, CBS restores it during servicing regardless of what a script set earlier.

**Script writes have no enforcement mechanism.** When a hardening script sets a startup type via `Set-Service -StartupType Disabled` or writes directly to `HKLM:\SYSTEM\CurrentControlSet\Services\<name>\Start`, that is a one-time write. Windows Update has no awareness of it.

### Services most commonly reset

| Service | Microsoft Default | Why It Gets Reset |
|---|---|---|
| RemoteRegistry | Manual | Serviced frequently as part of OS updates |
| Print Spooler | Automatic | Reset by printer driver updates |
| WinRM | Manual | Updated alongside PowerShell and WMF packages |
| Fax | Manual | Part of legacy Windows feature components |

### What a failed build looks like

If hardening runs before Windows Update, a post-patch validation step will catch the regression:

```
An error occurred: RemoteRegistry not disabled
```

This is not a script bug — it is the expected result of patching over a hardened state. The fix is sequencing, not the script itself.

---

## Hardening Twice: The Re-Apply Pattern

For Windows images, run your hardening script as a second pass after the patch cycle completes:

```bicep
customize: [
  {
    type: 'PowerShell'
    name: 'InstallAgents'
    scriptUri: 'https://${storageAccountName}.blob.core.windows.net/scripts/install-agents.ps1'
    runElevated: true
  }
  {
    type: 'WindowsUpdate'
  }
  {
    type: 'WindowsRestart'
    restartTimeout: '10m'
  }
  {
    type: 'PowerShell'
    name: 'ApplyHardening'
    scriptUri: 'https://${storageAccountName}.blob.core.windows.net/scripts/harden-windows.ps1'
    runElevated: true
  }
  {
    type: 'PowerShell'
    name: 'ValidateHardening'
    inline: [
      'if ((Get-Service -Name RemoteRegistry).StartType -ne "Disabled") { throw "RemoteRegistry not disabled" }'
    ]
    runElevated: true
  }
]
```

Running the hardening script twice (or only post-patch) costs a few extra minutes but guarantees the final image reflects your policy, not the post-patch defaults.

---

## Inline Script Character Restrictions

AIB wraps `inline` PowerShell commands inside a Packer elevated shell template. Certain characters break the string parsing in that wrapper:

| Character | Effect | Fix |
|---|---|---|
| Em dash `—` | Parse error: `The string is missing the terminator: '"` | Replace with a regular hyphen `-` |
| Curly quotes `"` `"` | Same parse error | Use straight double quotes `"` |

This restriction applies only to `inline` arrays. Scripts referenced via `scriptUri` are downloaded and executed as files and are not affected.

---

## What to Bake Into the Image

The factory should only bake in software and configuration that is **universal and environment-agnostic** — things that are true for every VM regardless of where it lands. Anything requiring a per-VM value, a subscription ID, a workspace, or a credential belongs to the deployment layer, not the image.

| Bake in | Apply at deployment |
|---|---|
| Agent binaries (monitoring, EDR, management) | Agent configuration tied to a workspace or tenant ID |
| OS hardening (services, registry, SMB policy) | Domain or Entra join |
| Language packs, runtimes, redistributables | Data Collection Rule associations |
| Corporate tooling with no per-env config | MDE onboarding (tenant-specific) |
| Approved application packages (MSI/EXE/MSIX) | Per-workload software |
| Windows Update (at build time) | Post-deploy Windows Update (policy-driven) |
| Drivers required for the VM type | Environment-specific certificates or secrets |

**The test:** if two teams in two different Azure subscriptions would need different values for it, it does not belong in the image.

For the deployment side of this split — VM extensions, AMA Data Collection Rules, MDE onboarding, and domain join — see [Image Consumption](../image-consumption).

---

## Package Formats and Installation Patterns

AIB customization runs as SYSTEM in an elevated PowerShell session. The table below covers the package formats you are most likely to encounter and how to handle each reliably inside a customization script.

| Format | Silent install pattern | Notes |
|---|---|---|
| `.msi` | `msiexec /i app.msi /qn /norestart /log app.log` | Most predictable; exit 0 = success, 3010 = success + reboot needed |
| `.exe` (wraps MSI) | Vendor-specific: `/quiet`, `/silent`, `/S` | Test flags against the vendor's documentation; log output when available |
| `.exe` (custom engine) | Same as above; check for `/norestart` | Custom engines vary widely — test that exit codes are meaningful |
| `.msix` / `.msixbundle` | `Add-AppxProvisionedPackage -Online -PackagePath app.msix -SkipLicense` | Use the provisioned form so the package is available to all users, not just SYSTEM |
| `.appx` / `.appxbundle` | Same as MSIX | Legacy UWP; prefer MSIX where available |
| `.zip` | `Expand-Archive -Path app.zip -DestinationPath C:\install\app` then run contained installer | Extract first; 7z archives require bootstrapping 7-Zip before extraction |
| Winget | `winget install --id Publisher.App --silent --accept-package-agreements` | Available on Windows Server 2022 images; no staging required |
| Chocolatey | Bootstrap: `. { iwr https://chocolatey.org/install.ps1 } | iex` then `choco install pkg -y` | Requires outbound internet from the build VM |
| PowerShell Gallery | `Install-Module -Name ModuleName -Force -AllowClobber` | Installs to all-users scope when run elevated |
| `.cab` | `Add-WindowsPackage -Online -PackagePath update.cab` | Used for LCUs, language packs, and optional features |
| Driver (`.inf` + `.sys`) | `pnputil /add-driver driver.inf /install` | Stage files first using the File customizer |

### Staging Files Before Installation

For packages not available via a package manager, use the AIB **File customizer** to copy the binary from storage into the build VM before running it:

```bicep
{
  type: 'File'
  name: 'StageInstaller'
  sourceUri: 'https://${storageAccountName}.blob.core.windows.net/installers/app.msi'
  destination: 'C:\\install\\app.msi'
}
{
  type: 'PowerShell'
  name: 'InstallApp'
  scriptUri: 'https://${storageAccountName}.blob.core.windows.net/scripts/install-app.ps1'
  runElevated: true
}
```

Keep the installation logic in a `scriptUri` script rather than `inline` to avoid the character restrictions described above and to keep logs readable.

### Exit Code Handling

AIB fails the build if a customization step exits non-zero. For MSI installs, exit code `3010` (success, reboot pending) is valid and should be treated as success:

```powershell
msiexec /i "C:\install\app.msi" /qn /norestart /log "C:\install\app.log"
if ($LASTEXITCODE -notin @(0, 3010)) {
    throw "Install failed with exit code $LASTEXITCODE. See C:\install\app.log"
}
```

If a reboot is needed after install, add a `WindowsRestart` step in the Bicep template after the install step rather than triggering a restart from within the script.
