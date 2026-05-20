---
layout: default
title: Build Sequence
parent: Management
nav_order: 1
---

# Build Sequence
{: .no_toc }

How to order customization steps, and why the sequence matters for hardened Windows images.

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
