# PSVergeOS

A PowerShell module for managing VergeOS infrastructure. PSVergeOS provides a comprehensive set of cmdlets for automating VM lifecycle, networking, storage, multi-tenant operations, and disaster recovery through the VergeOS REST API.

Built for infrastructure administrators and automation engineers who want to leverage PowerShell expertise for VergeOS management.

## Key Features

- **Complete VM Management** - Create, configure, start, stop, clone, snapshot, and migrate virtual machines
- **Advanced Networking** - Configure virtual networks, firewall rules, DHCP, DNS, IPSec VPN, and WireGuard
- **NAS & Storage** - Manage NAS services, volumes, CIFS/NFS shares, and volume synchronization
- **Multi-Tenancy** - Provision and manage tenant environments with full resource isolation
- **Disaster Recovery** - Cloud snapshots, site synchronization, and automated recovery workflows
- **Pipeline Support** - Chain cmdlets together for bulk operations and automation
- **Cross-Platform** - Works on Windows, macOS, and Linux with PowerShell 7.4+

## Requirements

- PowerShell 7.4 or later
- VergeOS 26.0 or later

## Installation

### From PowerShell Gallery (Recommended)

```powershell
Install-Module -Name PSVergeOS -Scope CurrentUser
```

### Manual Installation

```powershell
# Clone the repository
git clone https://github.com/verge-io/PSVergeOS.git

# Import the module
Import-Module ./PSVergeOS/PSVergeOS.psd1
```

## Quick Start

### Connect to VergeOS

```powershell
# Interactive login with credential prompt
Connect-VergeOS -Server "vergeos.company.com" -Credential (Get-Credential)

# Token-based login for automation
Connect-VergeOS -Server "vergeos.company.com" -Token $env:VERGE_TOKEN

# Self-signed certificate environments
Connect-VergeOS -Server "vergeos.local" -Credential $cred -SkipCertificateCheck
```

### Virtual Machine Operations

```powershell
# List all VMs
Get-VergeVM

# Filter VMs by name and state
Get-VergeVM -Name "Web*" -PowerState Running

# Start/Stop VMs
Start-VergeVM -Name "WebServer01"
Stop-VergeVM -Name "WebServer01"

# Create a snapshot before maintenance
New-VergeVMSnapshot -VMName "WebServer01" -Name "Pre-Update"

# Clone a VM from template
New-VergeVMClone -SourceVM "Template-Ubuntu22" -Name "NewServer"
```

### Network Management

```powershell
# Create a network with DHCP
New-VergeNetwork -Name "App-Network" -NetworkAddress "10.10.0.0/24" `
    -Gateway "10.10.0.1" -DHCPEnabled -DHCPStart "10.10.0.100" -DHCPStop "10.10.0.200"

# Add a firewall rule
New-VergeNetworkRule -Network "External" -Name "Allow-HTTPS" `
    -Action Accept -Direction Incoming -Protocol TCP -DestinationPorts "443"

# Apply rules to activate changes
Invoke-VergeNetworkApply -Network "External"
```

### Bulk Operations with Pipeline

```powershell
# Stop all VMs matching a pattern
Get-VergeVM -Name "Dev-*" | Stop-VergeVM -Confirm:$false

# Snapshot all production VMs
Get-VergeVM -Name "Prod-*" | ForEach-Object {
    New-VergeVMSnapshot -VMName $_.Name -Name "Daily-$(Get-Date -Format 'yyyyMMdd')"
}

# Export VM inventory to CSV
Get-VergeVM | Select-Object Name, PowerState, CPUCores, RAM, Cluster | Export-Csv vms.csv
```

### Multi-Server Management

```powershell
# Connect to multiple VergeOS systems
$prod = Connect-VergeOS -Server "prod.vergeos.local" -Token $env:PROD_TOKEN -PassThru
$dev = Connect-VergeOS -Server "dev.vergeos.local" -Token $env:DEV_TOKEN -PassThru

# Query specific server
Get-VergeVM -Server $prod
Get-VergeVM -Server $dev

# Switch default connection
Set-VergeConnection -Server "prod.vergeos.local"
```

