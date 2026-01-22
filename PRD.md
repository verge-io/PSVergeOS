# Product Requirements Document: VergeOS PowerShell Module

**Project Name:** PSVergeOS
**Version:** 1.0
**License:** MIT (Open Source)
**Maintainer:** Verge Engineering
**Date:** January 22, 2026
**Status:** Draft  

---

## 1. Executive Summary

This document outlines the requirements for developing a PowerShell module that provides a command-line interface for managing VergeOS infrastructure. Similar to VMware's PowerCLI, this module will enable administrators to automate tasks, perform bulk operations, and integrate VergeOS management into existing PowerShell-based workflows and scripts.

The module will wrap the VergeOS REST API (v4) with idiomatic PowerShell cmdlets, providing a familiar experience for administrators transitioning from VMware environments or those already proficient in PowerShell automation.

---

## 2. Problem Statement

### Current State
- VergeOS provides a REST API (`/api/v4/`) for programmatic access
- Existing CLI tools include:
  - **verge-cli**: A Go-based CLI tool (cross-platform, but not PowerShell-native)
  - **yb-api**: A bash helper script (requires SSH access to nodes)
  - **Terraform Provider**: Infrastructure-as-code (not suitable for ad-hoc tasks)
- Many organizations migrating from VMware have existing PowerShell expertise and automation scripts
- No native PowerShell module exists for VergeOS management

### Pain Points
1. Administrators cannot leverage existing PowerShell skills for VergeOS management
2. No pipeline support for chaining VergeOS operations with other PowerShell commands
3. Bulk operations require manual API calls or custom scripting
4. VMware-to-VergeOS migrations lose existing PowerCLI automation investments
5. Windows-centric IT shops lack native tooling integration

---

## 3. Goals and Objectives

### Primary Goals
1. Provide a PowerShell-native interface for VergeOS API operations
2. Enable automation of common administrative tasks (VM lifecycle, network management, user provisioning)
3. Support pipeline operations for bulk management scenarios
4. Reduce time-to-productivity for administrators familiar with PowerCLI

### Success Criteria
- Module passes Pester tests with >90% code coverage
- All core VM lifecycle operations supported (create, start, stop, remove, clone, snapshot)
- Documentation includes examples for 20+ common use cases
- Module approved for PowerShell Gallery publication
- Adoption by [X] customers within 6 months of release

### Non-Goals (Out of Scope for v1.0)
- GUI or graphical tools
- Real-time monitoring dashboards
- Direct vSAN/storage tier management (beyond basic queries)
- Tenant billing/chargeback operations
- VergeOS installation or upgrade automation

---

## 4. Target Users

### Primary Users
| Persona | Description | Key Needs |
|---------|-------------|-----------|
| **Infrastructure Admin** | Manages day-to-day VergeOS operations | Quick VM provisioning, bulk operations, reporting |
| **Automation Engineer** | Builds CI/CD pipelines and automation | Scriptable commands, consistent output, error handling |
| **VMware Migrator** | Transitioning from vSphere environment | Familiar PowerCLI-like syntax, migration helpers |

### Secondary Users
| Persona | Description | Key Needs |
|---------|-------------|-----------|
| **MSP Technician** | Manages multiple VergeOS tenants | Multi-tenant support, credential management |
| **Security Admin** | Audits and manages access | User/group management, permission reporting |

---

## 5. Functional Requirements

### 5.1 Authentication & Connection

| ID | Requirement | Priority |
|----|-------------|----------|
| AUTH-01 | Connect to VergeOS system using username/password | P0 |
| AUTH-02 | Connect using API token for non-interactive scenarios | P0 |
| AUTH-03 | Support multiple simultaneous connections (different systems) | P1 |
| AUTH-04 | Securely store credentials using PowerShell SecretManagement | P1 |
| AUTH-05 | Support self-signed certificates with `-SkipCertificateCheck` | P0 |
| AUTH-06 | Automatic session token refresh before expiration | P2 |
| AUTH-07 | Disconnect and invalidate session tokens | P1 |

**Example Usage:**
```powershell
# Interactive login
Connect-VergeOS -Server "vergeos.company.com" -Credential (Get-Credential)

# Token-based login
Connect-VergeOS -Server "vergeos.company.com" -Token $env:VERGE_TOKEN

# Multiple connections
$prod = Connect-VergeOS -Server "prod.vergeos.local" -Credential $cred
$dev = Connect-VergeOS -Server "dev.vergeos.local" -Credential $cred
Get-VergeVM -Server $prod
```

### 5.2 Virtual Machine Management

| ID | Requirement | Priority |
|----|-------------|----------|
| VM-01 | List all VMs with filtering (name, status, cluster) | P0 |
| VM-02 | Get detailed VM configuration (CPU, RAM, drives, NICs) | P0 |
| VM-03 | Create new VM with specified configuration | P0 |
| VM-04 | Start/Stop/Restart VM (graceful and forced) | P0 |
| VM-05 | Remove/Delete VM | P0 |
| VM-06 | Clone VM with new name | P1 |
| VM-07 | Create VM snapshot | P1 |
| VM-08 | Restore VM from snapshot | P1 |
| VM-09 | List and remove snapshots | P1 |
| VM-10 | Modify VM configuration (CPU, RAM hotplug where supported) | P1 |
| VM-11 | Add/Remove VM drives | P1 |
| VM-12 | Add/Remove VM network interfaces | P1 |
| VM-13 | Get VM console URL/access | P1 |
| VM-14 | Import VM from OVA/OVF | P2 |
| VM-15 | Export VM to OVA/OVF | P3 |
| VM-16 | List VM drives with media source details (size, tier, interface) | P0 |
| VM-17 | Configure VM drives (interface type, tier, media source) | P1 |
| VM-18 | List VM NICs with IP/MAC/network details | P0 |
| VM-19 | Configure VM NICs (network assignment, MAC, IP settings) | P1 |
| VM-20 | Migrate VM to different node | P1 |
| VM-21 | Support VM guest agent operations (execute command, file ops) | P2 |
| VM-22 | Support GPU/TPM/USB device passthrough configuration | P2 |
| VM-23 | Change VM CD/ISO media | P1 |
| VM-24 | Hibernate/Suspend VM | P2 |

