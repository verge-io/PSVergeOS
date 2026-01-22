# PSVergeOS

A PowerShell module for managing VergeOS infrastructure. Similar to VMware PowerCLI, PSVergeOS provides cmdlets for automating VM lifecycle, networking, storage, and multi-tenant operations through the VergeOS REST API.

## Features

- **VM Management** - Create, start, stop, clone, snapshot, and manage virtual machines
- **Network Operations** - Configure virtual networks, firewall rules, DHCP, and DNS
- **Storage Management** - Manage storage tiers, NAS volumes, and file shares
- **Multi-Tenancy** - Provision and manage tenant environments
- **Pipeline Support** - Chain cmdlets together for bulk operations
- **Cross-Platform** - Works on Windows, macOS, and Linux

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
# Interactive login
Connect-VergeOS -Server "vergeos.company.com" -Credential (Get-Credential)

# Token-based login (for automation)
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
Stop-VergeVM -Name "WebServer01" -Graceful

# Create a snapshot
New-VergeVMSnapshot -VM "WebServer01" -Name "Pre-Update"

# Clone a VM
New-VergeVMClone -SourceVM "Template-Ubuntu22" -Name "NewServer"
```

### Network Management

```powershell
# List networks
Get-VergeNetwork

# Create a firewall rule
New-VergeNetworkRule -Network "External" -Action Accept -Direction Incoming -Port 443 -Protocol TCP

# Apply rules
Invoke-VergeNetworkApply -Network "External"
```

### Bulk Operations

```powershell
# Stop all VMs matching a pattern
Get-VergeVM -Name "Dev-*" | Stop-VergeVM -Graceful

# Export VM inventory to CSV
Get-VergeVM | Select-Object Name, PowerState, CPUCores, RAM | Export-Csv -Path vms.csv

# Snapshot multiple VMs
Get-VergeVM -Name "Prod-*" | ForEach-Object {
    New-VergeVMSnapshot -VM $_.Name -Name "Daily-$(Get-Date -Format 'yyyyMMdd')"
}
```

### Working with Multiple Servers

```powershell
# Connect to multiple VergeOS systems
$prod = Connect-VergeOS -Server "prod.vergeos.local" -Credential $cred
$dev = Connect-VergeOS -Server "dev.vergeos.local" -Credential $cred

# Query specific server
Get-VergeVM -Server $prod
Get-VergeVM -Server $dev
```

## Cmdlet Reference

### Connection
| Cmdlet | Description |
|--------|-------------|
| `Connect-VergeOS` | Establish connection to VergeOS |
| `Disconnect-VergeOS` | Close connection |
| `Get-VergeConnection` | Display current connections |

### Virtual Machines
| Cmdlet | Description |
|--------|-------------|
| `Get-VergeVM` | List virtual machines |
| `New-VergeVM` | Create a new VM |
| `Set-VergeVM` | Modify VM configuration |
| `Remove-VergeVM` | Delete a VM |
| `Start-VergeVM` | Power on a VM |
| `Stop-VergeVM` | Power off a VM |
| `Restart-VergeVM` | Reboot a VM |
| `New-VergeVMClone` | Clone a VM |
| `New-VergeVMSnapshot` | Create a snapshot |
| `Get-VergeVMSnapshot` | List snapshots |
| `Restore-VergeVMSnapshot` | Revert to snapshot |

### Networking
| Cmdlet | Description |
|--------|-------------|
| `Get-VergeNetwork` | List networks |
| `New-VergeNetwork` | Create a network |
| `Get-VergeNetworkRule` | List firewall rules |
| `New-VergeNetworkRule` | Create firewall rule |

### System
| Cmdlet | Description |
|--------|-------------|
| `Get-VergeCluster` | Get cluster information |
| `Get-VergeNode` | Get node information |
| `Get-VergeTask` | List tasks |
| `Wait-VergeTask` | Wait for task completion |

For a complete list of cmdlets, run:

```powershell
Get-Command -Module PSVergeOS
```

## PowerCLI Migration

If you're migrating from VMware PowerCLI, PSVergeOS uses similar patterns:

| PowerCLI | PSVergeOS |
|----------|-----------|
| `Connect-VIServer` | `Connect-VergeOS` |
| `Get-VM` | `Get-VergeVM` |
| `Start-VM` | `Start-VergeVM` |
| `Stop-VM` | `Stop-VergeVM` |
| `New-Snapshot` | `New-VergeVMSnapshot` |
| `Get-VMHost` | `Get-VergeNode` |
| `Get-Cluster` | `Get-VergeCluster` |

See the full mapping in [PRD.md](PRD.md#a-powercli-to-psvergeos-command-mapping).

## Documentation

- [Product Requirements (PRD.md)](PRD.md) - Detailed specifications and API mappings
- [VergeOS Documentation](https://docs.verge.io/) - Official VergeOS documentation
- [VergeOS API Reference](https://docs.verge.io/knowledge-base/category/api/) - REST API documentation

## Contributing

Contributions are welcome! Please read our contributing guidelines before submitting pull requests.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/new-cmdlet`)
3. Write tests for your changes
4. Ensure all tests pass (`Invoke-Pester`)
5. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

- [GitHub Issues](https://github.com/verge-io/PSVergeOS/issues) - Bug reports and feature requests
- [VergeOS Support](https://www.verge.io/support) - Commercial support options