## Cmdlet Reference

PSVergeOS includes over 200 cmdlets organized by functional area.

### Connection Management

| Cmdlet | Description |
|--------|-------------|
| `Connect-VergeOS` | Establish connection to a VergeOS system |
| `Disconnect-VergeOS` | Close connection and invalidate session |
| `Get-VergeConnection` | Display active connections |
| `Set-VergeConnection` | Change the default connection |

### Virtual Machines

| Cmdlet | Description |
|--------|-------------|
| `Get-VergeVM` | List virtual machines with filtering |
| `New-VergeVM` | Create a new virtual machine |
| `Set-VergeVM` | Modify VM configuration (CPU, RAM, etc.) |
| `Remove-VergeVM` | Delete a virtual machine |
| `Start-VergeVM` | Power on a VM |
| `Stop-VergeVM` | Power off a VM (graceful or forced) |
| `Restart-VergeVM` | Reboot a VM |
| `Move-VergeVM` | Migrate VM to different node |
| `New-VergeVMClone` | Clone a VM |
| `New-VergeVMSnapshot` | Create a VM snapshot |
| `Get-VergeVMSnapshot` | List VM snapshots |
| `Restore-VergeVMSnapshot` | Restore VM from snapshot |
| `Remove-VergeVMSnapshot` | Delete a snapshot |
| `Get-VergeVMConsole` | Get VM console URL |
| `Get-VergeDrive` | List VM drives |
| `New-VergeDrive` | Add a drive to a VM |
| `Set-VergeDrive` | Modify drive settings |
| `Remove-VergeDrive` | Remove a drive from a VM |
| `Get-VergeNIC` | List VM network interfaces |
| `New-VergeNIC` | Add a NIC to a VM |
| `Set-VergeNIC` | Modify NIC settings |
| `Remove-VergeNIC` | Remove a NIC from a VM |

### Networking

| Cmdlet | Description |
|--------|-------------|
| `Get-VergeNetwork` | List networks |
| `New-VergeNetwork` | Create a network |
| `Set-VergeNetwork` | Modify network settings |
| `Remove-VergeNetwork` | Delete a network |
| `Start-VergeNetwork` | Power on a network |
| `Stop-VergeNetwork` | Power off a network |
| `Restart-VergeNetwork` | Restart a network |
| `Invoke-VergeNetworkApply` | Apply pending rule changes |
| `Get-VergeNetworkRule` | List firewall rules |
| `New-VergeNetworkRule` | Create a firewall rule |
| `Set-VergeNetworkRule` | Modify a firewall rule |
| `Remove-VergeNetworkRule` | Delete a firewall rule |
| `Get-VergeNetworkHost` | List DHCP reservations |
| `New-VergeNetworkHost` | Create a DHCP reservation |
| `Set-VergeNetworkHost` | Modify a DHCP reservation |
| `Remove-VergeNetworkHost` | Delete a DHCP reservation |
| `Get-VergeNetworkAlias` | List IP aliases/groups |
| `New-VergeNetworkAlias` | Create an IP alias |
| `Remove-VergeNetworkAlias` | Delete an IP alias |
| `Get-VergeDNSZone` | List DNS zones |
| `Get-VergeDNSRecord` | List DNS records |
| `New-VergeDNSRecord` | Create a DNS record |
| `Remove-VergeDNSRecord` | Delete a DNS record |
| `Get-VergeNetworkStatistics` | Get network traffic statistics |
| `Get-VergeNetworkDiagnostics` | Get ARP table and DHCP leases |

### VPN (IPSec & WireGuard)