**Example Usage:**
```powershell
# List VMs
Get-VergeVM
Get-VergeVM -Name "Web*" -PowerState Running
Get-VergeVM | Where-Object {$_.RAM -gt 8192}

# VM Lifecycle
New-VergeVM -Name "WebServer01" -CPUCores 4 -RAM 8192 -OSFamily Linux
Start-VergeVM -Name "WebServer01"
Stop-VergeVM -Name "WebServer01" -Graceful
Restart-VergeVM -Name "WebServer01" -Force
Remove-VergeVM -Name "WebServer01" -Confirm:$false

# Cloning and Snapshots
New-VergeVMClone -SourceVM "Template-Ubuntu22" -Name "NewServer"
New-VergeVMSnapshot -VM "WebServer01" -Name "Pre-Update"
Get-VergeVMSnapshot -VM "WebServer01"
Restore-VergeVMSnapshot -VM "WebServer01" -Snapshot "Pre-Update"
```

### 5.3 Network Management

| ID | Requirement | Priority |
|----|-------------|----------|
| NET-01 | List all networks with filtering (name, type, status) | P0 |
| NET-02 | Get network details (DHCP, DNS, IP settings, rules) | P0 |
| NET-03 | Create internal/external/DMZ network | P1 |
| NET-04 | Modify network settings (DHCP range, DNS, gateway) | P1 |
| NET-05 | Remove network | P1 |
| NET-06 | Start/Stop/Restart network | P1 |
| NET-07 | List network rules with filtering | P1 |
| NET-08 | Add/Remove/Modify network rules | P1 |
| NET-09 | Apply firewall rules to network | P1 |
| NET-10 | Get network diagnostics (ARP table, DHCP leases) | P2 |
| NET-11 | List network aliases (IP groups for rules) | P2 |
| NET-12 | Add/Remove network aliases | P2 |
| NET-13 | List DHCP host reservations | P2 |
| NET-14 | Add/Remove DHCP host reservations | P2 |
| NET-15 | List DNS zones and records | P2 |
| NET-16 | Add/Remove DNS records | P2 |
| NET-17 | Configure IPSec VPN connections | P2 |
| NET-18 | Configure WireGuard VPN peers | P2 |
| NET-19 | Get network statistics (tx/rx rates, packets) | P2 |
| NET-20 | Configure network rate limiting | P3 |

**Example Usage:**
```powershell
# List and filter networks
Get-VergeNetwork
Get-VergeNetwork -Name "Internal-*" -Type Internal
Get-VergeNetwork | Where-Object { $_.DHCPEnabled }

# Network lifecycle
New-VergeNetwork -Name "Dev-Network" -NetworkAddress "10.10.10.0/24" -DHCPEnabled
Start-VergeNetwork -Name "Dev-Network"
Stop-VergeNetwork -Name "Dev-Network"

# Firewall rules
Get-VergeNetworkRule -Network "External"
New-VergeNetworkRule -Network "External" -Action Accept -Direction Incoming -Port 443 -Protocol TCP
Invoke-VergeNetworkApply -Network "External"  # Apply rules

# DHCP reservations
Get-VergeNetworkHost -Network "Internal"
New-VergeNetworkHost -Network "Internal" -Hostname "server01" -MAC "00:11:22:33:44:55" -IP "10.0.0.50"

# DNS management
Get-VergeDNSZone -Network "Internal"
New-VergeDNSRecord -Network "Internal" -Name "app" -Type A -Value "10.0.0.100"
```

### 5.4 Storage Management

| ID | Requirement | Priority |
|----|-------------|----------|
| STOR-01 | List storage tiers with capacity and usage stats | P0 |
| STOR-02 | Get storage tier details (IOPS, throughput, dedup ratio) | P1 |
| STOR-03 | List VM drives with tier and media source info | P0 |
| STOR-04 | Get vSAN health status and statistics | P2 |
| STOR-05 | List media sources (ISOs, images) | P1 |
| STOR-06 | Upload ISO/image to media sources | P2 |
| STOR-07 | Download/export media sources | P3 |

### 5.5 User and Tenant Management

| ID | Requirement | Priority |
|----|-------------|----------|
| USER-01 | List users with filtering (name, type, enabled) | P1 |
| USER-02 | Create user (normal, API, VDI types) | P1 |
| USER-03 | Modify user settings (password, email, 2FA) | P1 |
| USER-04 | Remove user | P1 |
| USER-05 | Enable/Disable user account | P1 |
| USER-06 | List user API keys | P2 |
| USER-07 | Create/Remove user API keys | P2 |
| USER-08 | List groups | P1 |
| USER-09 | Create/Modify/Remove groups | P2 |
| USER-10 | List group members | P1 |
| USER-11 | Add/Remove group members | P2 |
| USER-12 | List permissions | P2 |
| USER-13 | Grant/Revoke permissions | P2 |
| TENANT-01 | List tenants with status | P1 |
| TENANT-02 | Get tenant details (nodes, storage, network) | P1 |
| TENANT-03 | Create tenant | P2 |
| TENANT-04 | Modify tenant settings | P2 |
| TENANT-05 | Remove tenant | P2 |
| TENANT-06 | Start/Stop/Reset tenant | P1 |
| TENANT-07 | Clone tenant | P2 |
| TENANT-08 | Connect to tenant context (execute commands as tenant) | P2 |
| TENANT-09 | List tenant snapshots | P2 |
| TENANT-10 | Create/Restore tenant snapshot | P2 |
| TENANT-11 | Enable/Disable tenant isolation mode | P3 |

### 5.6 System Information

| ID | Requirement | Priority |
|----|-------------|----------|
| SYS-01 | Get VergeOS version information | P0 |
| SYS-02 | List clusters with status | P1 |
| SYS-03 | Get cluster details (CPU type, RAM, storage tiers) | P1 |
| SYS-04 | List nodes with status and resources | P0 |
| SYS-05 | Get node details (RAM, cores, drives, NICs, GPU) | P1 |
| SYS-06 | Enable/Disable node maintenance mode | P1 |
| SYS-07 | Reboot node (maintenance reboot) | P2 |
| SYS-08 | Get system dashboard/overview statistics | P2 |
| SYS-09 | List system settings | P2 |
| SYS-10 | Get license information | P2 |
| SYS-11 | List node drivers (GPU, network) | P2 |
| SYS-12 | List node PCI/USB/GPU devices | P2 |

### 5.7 Volume/NAS Management

| ID | Requirement | Priority |
|----|-------------|----------|
| VOL-01 | List volumes with capacity and usage | P1 |
| VOL-02 | Get volume details (tier, sync status, shares) | P1 |
| VOL-03 | Create volume | P2 |
| VOL-04 | Modify volume settings | P2 |
| VOL-05 | Remove volume | P2 |
| VOL-06 | List volume snapshots | P1 |
| VOL-07 | Create volume snapshot | P2 |
| VOL-08 | Remove volume snapshot | P2 |
| VOL-09 | List CIFS/SMB shares | P2 |
| VOL-10 | Create/Modify/Remove CIFS share | P2 |
| VOL-11 | List NFS shares | P2 |
| VOL-12 | Create/Modify/Remove NFS share | P2 |
| VOL-13 | List volume sync jobs | P2 |
| VOL-14 | Create/Start/Stop volume sync | P3 |
| VOL-15 | Browse volume files (list, read) | P3 |

