# Customization Scripts

Scripts executed inside the image during the Azure Image Builder build process.

## Planned Scripts

| Script | OS | Purpose |
|---|---|---|
| `harden-windows.ps1` | Windows | Apply CIS benchmark hardening |
| `install-agents.ps1` | Windows | Install Azure Monitor Agent, Defender for Endpoint |
| `configure-base.sh` | Linux | Base OS configuration and hardening |
| `install-agents.sh` | Linux | Install Azure Monitor Agent on Linux |

## Notes

- Scripts are uploaded to an Azure Storage Account and referenced in the AIB image template via `scriptUri`
- Secrets (e.g., join passwords, certificates) should be retrieved from Key Vault at runtime — never hardcoded