| Cmdlet | Description |
|--------|-------------|
| `Get-VergeIPSecConnection` | List IPSec connections |
| `New-VergeIPSecConnection` | Create an IPSec connection |
| `Set-VergeIPSecConnection` | Modify IPSec connection |
| `Remove-VergeIPSecConnection` | Delete IPSec connection |
| `Get-VergeIPSecPolicy` | List IPSec policies |
| `New-VergeIPSecPolicy` | Create an IPSec policy |
| `Remove-VergeIPSecPolicy` | Delete an IPSec policy |
| `Get-VergeWireGuard` | List WireGuard interfaces |
| `New-VergeWireGuard` | Create a WireGuard interface |
| `Set-VergeWireGuard` | Modify WireGuard interface |
| `Remove-VergeWireGuard` | Delete WireGuard interface |
| `Get-VergeWireGuardPeer` | List WireGuard peers |
| `New-VergeWireGuardPeer` | Add a WireGuard peer |
| `Remove-VergeWireGuardPeer` | Remove a WireGuard peer |

### NAS & Storage

| Cmdlet | Description |
|--------|-------------|
| `Get-VergeNASService` | List NAS services |
| `New-VergeNASService` | Deploy a NAS service |
| `Set-VergeNASService` | Modify NAS service settings |
| `Remove-VergeNASService` | Remove a NAS service |
| `Get-VergeNASVolume` | List NAS volumes |
| `New-VergeNASVolume` | Create a volume |
| `Set-VergeNASVolume` | Modify volume settings |
| `Remove-VergeNASVolume` | Delete a volume |
| `Get-VergeNASVolumeSnapshot` | List volume snapshots |
| `New-VergeNASVolumeSnapshot` | Create a volume snapshot |
| `Remove-VergeNASVolumeSnapshot` | Delete a volume snapshot |
| `Get-VergeNASCIFSShare` | List CIFS/SMB shares |
| `New-VergeNASCIFSShare` | Create a CIFS share |
| `Set-VergeNASCIFSShare` | Modify CIFS share |
| `Remove-VergeNASCIFSShare` | Delete CIFS share |
| `Get-VergeNASNFSShare` | List NFS shares |
| `New-VergeNASNFSShare` | Create an NFS share |
| `Set-VergeNASNFSShare` | Modify NFS share |
| `Remove-VergeNASNFSShare` | Delete NFS share |
| `Get-VergeNASVolumeSync` | List volume sync jobs |
| `New-VergeNASVolumeSync` | Create a volume sync |
| `Start-VergeNASVolumeSync` | Start a sync job |
| `Stop-VergeNASVolumeSync` | Stop a sync job |
| `Get-VergeNASVolumeFile` | Browse volume files |
| `Get-VergeNASUser` | List NAS local users |
| `New-VergeNASUser` | Create a NAS user |
| `Set-VergeNASUser` | Modify NAS user |
| `Remove-VergeNASUser` | Delete NAS user |
| `Get-VergeStorageTier` | List storage tiers |
| `Get-VergevSANStatus` | Get vSAN health status |

### Tenants

| Cmdlet | Description |
|--------|-------------|
| `Get-VergeTenant` | List tenants |
| `New-VergeTenant` | Create a tenant |
| `Set-VergeTenant` | Modify tenant settings |
| `Remove-VergeTenant` | Delete a tenant |
| `Start-VergeTenant` | Power on a tenant |
| `Stop-VergeTenant` | Power off a tenant |
| `Restart-VergeTenant` | Restart a tenant |
| `New-VergeTenantClone` | Clone a tenant |
| `Connect-VergeTenantContext` | Execute commands in tenant context |
| `Get-VergeTenantSnapshot` | List tenant snapshots |
| `New-VergeTenantSnapshot` | Create tenant snapshot |
| `Restore-VergeTenantSnapshot` | Restore tenant from snapshot |
| `Get-VergeTenantStorage` | List tenant storage allocations |
| `New-VergeTenantStorage` | Add storage to tenant |
| `Set-VergeTenantStorage` | Modify tenant storage |
| `Get-VergeTenantExternalIP` | List tenant external IPs |
| `New-VergeTenantExternalIP` | Assign external IP to tenant |
| `Get-VergeTenantNetworkBlock` | List tenant network blocks |
| `New-VergeTenantNetworkBlock` | Assign network block to tenant |
| `Get-VergeSharedObject` | List VMs shared with tenant |
| `New-VergeSharedObject` | Share a VM with tenant |
| `Import-VergeSharedObject` | Import shared VM into tenant |
| `New-VergeTenantCrashCart` | Deploy emergency console VM |