**Example Usage:**
```powershell
# Volume management
Get-VergeVolume
Get-VergeVolume -Name "NAS-*" | Select-Object Name, Tier, UsedGB, CapacityGB
New-VergeVolume -Name "FileShare" -Tier 2 -Size 500GB

# Volume snapshots
Get-VergeVolumeSnapshot -Volume "FileShare"
New-VergeVolumeSnapshot -Volume "FileShare" -Name "Daily-Backup"

# Share management
Get-VergeCIFSShare -Volume "FileShare"
New-VergeCIFSShare -Volume "FileShare" -Name "shared" -Path "/shared"
Get-VergeNFSShare -Volume "FileShare"
```

### 5.8 Monitoring and Tasks

| ID | Requirement | Priority |
|----|-------------|----------|
| MON-01 | List active alarms with filtering (severity, type) | P1 |
| MON-02 | Get alarm details and history | P1 |
| MON-03 | Acknowledge/Snooze alarms | P2 |
| MON-04 | List system logs with filtering | P2 |
| MON-05 | List running tasks | P0 |
| MON-06 | Get task details and status | P0 |
| MON-07 | Wait for task completion | P0 |
| MON-08 | Cancel running task | P2 |
| MON-09 | List scheduled tasks | P2 |
| MON-10 | Get resource statistics (CPU, RAM, storage, network) | P2 |

**Example Usage:**
```powershell
# Alarm management
Get-VergeAlarm -Severity Critical
Get-VergeAlarm | Where-Object { $_.Type -eq "disk_error" }
Set-VergeAlarm -Id 123 -Snooze (Get-Date).AddHours(4)

# Task management
Get-VergeTask -Status Running
$task = Start-VergeVM -Name "WebServer" -PassThru
Wait-VergeTask -Task $task -Timeout 300
Get-VergeTask -Id $task.Key | Select-Object Status, Progress, Duration

# Logs
Get-VergeLog -Hours 24 -Severity Error
Get-VergeLog -Machine "WebServer01" -Limit 100
```

### 5.9 Backup and Disaster Recovery

| ID | Requirement | Priority |
|----|-------------|----------|
| DR-01 | List snapshot profiles | P2 |
| DR-02 | Create/Modify snapshot profile | P2 |
| DR-03 | List cloud snapshots (system snapshots) | P2 |
| DR-04 | Create cloud snapshot | P2 |
| DR-05 | Restore from cloud snapshot | P3 |
| DR-06 | List site sync configurations (outgoing) | P2 |
| DR-07 | Get site sync status and statistics | P2 |
| DR-08 | Start/Stop site sync | P2 |
| DR-09 | List site sync incoming (from remote) | P2 |
| DR-10 | List sites (remote VergeOS systems) | P2 |

**Example Usage:**
```powershell
# Snapshot profiles
Get-VergeSnapshotProfile
New-VergeSnapshotProfile -Name "Hourly" -Retention 24h -Interval 1h

# Cloud snapshots
Get-VergeCloudSnapshot
New-VergeCloudSnapshot -Name "Pre-Upgrade-$(Get-Date -Format 'yyyyMMdd')"

# Site sync
Get-VergeSiteSync
Get-VergeSiteSync -Name "DR-Site" | Select-Object Name, Status, LastSync, BytesSynced
Start-VergeSiteSync -Name "DR-Site"
```

---

## 6. Non-Functional Requirements

### 6.1 Compatibility

| ID | Requirement |
|----|-------------|
| COMPAT-01 | Support PowerShell 7.2+ (LTS) on Windows, macOS, and Linux |
| COMPAT-02 | ~~Windows PowerShell 5.1~~ **Not supported** - PS7+ only |
| COMPAT-03 | Compatible with VergeOS 26.0+ (API v4) |
| COMPAT-04 | No external dependencies beyond standard PowerShell modules |

### 6.2 Performance

| ID | Requirement |
|----|-------------|
| PERF-01 | Single API call operations complete in <2 seconds (network permitting) |
| PERF-02 | Bulk operations support `-Parallel` for concurrent execution |
| PERF-03 | Large result sets support pagination without memory issues |

### 6.3 Security

| ID | Requirement |
|----|-------------|
| SEC-01 | Never log or display passwords/tokens in plain text |
| SEC-02 | Support TLS 1.2+ connections only |
| SEC-03 | Credential storage uses OS-native secure storage (DPAPI, Keychain) |
| SEC-04 | Audit logging capability for compliance scenarios |

### 6.4 Usability

| ID | Requirement |
|----|-------------|
| UX-01 | All cmdlets include `-WhatIf` and `-Confirm` for destructive operations |
| UX-02 | Tab completion for parameter values (VM names, network names) |
| UX-03 | Comprehensive `Get-Help` documentation for all cmdlets |
| UX-04 | Consistent error messages with actionable guidance |
| UX-05 | Progress indicators for long-running operations |
| UX-06 | Support `-Verbose` for detailed operation logging |

---

## 7. Technical Architecture

### 7.1 Module Structure

```
PSVergeOS/
├── PSVergeOS.psd1               # Module manifest
├── PSVergeOS.psm1               # Root module
├── Public/                       # Exported cmdlets
│   ├── Connect-VergeOS.ps1
│   ├── Disconnect-VergeOS.ps1
│   ├── VM/
│   │   ├── Get-VergeVM.ps1
│   │   ├── New-VergeVM.ps1
│   │   ├── Start-VergeVM.ps1
│   │   ├── Stop-VergeVM.ps1
│   │   └── ...
│   ├── Network/
│   │   ├── Get-VergeNetwork.ps1
│   │   └── ...
│   └── ...
├── Private/                      # Internal functions
│   ├── Invoke-VergeAPI.ps1      # Core API wrapper
│   ├── ConvertTo-VergeFilter.ps1
│   └── ...
├── Classes/                      # PowerShell classes
│   ├── VergeConnection.ps1
│   ├── VergeVM.ps1
│   └── ...
├── Tests/                        # Pester tests
│   ├── Unit/
│   └── Integration/
├── docs/                         # Documentation
│   └── cmdlets/
└── Examples/                     # Example scripts
```

### 7.2 API Mapping

