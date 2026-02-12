---
title: PSVergeOS Cmdlet Reference
description: Complete reference documentation index for all PSVergeOS cmdlets organized by functional area
tags: [reference, index, cmdlets, powershell, psverge, overview, pipeline, naming-conventions, get-help]
categories: [Reference]
---

# PSVergeOS Cmdlet Reference

Complete reference documentation for all PSVergeOS cmdlets organized by functional area.

## Quick Navigation

| Category | Description | Count |
|----------|-------------|-------|
| [Connection](Connection.md) | Session management and authentication | 4 |
| [Virtual Machines](VirtualMachines.md) | VM lifecycle and configuration | 22 |
| [Networking](Networking.md) | Networks, firewall, DHCP, DNS | 25 |
| [VPN](VPN.md) | IPSec and WireGuard configuration | 14 |
| [Storage](Storage.md) | NAS services, volumes, and shares | 42 |
| [Tenants](Tenants.md) | Multi-tenant environment management | 36 |
| [Users](Users.md) | User, group, and permission management | 19 |
| [System](System.md) | Clusters, nodes, certificates, and system administration | 20 |
| [Monitoring](Monitoring.md) | Alarms, logs, and tasks | 7 |
| [Backup](Backup.md) | Snapshots, cloud backup, and disaster recovery | 20 |
| [Files](Files.md) | Media files, ISOs, and imports | 6 |

## Getting Help

Every cmdlet includes built-in help accessible via `Get-Help`:

```powershell
# Basic help
Get-Help Get-VergeVM

# Detailed help with parameters
Get-Help Get-VergeVM -Full

# Show examples
Get-Help New-VergeNetwork -Examples

# List all cmdlets
Get-Command -Module PSVergeOS
```

## Common Parameters

All PSVergeOS cmdlets support these common parameters:

| Parameter | Description |
|-----------|-------------|
| `-Server` | Specify which VergeOS connection to use (for multi-server scenarios) |
| `-Verbose` | Show detailed operation logging |
| `-WhatIf` | Preview changes without executing (destructive operations) |
| `-Confirm` | Prompt for confirmation (destructive operations) |

## Pipeline Support

Most cmdlets support PowerShell pipeline for chaining operations:

```powershell
# Stop all VMs matching a pattern
Get-VergeVM -Name "Dev-*" | Stop-VergeVM

# Create snapshots for running VMs
Get-VergeVM -PowerState Running | ForEach-Object {
    New-VergeVMSnapshot -VMName $_.Name -Name "Backup"
}

# Export data to CSV
Get-VergeNetwork | Select-Object Name, Type, Network | Export-Csv networks.csv
```

## Naming Conventions

PSVergeOS follows PowerShell naming conventions:

- **Get-** - Retrieve information (read-only)
- **New-** - Create new resources
- **Set-** - Modify existing resources
- **Remove-** - Delete resources
- **Start-** - Power on or begin operations
- **Stop-** - Power off or halt operations
- **Restart-** - Reboot or restart operations
- **Invoke-** - Execute actions
- **Enable-/Disable-** - Toggle features on/off
- **Grant-/Revoke-** - Manage permissions

All cmdlets use the `Verge` noun prefix (e.g., `Get-VergeVM`, `New-VergeNetwork`).