### Users & Groups

| Cmdlet | Description |
|--------|-------------|
| `Get-VergeUser` | List users |
| `New-VergeUser` | Create a user |
| `Set-VergeUser` | Modify user settings |
| `Remove-VergeUser` | Delete a user |
| `Enable-VergeUser` | Enable a user account |
| `Disable-VergeUser` | Disable a user account |
| `Get-VergeAPIKey` | List user API keys |
| `New-VergeAPIKey` | Create an API key |
| `Remove-VergeAPIKey` | Delete an API key |
| `Get-VergeGroup` | List groups |
| `New-VergeGroup` | Create a group |
| `Set-VergeGroup` | Modify group settings |
| `Remove-VergeGroup` | Delete a group |
| `Get-VergeGroupMember` | List group members |
| `Add-VergeGroupMember` | Add user to group |
| `Remove-VergeGroupMember` | Remove user from group |
| `Get-VergePermission` | List permissions |
| `Grant-VergePermission` | Grant a permission |
| `Revoke-VergePermission` | Revoke a permission |

### System Administration

| Cmdlet | Description |
|--------|-------------|
| `Get-VergeVersion` | Get VergeOS version information |
| `Get-VergeCluster` | List clusters |
| `New-VergeCluster` | Create a cluster |
| `Set-VergeCluster` | Modify cluster settings |
| `Remove-VergeCluster` | Delete a cluster |
| `Get-VergeNode` | List nodes |
| `Enable-VergeNodeMaintenance` | Put node in maintenance mode |
| `Disable-VergeNodeMaintenance` | Take node out of maintenance |
| `Restart-VergeNode` | Perform maintenance reboot |
| `Get-VergeNodeDevice` | List PCI/USB/GPU devices |
| `Get-VergeNodeDriver` | List custom drivers |
| `Get-VergeSystemStatistics` | Get system dashboard stats |
| `Get-VergeSystemSetting` | List system settings |
| `Get-VergeLicense` | Get license information |

### Monitoring & Tasks

| Cmdlet | Description |
|--------|-------------|
| `Get-VergeAlarm` | List active alarms |
| `Set-VergeAlarm` | Acknowledge/snooze alarms |
| `Get-VergeLog` | List system logs |
| `Get-VergeTask` | List running tasks |
| `Wait-VergeTask` | Wait for task completion |
| `Stop-VergeTask` | Cancel a running task |
| `Enable-VergeTask` | Enable a scheduled task |

### Backup & Disaster Recovery

| Cmdlet | Description |
|--------|-------------|
| `Get-VergeSnapshotProfile` | List snapshot profiles |
| `New-VergeSnapshotProfile` | Create snapshot profile |
| `Set-VergeSnapshotProfile` | Modify snapshot profile |
| `Remove-VergeSnapshotProfile` | Delete snapshot profile |
| `Get-VergeCloudSnapshot` | List cloud snapshots |
| `New-VergeCloudSnapshot` | Create a cloud snapshot |
| `Remove-VergeCloudSnapshot` | Delete cloud snapshot |
| `Restore-VergeVMFromCloudSnapshot` | Restore VM from cloud snapshot |
| `Restore-VergeTenantFromCloudSnapshot` | Restore tenant from cloud snapshot |
| `Get-VergeSite` | List remote sites |
| `New-VergeSite` | Add a remote site |
| `Remove-VergeSite` | Remove a remote site |
| `Get-VergeSiteSync` | List site sync configurations |
| `Start-VergeSiteSync` | Start site synchronization |
| `Stop-VergeSiteSync` | Stop site synchronization |
| `Invoke-VergeSiteSync` | Trigger immediate sync |
| `Get-VergeSiteSyncIncoming` | List incoming syncs |