#### Virtual Machine APIs
| VergeOS API Endpoint | PowerShell Cmdlet |
|---------------------|-------------------|
| `GET /api/v4/vms` | `Get-VergeVM` |
| `POST /api/v4/vms` | `New-VergeVM` |
| `PUT /api/v4/vms/{id}` | `Set-VergeVM` |
| `DELETE /api/v4/vms/{id}` | `Remove-VergeVM` |
| `POST /api/v4/vm_actions` (poweron) | `Start-VergeVM` |
| `POST /api/v4/vm_actions` (poweroff) | `Stop-VergeVM -Graceful` |
| `POST /api/v4/vm_actions` (kill) | `Stop-VergeVM -Force` |
| `POST /api/v4/vm_actions` (reset) | `Restart-VergeVM` |
| `POST /api/v4/vm_actions` (migrate) | `Move-VergeVM` |
| `POST /api/v4/vm_actions` (hibernate) | `Suspend-VergeVM` |
| `POST /api/v4/vm_actions` (clone) | `New-VergeVMClone` |
| `POST /api/v4/vm_actions` (restore) | `Restore-VergeVMSnapshot` |
| `POST /api/v4/vm_actions` (changecd) | `Set-VergeDrive -Media` |
| `POST /api/v4/vm_actions` (changenet) | `Set-VergeNIC -Network` |
| `POST /api/v4/vm_actions` (execute) | `Invoke-VergeVMScript` |
| `GET /api/v4/machine_drives` | `Get-VergeDrive` |
| `POST /api/v4/machine_drives` | `New-VergeDrive` |
| `PUT /api/v4/machine_drives/{id}` | `Set-VergeDrive` |
| `DELETE /api/v4/machine_drives/{id}` | `Remove-VergeDrive` |
| `GET /api/v4/machine_nics` | `Get-VergeNIC` |
| `POST /api/v4/machine_nics` | `New-VergeNIC` |
| `PUT /api/v4/machine_nics/{id}` | `Set-VergeNIC` |
| `DELETE /api/v4/machine_nics/{id}` | `Remove-VergeNIC` |
| `GET /api/v4/machine_snapshots` | `Get-VergeVMSnapshot` |
| `POST /api/v4/machine_snapshots` | `New-VergeVMSnapshot` |
| `DELETE /api/v4/machine_snapshots/{id}` | `Remove-VergeVMSnapshot` |
| `GET /api/v4/machine_devices` | `Get-VergeDevice` |
| `GET /api/v4/machine_console` | `Get-VergeVMConsole` |

#### Network APIs
| VergeOS API Endpoint | PowerShell Cmdlet |
|---------------------|-------------------|
| `GET /api/v4/vnets` | `Get-VergeNetwork` |
| `POST /api/v4/vnets` | `New-VergeNetwork` |
| `PUT /api/v4/vnets/{id}` | `Set-VergeNetwork` |
| `DELETE /api/v4/vnets/{id}` | `Remove-VergeNetwork` |
| `POST /api/v4/vnet_actions` | `Start-VergeNetwork`, `Stop-VergeNetwork`, `Invoke-VergeNetworkApply` |
| `GET /api/v4/vnet_rules` | `Get-VergeNetworkRule` |
| `POST /api/v4/vnet_rules` | `New-VergeNetworkRule` |
| `DELETE /api/v4/vnet_rules/{id}` | `Remove-VergeNetworkRule` |
| `GET /api/v4/vnet_hosts` | `Get-VergeNetworkHost` |
| `POST /api/v4/vnet_hosts` | `New-VergeNetworkHost` |
| `GET /api/v4/vnet_aliases` | `Get-VergeNetworkAlias` |
| `GET /api/v4/vnet_dns_zones` | `Get-VergeDNSZone` |
| `GET /api/v4/vnet_dns_zone_records` | `Get-VergeDNSRecord` |
| `GET /api/v4/vnet_ipsecs` | `Get-VergeIPSec` |
| `GET /api/v4/vnet_wireguards` | `Get-VergeWireGuard` |

#### Storage APIs
| VergeOS API Endpoint | PowerShell Cmdlet |
|---------------------|-------------------|
| `GET /api/v4/storage_tiers` | `Get-VergeStorageTier` |
| `GET /api/v4/volumes` | `Get-VergeVolume` |
| `POST /api/v4/volumes` | `New-VergeVolume` |
| `PUT /api/v4/volumes/{id}` | `Set-VergeVolume` |
| `DELETE /api/v4/volumes/{id}` | `Remove-VergeVolume` |
| `GET /api/v4/volume_snapshots` | `Get-VergeVolumeSnapshot` |
| `POST /api/v4/volume_snapshots` | `New-VergeVolumeSnapshot` |
| `GET /api/v4/volume_cifs_shares` | `Get-VergeCIFSShare` |
| `POST /api/v4/volume_cifs_shares` | `New-VergeCIFSShare` |
| `GET /api/v4/volume_nfs_shares` | `Get-VergeNFSShare` |
| `POST /api/v4/volume_nfs_shares` | `New-VergeNFSShare` |
| `GET /api/v4/volume_syncs` | `Get-VergeVolumeSync` |
| `GET /api/v4/files` | `Get-VergeFile` |

#### System/Infrastructure APIs
| VergeOS API Endpoint | PowerShell Cmdlet |
|---------------------|-------------------|
| `GET /api/v4/clusters` | `Get-VergeCluster` |
| `GET /api/v4/cluster_status` | (included in `Get-VergeCluster`) |
| `GET /api/v4/nodes` | `Get-VergeNode` |
| `POST /api/v4/node_actions` | `Enable-VergeNodeMaintenance`, `Disable-VergeNodeMaintenance`, `Restart-VergeNode` |
| `GET /api/v4/node_drivers` | `Get-VergeNodeDriver` |
| `GET /api/v4/node_gpus` | `Get-VergeNodeGPU` |
| `GET /api/v4/node_pci_devices` | `Get-VergeNodePCIDevice` |
| `GET /api/v4/node_usb_devices` | `Get-VergeNodeUSBDevice` |
| `GET /api/v4/licenses` | `Get-VergeLicense` |
| `GET /api/v4/system` | `Get-VergeSystem` |
| `GET /api/v4/settings` | `Get-VergeSetting` |

#### User/Group/Tenant APIs
| VergeOS API Endpoint | PowerShell Cmdlet |
|---------------------|-------------------|
| `GET /api/v4/users` | `Get-VergeUser` |
| `POST /api/v4/users` | `New-VergeUser` |
| `PUT /api/v4/users/{id}` | `Set-VergeUser` |
| `DELETE /api/v4/users/{id}` | `Remove-VergeUser` |
| `POST /api/v4/user_actions` | `Enable-VergeUser`, `Disable-VergeUser` |
| `GET /api/v4/user_api_keys` | `Get-VergeAPIKey` |
| `POST /api/v4/user_api_keys` | `New-VergeAPIKey` |
| `GET /api/v4/groups` | `Get-VergeGroup` |
| `POST /api/v4/groups` | `New-VergeGroup` |
| `GET /api/v4/members` | `Get-VergeGroupMember` |
| `POST /api/v4/members` | `Add-VergeGroupMember` |
| `DELETE /api/v4/members/{id}` | `Remove-VergeGroupMember` |
| `GET /api/v4/permissions` | `Get-VergePermission` |
| `POST /api/v4/permissions` | `Grant-VergePermission` |
| `DELETE /api/v4/permissions/{id}` | `Revoke-VergePermission` |
| `GET /api/v4/tenants` | `Get-VergeTenant` |
| `POST /api/v4/tenants` | `New-VergeTenant` |
| `PUT /api/v4/tenants/{id}` | `Set-VergeTenant` |
| `DELETE /api/v4/tenants/{id}` | `Remove-VergeTenant` |
| `POST /api/v4/tenant_actions` | `Start-VergeTenant`, `Stop-VergeTenant`, `New-VergeTenantClone` |
| `GET /api/v4/tenant_snapshots` | `Get-VergeTenantSnapshot` |

#### Monitoring/Task APIs
| VergeOS API Endpoint | PowerShell Cmdlet |
|---------------------|-------------------|
| `GET /api/v4/alarms` | `Get-VergeAlarm` |
| `PUT /api/v4/alarms/{id}` | `Set-VergeAlarm` |
| `GET /api/v4/alarm_history` | `Get-VergeAlarmHistory` |
| `GET /api/v4/logs` | `Get-VergeLog` |
| `GET /api/v4/tasks` | `Get-VergeTask` |

#### Backup/DR APIs
| VergeOS API Endpoint | PowerShell Cmdlet |
|---------------------|-------------------|
| `GET /api/v4/snapshot_profiles` | `Get-VergeSnapshotProfile` |
| `POST /api/v4/snapshot_profiles` | `New-VergeSnapshotProfile` |
| `GET /api/v4/cloud_snapshots` | `Get-VergeCloudSnapshot` |
| `POST /api/v4/cloud_snapshot_actions` | `New-VergeCloudSnapshot`, `Restore-VergeCloudSnapshot` |
| `GET /api/v4/site_syncs_outgoing` | `Get-VergeSiteSync` |
| `POST /api/v4/site_syncs_outgoing_actions` | `Start-VergeSiteSync`, `Stop-VergeSiteSync` |
| `GET /api/v4/site_syncs_incoming` | `Get-VergeSiteSyncIncoming` |
| `GET /api/v4/sites` | `Get-VergeSite` |

### 7.3 Output Objects

All cmdlets return strongly-typed PowerShell objects with consistent properties:

```powershell
# Example: Get-VergeVM returns [VergeVM] objects
[PSCustomObject]@{
    PSTypeName    = 'Verge.VM'
    Key           = [int]       # VM identifier ($key)
    Name          = [string]
    Description   = [string]
    PowerState    = [string]    # Running, Stopped, Suspended
    CPUCores      = [int]
    RAM           = [int]       # MB
    OSFamily      = [string]
    Cluster       = [string]
    MachineKey    = [int]
    Created       = [datetime]
    Modified      = [datetime]
    Drives        = [array]
    NICs          = [array]
}
```

---

## 8. User Stories

### Epic: VM Lifecycle Management

| ID | As a... | I want to... | So that... |
|----|---------|--------------|------------|
| US-01 | Infrastructure Admin | list all VMs in my environment | I can audit my infrastructure |
| US-02 | Infrastructure Admin | filter VMs by name pattern | I can find specific VMs quickly |
| US-03 | Infrastructure Admin | create a VM from command line | I can automate provisioning |
| US-04 | Infrastructure Admin | start/stop multiple VMs at once | I can manage maintenance windows efficiently |
| US-05 | Automation Engineer | script VM creation with parameters | I can integrate with CI/CD pipelines |
| US-06 | Automation Engineer | receive consistent object output | I can pipe results to other commands |

### Epic: Migration Support

| ID | As a... | I want to... | So that... |
|----|---------|--------------|------------|
| US-10 | VMware Migrator | use similar syntax to PowerCLI | I can adapt existing scripts quickly |
| US-11 | VMware Migrator | see a command mapping guide | I know which cmdlets replace my PowerCLI commands |

### Epic: Bulk Operations

| ID | As a... | I want to... | So that... |
|----|---------|--------------|------------|
| US-20 | Infrastructure Admin | stop all VMs matching a pattern | I can perform bulk maintenance |
| US-21 | Infrastructure Admin | export VM inventory to CSV | I can generate reports |
| US-22 | Automation Engineer | run operations in parallel | bulk operations complete faster |

---

## 9. Cmdlet Reference (Proposed)

### Connection Cmdlets (4)
| Cmdlet | Description |
|--------|-------------|
| `Connect-VergeOS` | Establish connection to VergeOS system |
| `Disconnect-VergeOS` | Close connection and invalidate token |
| `Get-VergeConnection` | Display current connection(s) |
| `Set-VergeConnection` | Set default connection for cmdlets |

### VM Cmdlets (22)
| Cmdlet | Description |
|--------|-------------|
| `Get-VergeVM` | Retrieve VM information with filtering |
| `New-VergeVM` | Create a new VM |
| `Set-VergeVM` | Modify VM configuration |
| `Remove-VergeVM` | Delete a VM |
| `Start-VergeVM` | Power on a VM |
| `Stop-VergeVM` | Power off a VM (graceful/forced) |
| `Restart-VergeVM` | Reboot a VM |
| `Suspend-VergeVM` | Hibernate a VM |
| `Move-VergeVM` | Migrate VM to different node |
| `New-VergeVMClone` | Clone an existing VM |
| `New-VergeVMSnapshot` | Create a VM snapshot |
| `Get-VergeVMSnapshot` | List VM snapshots |
| `Remove-VergeVMSnapshot` | Delete a snapshot |
| `Restore-VergeVMSnapshot` | Revert VM to snapshot |
| `Get-VergeDrive` | List VM drives |
| `New-VergeDrive` | Add drive to VM |
| `Set-VergeDrive` | Modify drive (media, interface) |
| `Remove-VergeDrive` | Remove drive from VM |
| `Get-VergeNIC` | List VM network interfaces |
| `New-VergeNIC` | Add NIC to VM |
| `Set-VergeNIC` | Modify NIC (network, MAC) |
| `Remove-VergeNIC` | Remove NIC from VM |
| `Get-VergeDevice` | List VM devices (GPU, TPM, USB) |
| `Get-VergeVMConsole` | Get VM console access URL |
| `Invoke-VergeVMScript` | Execute script via guest agent |