### Files & Media

| Cmdlet | Description |
|--------|-------------|
| `Get-VergeFile` | List files (ISOs, images) |
| `Save-VergeFile` | Download a file |
| `Send-VergeFile` | Upload a file |
| `Remove-VergeFile` | Delete a file |
| `Import-VergeDrive` | Import drive image |
| `Import-VergeVM` | Import VM from file |

For detailed help on any cmdlet:

```powershell
Get-Help Get-VergeVM -Full
Get-Help New-VergeNetwork -Examples
```

## Example Scripts

The `Examples/` directory contains ready-to-use scripts demonstrating common workflows:

| Script | Description |
|--------|-------------|
| **[01-Connection.ps1](Examples/01-Connection.ps1)** | Connection methods: interactive, token-based, multi-server management |
| **[02-CreateVMWithNetwork.ps1](Examples/02-CreateVMWithNetwork.ps1)** | Complete workflow: create network, VM, drives, NIC, and boot from ISO |
| **[03-VMLifecycle.ps1](Examples/03-VMLifecycle.ps1)** | VM operations: listing, filtering, power control, snapshots, cloning, bulk operations |
| **[04-NetworkManagement.ps1](Examples/04-NetworkManagement.ps1)** | Network configuration: DHCP, firewall rules, DNS, IP aliases, diagnostics |
| **[05-SystemManagement.ps1](Examples/05-SystemManagement.ps1)** | System administration: clusters, nodes, maintenance mode, hardware discovery |
| **[06-NASSimple.ps1](Examples/06-NASSimple.ps1)** | Basic NAS setup: deploy service, create volumes and shares |
| **[07-NASVolumeSync.ps1](Examples/07-NASVolumeSync.ps1)** | Volume synchronization for backup and replication |
| **[08-NASAdvanced.ps1](Examples/08-NASAdvanced.ps1)** | Advanced NAS: CIFS/NFS settings, local users, Active Directory |
| **[09-TaskManagement.ps1](Examples/09-TaskManagement.ps1)** | Task monitoring: list, wait, cancel, and track long-running operations |
| **[10-AlarmsAndLogs.ps1](Examples/10-AlarmsAndLogs.ps1)** | Monitoring: alarms, acknowledgment, system logs, health checks |
| **[11-RestoreFromCloudSnapshot.ps1](Examples/11-RestoreFromCloudSnapshot.ps1)** | Disaster recovery: restore VMs and tenants from cloud snapshots |

## Development

### Running Tests

```powershell
# Run all tests
Invoke-Pester -Path ./Tests

# Run with code coverage
Invoke-Pester -Path ./Tests -CodeCoverage ./Public/**/*.ps1

# Run specific test file
Invoke-Pester -Path ./Tests/Unit/Connection.Tests.ps1
```

### Code Quality

```powershell
# Analyze code with PSScriptAnalyzer
Invoke-ScriptAnalyzer -Path ./Public -Recurse
```

### Local Development

```powershell
# Import module for testing
Import-Module ./PSVergeOS.psd1 -Force

# List all available cmdlets
Get-Command -Module PSVergeOS
```

## Contributing

Contributions are welcome! Please follow these guidelines:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/new-cmdlet`)
3. Write tests for your changes
4. Ensure all tests pass (`Invoke-Pester`)
5. Run script analyzer (`Invoke-ScriptAnalyzer`)
6. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Resources

- [VergeOS Documentation](https://docs.verge.io/) - Official VergeOS documentation
- [VergeOS API Reference](https://docs.verge.io/knowledge-base/category/api/) - REST API documentation
- [GitHub Issues](https://github.com/verge-io/PSVergeOS/issues) - Bug reports and feature requests
- [VergeOS Support](https://www.verge.io/support) - Commercial support options