### Network Cmdlets (18)
| Cmdlet | Description |
|--------|-------------|
| `Get-VergeNetwork` | Retrieve network information |
| `New-VergeNetwork` | Create a network |
| `Set-VergeNetwork` | Modify network settings |
| `Remove-VergeNetwork` | Delete a network |
| `Start-VergeNetwork` | Power on a network |
| `Stop-VergeNetwork` | Power off a network |
| `Invoke-VergeNetworkApply` | Apply firewall/DNS rules |
| `Get-VergeNetworkRule` | List firewall rules |
| `New-VergeNetworkRule` | Create firewall rule |
| `Set-VergeNetworkRule` | Modify firewall rule |
| `Remove-VergeNetworkRule` | Delete firewall rule |
| `Get-VergeNetworkHost` | List DHCP reservations |
| `New-VergeNetworkHost` | Create DHCP reservation |
| `Get-VergeNetworkAlias` | List IP aliases for rules |
| `Get-VergeDNSZone` | List DNS zones |
| `Get-VergeDNSRecord` | List DNS records |
| `New-VergeDNSRecord` | Create DNS record |
| `Get-VergeIPSec` | List IPSec VPN configs |
| `Get-VergeWireGuard` | List WireGuard VPN configs |

### Storage Cmdlets (14)
| Cmdlet | Description |
|--------|-------------|
| `Get-VergeStorageTier` | Get storage tier info and stats |
| `Get-VergeVolume` | List NAS volumes |
| `New-VergeVolume` | Create a volume |
| `Set-VergeVolume` | Modify volume settings |
| `Remove-VergeVolume` | Delete a volume |
| `Get-VergeVolumeSnapshot` | List volume snapshots |
| `New-VergeVolumeSnapshot` | Create volume snapshot |
| `Remove-VergeVolumeSnapshot` | Delete volume snapshot |
| `Get-VergeCIFSShare` | List CIFS/SMB shares |
| `New-VergeCIFSShare` | Create CIFS share |
| `Get-VergeNFSShare` | List NFS shares |
| `New-VergeNFSShare` | Create NFS share |
| `Get-VergeVolumeSync` | List volume sync jobs |
| `Get-VergeFile` | Browse volume files |

### System Cmdlets (14)
| Cmdlet | Description |
|--------|-------------|
| `Get-VergeSystem` | Get VergeOS system info |
| `Get-VergeCluster` | Get cluster information |
| `Get-VergeNode` | Get node information |
| `Enable-VergeNodeMaintenance` | Put node in maintenance mode |
| `Disable-VergeNodeMaintenance` | Remove node from maintenance |
| `Restart-VergeNode` | Reboot node (maintenance reboot) |
| `Get-VergeNodeDriver` | List node drivers |
| `Get-VergeNodeGPU` | List node GPU devices |
| `Get-VergeNodePCIDevice` | List node PCI devices |
| `Get-VergeNodeUSBDevice` | List node USB devices |
| `Get-VergeLicense` | Get license information |
| `Get-VergeSetting` | List system settings |
| `Get-VergeMediaSource` | List available ISOs/images |

### User/Group Cmdlets (14)
| Cmdlet | Description |
|--------|-------------|
| `Get-VergeUser` | List users |
| `New-VergeUser` | Create a user |
| `Set-VergeUser` | Modify a user |
| `Remove-VergeUser` | Delete a user |
| `Enable-VergeUser` | Enable user account |
| `Disable-VergeUser` | Disable user account |
| `Get-VergeAPIKey` | List user API keys |
| `New-VergeAPIKey` | Create API key |
| `Remove-VergeAPIKey` | Delete API key |
| `Get-VergeGroup` | List groups |
| `New-VergeGroup` | Create a group |
| `Get-VergeGroupMember` | List group members |
| `Add-VergeGroupMember` | Add user to group |
| `Remove-VergeGroupMember` | Remove user from group |
| `Get-VergePermission` | List permissions |
| `Grant-VergePermission` | Grant permission |
| `Revoke-VergePermission` | Revoke permission |

### Tenant Cmdlets (10)
| Cmdlet | Description |
|--------|-------------|
| `Get-VergeTenant` | List tenants |
| `New-VergeTenant` | Create a tenant |
| `Set-VergeTenant` | Modify tenant settings |
| `Remove-VergeTenant` | Delete a tenant |
| `Start-VergeTenant` | Power on a tenant |
| `Stop-VergeTenant` | Power off a tenant |
| `Restart-VergeTenant` | Reset a tenant |
| `New-VergeTenantClone` | Clone a tenant |
| `Get-VergeTenantSnapshot` | List tenant snapshots |
| `Enter-VergeTenant` | Switch to tenant context |
| `Exit-VergeTenant` | Return to parent context |

### Monitoring Cmdlets (7)
| Cmdlet | Description |
|--------|-------------|
| `Get-VergeAlarm` | List active alarms |
| `Set-VergeAlarm` | Acknowledge/snooze alarm |
| `Get-VergeAlarmHistory` | Get alarm history |
| `Get-VergeLog` | Get system/machine logs |
| `Get-VergeTask` | List running/completed tasks |
| `Wait-VergeTask` | Wait for task completion |
| `Stop-VergeTask` | Cancel a running task |

### Backup/DR Cmdlets (9)
| Cmdlet | Description |
|--------|-------------|
| `Get-VergeSnapshotProfile` | List snapshot profiles |
| `New-VergeSnapshotProfile` | Create snapshot profile |
| `Set-VergeSnapshotProfile` | Modify snapshot profile |
| `Get-VergeCloudSnapshot` | List system snapshots |
| `New-VergeCloudSnapshot` | Create system snapshot |
| `Restore-VergeCloudSnapshot` | Restore from system snapshot |
| `Get-VergeSiteSync` | List outgoing site syncs |
| `Start-VergeSiteSync` | Start site sync |
| `Stop-VergeSiteSync` | Stop site sync |
| `Get-VergeSiteSyncIncoming` | List incoming site syncs |
| `Get-VergeSite` | List configured sites |

### Total Cmdlet Count: ~110

---

## 10. Milestones and Timeline

### Phase 1: Foundation (~40 cmdlets)
**Goal:** Core VM lifecycle management comparable to basic PowerCLI functionality

- [ ] Project setup (repo, CI/CD, test framework)
- [ ] Core API wrapper implementation with session management
- [ ] Connection cmdlets (`Connect-VergeOS`, `Disconnect-VergeOS`, `Get-VergeConnection`, `Set-VergeConnection`)
- [ ] Core VM operations (`Get-VergeVM`, `New-VergeVM`, `Set-VergeVM`, `Remove-VergeVM`, `Start-VergeVM`, `Stop-VergeVM`, `Restart-VergeVM`)
- [ ] VM components (`Get-VergeDrive`, `Get-VergeNIC`, `Get-VergeVMSnapshot`)
- [ ] Basic Network operations (`Get-VergeNetwork`, `Get-VergeNetworkRule`)
- [ ] System visibility (`Get-VergeCluster`, `Get-VergeNode`, `Get-VergeStorageTier`)
- [ ] Task management (`Get-VergeTask`, `Wait-VergeTask`) - essential for async operations
- [ ] Unit test framework and initial integration tests

### Phase 2: Extended VM & Network (~70 cmdlets)
**Goal:** Full VM and network management with snapshots and firewall

- [ ] VM lifecycle (`New-VergeVMClone`, `Move-VergeVM`, `Suspend-VergeVM`)
- [ ] VM drives (`New-VergeDrive`, `Set-VergeDrive`, `Remove-VergeDrive`)
- [ ] VM NICs (`New-VergeNIC`, `Set-VergeNIC`, `Remove-VergeNIC`)
- [ ] Snapshots (`New-VergeVMSnapshot`, `Remove-VergeVMSnapshot`, `Restore-VergeVMSnapshot`)
- [ ] Network lifecycle (`New-VergeNetwork`, `Set-VergeNetwork`, `Remove-VergeNetwork`, `Start-VergeNetwork`, `Stop-VergeNetwork`)
- [ ] Firewall rules (`New-VergeNetworkRule`, `Set-VergeNetworkRule`, `Remove-VergeNetworkRule`, `Invoke-VergeNetworkApply`)
- [ ] DHCP/DNS (`Get-VergeNetworkHost`, `New-VergeNetworkHost`, `Get-VergeDNSZone`, `Get-VergeDNSRecord`)
- [ ] User management (`Get-VergeUser`, `New-VergeUser`, `Set-VergeUser`, `Remove-VergeUser`, `Enable-VergeUser`, `Disable-VergeUser`)
- [ ] Monitoring basics (`Get-VergeAlarm`, `Set-VergeAlarm`)
- [ ] Tab completion implementation
- [ ] Help documentation (Comment-Based Help)

### Phase 3: Multi-Tenancy & Storage (~90 cmdlets)
**Goal:** Complete tenant and NAS/volume management

- [ ] Tenant operations (`Get-VergeTenant`, `New-VergeTenant`, `Set-VergeTenant`, `Remove-VergeTenant`)
- [ ] Tenant lifecycle (`Start-VergeTenant`, `Stop-VergeTenant`, `New-VergeTenantClone`)
- [ ] Tenant context (`Enter-VergeTenant`, `Exit-VergeTenant`, `Get-VergeTenantSnapshot`)
- [ ] Volumes (`Get-VergeVolume`, `New-VergeVolume`, `Set-VergeVolume`, `Remove-VergeVolume`)
- [ ] Volume snapshots (`Get-VergeVolumeSnapshot`, `New-VergeVolumeSnapshot`, `Remove-VergeVolumeSnapshot`)
- [ ] File shares (`Get-VergeCIFSShare`, `New-VergeCIFSShare`, `Get-VergeNFSShare`, `New-VergeNFSShare`)
- [ ] Groups/Permissions (`Get-VergeGroup`, `New-VergeGroup`, `Get-VergeGroupMember`, `Add-VergeGroupMember`, `Remove-VergeGroupMember`, `Get-VergePermission`, `Grant-VergePermission`, `Revoke-VergePermission`)
- [ ] Node operations (`Enable-VergeNodeMaintenance`, `Disable-VergeNodeMaintenance`, `Restart-VergeNode`)

### Phase 4: Backup/DR & Advanced (~110 cmdlets)
**Goal:** Complete API coverage including DR, advanced networking, and monitoring

- [ ] Snapshot profiles (`Get-VergeSnapshotProfile`, `New-VergeSnapshotProfile`, `Set-VergeSnapshotProfile`)
- [ ] Cloud snapshots (`Get-VergeCloudSnapshot`, `New-VergeCloudSnapshot`, `Restore-VergeCloudSnapshot`)
- [ ] Site sync (`Get-VergeSiteSync`, `Start-VergeSiteSync`, `Stop-VergeSiteSync`, `Get-VergeSiteSyncIncoming`, `Get-VergeSite`)
- [ ] VPN (`Get-VergeIPSec`, `Get-VergeWireGuard`)
- [ ] Advanced VM (`Get-VergeDevice`, `Get-VergeVMConsole`, `Invoke-VergeVMScript`)
- [ ] Node hardware (`Get-VergeNodeDriver`, `Get-VergeNodeGPU`, `Get-VergeNodePCIDevice`, `Get-VergeNodeUSBDevice`)
- [ ] API keys (`Get-VergeAPIKey`, `New-VergeAPIKey`, `Remove-VergeAPIKey`)
- [ ] Logging (`Get-VergeLog`, `Get-VergeAlarmHistory`)
- [ ] Media management (`Get-VergeMediaSource`)

### Phase 5: Polish and Release
**Goal:** Production-ready module with complete documentation

- [ ] Complete documentation with full cmdlet help
- [ ] PowerShell Gallery publishing
- [ ] Performance optimization (parallel operations, caching)
- [ ] Community example scripts library
- [ ] Comprehensive integration testing suite
- [ ] CI/CD pipeline for releases
- [ ] v1.0 Release

---

## 11. Risks and Mitigations

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| API changes in future VergeOS versions | High | Medium | Version detection, graceful degradation, clear error messages |
| ~~PowerShell 5.1 compatibility issues~~ | N/A | N/A | **Resolved: PS7+ only, no 5.1 support** |
| Performance issues with large environments | Medium | Low | Implement pagination, async operations, caching |
| Insufficient test coverage | High | Medium | Establish coverage requirements, automated testing in CI |
| Scope creep delaying release | High | High | Strict P0/P1 focus for v1.0, defer P2+ to v1.1 |

---

## 12. Open Questions

| # | Question | Owner | Status |
|---|----------|-------|--------|
| 1 | ~~Official module name?~~ | Product | **Resolved: PSVergeOS** |
| 2 | ~~Will this be open-source or proprietary?~~ | Legal/Product | **Resolved: Open Source, MIT License** |
| 3 | ~~Minimum supported VergeOS version?~~ | Engineering | **Resolved: VergeOS 26.0+** |
| 4 | ~~Should we support Windows PowerShell 5.1?~~ | Engineering | **Resolved: PowerShell 7+ only** |
| 5 | ~~Integration with existing verge-cli tool?~~ | Engineering | **Resolved: No integration planned** |
| 6 | ~~Customer beta program participants?~~ | Sales/CS | **Resolved: No beta program** |
| 7 | ~~PowerShell Gallery publisher account ownership?~~ | IT/Product | **Resolved: Verge Engineering** |

---

## 13. Appendix

### A. PowerCLI to PSVergeOS Command Mapping

| VMware PowerCLI | PSVergeOS | Notes |
|-----------------|---------------|-------|
| **Connection** | | |
| `Connect-VIServer` | `Connect-VergeOS` | |
| `Disconnect-VIServer` | `Disconnect-VergeOS` | |
| **Virtual Machines** | | |
| `Get-VM` | `Get-VergeVM` | |
| `New-VM` | `New-VergeVM` | |
| `Set-VM` | `Set-VergeVM` | |
| `Remove-VM` | `Remove-VergeVM` | |
| `Start-VM` | `Start-VergeVM` | |
| `Stop-VM` | `Stop-VergeVM` | |
| `Stop-VM -Kill` | `Stop-VergeVM -Force` | |
| `Restart-VM` | `Restart-VergeVM` | |
| `Suspend-VM` | `Suspend-VergeVM` | |
| `Move-VM` | `Move-VergeVM` | VM migration |
| `New-Snapshot` | `New-VergeVMSnapshot` | |
| `Get-Snapshot` | `Get-VergeVMSnapshot` | |
| `Remove-Snapshot` | `Remove-VergeVMSnapshot` | |
| `Set-VM -Snapshot` | `Restore-VergeVMSnapshot` | Revert to snapshot |
| **VM Hardware** | | |
| `Get-HardDisk` | `Get-VergeDrive` | |
| `New-HardDisk` | `New-VergeDrive` | |
| `Set-HardDisk` | `Set-VergeDrive` | |
| `Remove-HardDisk` | `Remove-VergeDrive` | |
| `Get-NetworkAdapter` | `Get-VergeNIC` | |
| `New-NetworkAdapter` | `New-VergeNIC` | |
| `Set-NetworkAdapter` | `Set-VergeNIC` | |
| `Remove-NetworkAdapter` | `Remove-VergeNIC` | |
| `Get-CDDrive` | `Get-VergeDrive -Type CD` | |
| `Set-CDDrive` | `Set-VergeDrive -Media` | |
| `Get-VMGuest` | `Invoke-VergeVMScript` | Guest agent ops |
| **Networking** | | |
| `Get-VirtualNetwork` | `Get-VergeNetwork` | |
| `New-VirtualNetwork` | `New-VergeNetwork` | |
| `Set-VirtualNetwork` | `Set-VergeNetwork` | |
| `Remove-VirtualNetwork` | `Remove-VergeNetwork` | |
| `Get-VDPortGroup` | `Get-VergeNetwork` | Different model |
| `Get-VMHostNetworkAdapter` | `Get-VergeNIC -Node` | Node NICs |
| **Storage** | | |
| `Get-Datastore` | `Get-VergeStorageTier` | Different concept |
| `Get-DatastoreCluster` | `Get-VergeStorageTier` | Tiers replace datastores |
| N/A | `Get-VergeVolume` | NAS volumes |
| N/A | `Get-VergeCIFSShare` | SMB shares |
| N/A | `Get-VergeNFSShare` | NFS exports |
| **Infrastructure** | | |
| `Get-Cluster` | `Get-VergeCluster` | |
| `Get-VMHost` | `Get-VergeNode` | |
| `Set-VMHost -MaintenanceMode` | `Enable-VergeNodeMaintenance` | |
| `Set-VMHost -MaintenanceMode:$false` | `Disable-VergeNodeMaintenance` | |
| `Restart-VMHost` | `Restart-VergeNode` | |
| **Users & Permissions** | | |
| `Get-VIPermission` | `Get-VergePermission` | |
| `New-VIPermission` | `Grant-VergePermission` | |
| `Remove-VIPermission` | `Revoke-VergePermission` | |
| `Get-VIRole` | `Get-VergeGroup` | Groups replace roles |
| **Tenants (Resource Pools)** | | |
| `Get-ResourcePool` | `Get-VergeTenant` | Tenants are more powerful |
| N/A | `Start-VergeTenant` | Boot tenant environment |
| N/A | `Stop-VergeTenant` | Shutdown tenant |
| N/A | `New-VergeTenantClone` | Clone entire tenant |
| **Tasks** | | |
| `Get-Task` | `Get-VergeTask` | |
| `Wait-Task` | `Wait-VergeTask` | |
| `Stop-Task` | `Stop-VergeTask` | |
| **Alarms** | | |
| `Get-AlarmDefinition` | `Get-VergeAlarm` | |
| N/A | `Set-VergeAlarm` | Snooze/acknowledge |

### B. VergeOS API Reference

- **Base URL:** `https://{server}/api/v4/`
- **Authentication:** Bearer token or session cookie
- **Total Endpoints:** 336 documented endpoints
- **Key Resource Categories:**
  - `/vms`, `/vm_actions` - Virtual machine management and lifecycle
  - `/machine_drives`, `/machine_nics`, `/machine_snapshots` - VM hardware
  - `/vnets`, `/vnet_actions`, `/vnet_rules` - Network management
  - `/volumes`, `/volume_snapshots`, `/volume_*_shares` - NAS/storage
  - `/clusters`, `/nodes`, `/node_*` - Infrastructure
  - `/tenants`, `/tenant_actions` - Multi-tenancy
  - `/users`, `/groups`, `/permissions` - Identity management
  - `/tasks`, `/alarms`, `/logs` - Operations and monitoring
  - `/site_syncs_*`, `/cloud_snapshots`, `/snapshot_profiles` - Backup/DR

### C. References

- [VergeOS API Documentation](https://docs.verge.io/knowledge-base/category/api/)
- [VergeOS API Helper Script](https://docs.verge.io/knowledge-base/api-helper-script/)
- [verge-cli GitHub Repository](https://github.com/verge-io/verge-cli)
- [VergeOS Terraform Provider](https://docs.verge.io/product-guide/tools-integrations/terraform-provider/)
- [VMware PowerCLI Reference](https://developer.vmware.com/powercli)

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 0.1 | 2026-01-22 | [Your Name] | Initial draft |