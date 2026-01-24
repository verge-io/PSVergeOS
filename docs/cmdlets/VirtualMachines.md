# Virtual Machine Cmdlets

Cmdlets for managing virtual machine lifecycle, configuration, and hardware.

## Overview

Virtual machine cmdlets provide complete control over VM operations including creation, power management, cloning, snapshots, and hardware configuration.

## VM Lifecycle Cmdlets

### Get-VergeVM

Retrieves virtual machines from VergeOS.

**Syntax:**
```powershell
Get-VergeVM [-Name <String>] [-PowerState <String>] [-Cluster <String>] [-IncludeSnapshots]
Get-VergeVM -Key <Int32>
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Name` | String | No | VM name (supports wildcards `*` and `?`) |
| `-Key` | Int32 | No | Unique VM identifier |
| `-PowerState` | String | No | Filter by state: Running, Stopped, etc. |
| `-Cluster` | String | No | Filter by cluster name |
| `-IncludeSnapshots` | Switch | No | Include VM snapshots in results |

**Examples:**

```powershell
# List all VMs
Get-VergeVM

# Find VMs by name pattern
Get-VergeVM -Name "Web*"

# Get running VMs only
Get-VergeVM -PowerState Running

# Combine filters
Get-VergeVM -Name "Prod-*" -PowerState Stopped -Cluster "Production"

# Get VM by key
Get-VergeVM -Key 123

# Advanced filtering with Where-Object
Get-VergeVM | Where-Object { $_.RAM -gt 8192 }
```

**Output Properties:**

| Property | Description |
|----------|-------------|
| `Key` | Unique identifier |
| `Name` | VM display name |
| `PowerState` | Current power state (Running, Stopped, etc.) |
| `CPUCores` | Allocated CPU cores |
| `RAM` | Allocated memory in MB |
| `Cluster` | Cluster name |
| `Node` | Current node |
| `OSFamily` | Operating system type |
| `UEFI` | UEFI boot enabled |
| `GuestAgent` | Guest agent enabled |

---

### New-VergeVM

Creates a new virtual machine.

**Syntax:**
```powershell
New-VergeVM -Name <String> [-Description <String>] [-CPUCores <Int32>] [-RAM <Int32>]
    [-OSFamily <String>] [-UEFI] [-SecureBoot] [-GuestAgent] [-Cluster <String>]
    [-BootOrder <String>] [-PassThru]
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Name` | String | Yes | VM name |
| `-Description` | String | No | VM description |
| `-CPUCores` | Int32 | No | Number of CPU cores (default: 1) |
| `-RAM` | Int32 | No | Memory in MB (default: 1024) |
| `-OSFamily` | String | No | Linux, Windows, Other |
| `-UEFI` | Switch | No | Enable UEFI boot |
| `-SecureBoot` | Switch | No | Enable Secure Boot (requires UEFI) |
| `-GuestAgent` | Switch | No | Enable guest agent support |
| `-Cluster` | String | No | Target cluster |
| `-BootOrder` | String | No | Boot device order |
| `-PassThru` | Switch | No | Return created VM |

**Examples:**

```powershell
# Create a basic VM
New-VergeVM -Name "TestServer"

# Create a configured VM
New-VergeVM -Name "WebServer01" -CPUCores 4 -RAM 8192 -OSFamily Linux -UEFI -GuestAgent

# Create and return the VM object
$vm = New-VergeVM -Name "Database01" -CPUCores 8 -RAM 32768 -PassThru
```

---

### Set-VergeVM

Modifies virtual machine configuration.

**Syntax:**
```powershell
Set-VergeVM -Name <String> [-NewName <String>] [-Description <String>] [-CPUCores <Int32>]
    [-RAM <Int32>] [-GuestAgent <Boolean>] [-PassThru]
Set-VergeVM -VM <Object> [parameters...]
```

**Examples:**

```powershell
# Change VM resources
Set-VergeVM -Name "WebServer01" -CPUCores 8 -RAM 16384

# Rename a VM
Set-VergeVM -Name "OldName" -NewName "NewName"

# Pipeline usage
Get-VergeVM -Name "TestVM" | Set-VergeVM -Description "Updated description"
```

---

### Remove-VergeVM

Deletes a virtual machine.

**Syntax:**
```powershell
Remove-VergeVM -Name <String> [-Force] [-Confirm]
Remove-VergeVM -VM <Object> [-Force] [-Confirm]
```

**Examples:**

```powershell
# Remove with confirmation
Remove-VergeVM -Name "OldServer"

# Remove without confirmation (use with caution)
Remove-VergeVM -Name "TempVM" -Confirm:$false

# Remove multiple VMs
Get-VergeVM -Name "Test-*" | Remove-VergeVM -Confirm:$false
```

---

### Start-VergeVM

Powers on a virtual machine.

**Syntax:**
```powershell
Start-VergeVM -Name <String> [-PassThru]
Start-VergeVM -VM <Object> [-PassThru]
```

**Examples:**

```powershell
# Start a VM
Start-VergeVM -Name "WebServer01"

# Start and return VM object
$vm = Start-VergeVM -Name "WebServer01" -PassThru

# Start all stopped VMs in a cluster
Get-VergeVM -Cluster "Production" -PowerState Stopped | Start-VergeVM
```

---

### Stop-VergeVM

Powers off a virtual machine.

**Syntax:**
```powershell
Stop-VergeVM -Name <String> [-Force] [-Confirm]
Stop-VergeVM -VM <Object> [-Force] [-Confirm]
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Name` | String | Yes* | VM name |
| `-VM` | Object | Yes* | VM object from pipeline |
| `-Force` | Switch | No | Hard power-off (skip graceful shutdown) |

**Examples:**

```powershell
# Graceful shutdown
Stop-VergeVM -Name "WebServer01"

# Force power off
Stop-VergeVM -Name "UnresponsiveVM" -Force

# Stop all dev VMs
Get-VergeVM -Name "Dev-*" | Stop-VergeVM -Confirm:$false
```

---

### Restart-VergeVM

Reboots a virtual machine.

**Syntax:**
```powershell
Restart-VergeVM -Name <String> [-Force]
Restart-VergeVM -VM <Object> [-Force]
```

**Examples:**

```powershell
# Graceful reboot
Restart-VergeVM -Name "WebServer01"

# Force reset
Restart-VergeVM -Name "FrozenVM" -Force
```

---

### Move-VergeVM

Migrates a VM to a different node.

**Syntax:**
```powershell
Move-VergeVM -Name <String> -Node <String> [-PassThru]
```

**Examples:**

```powershell
# Migrate VM to specific node
Move-VergeVM -Name "WebServer01" -Node "node2"

# Migrate and wait for completion
$vm = Move-VergeVM -Name "Database01" -Node "node3" -PassThru
```

---

### New-VergeVMClone

Creates a copy of an existing VM.

**Syntax:**
```powershell
New-VergeVMClone -SourceVM <String> -Name <String> [-Description <String>] [-PowerOn] [-PassThru]
```

**Examples:**

```powershell
# Clone a VM
New-VergeVMClone -SourceVM "Template-Ubuntu22" -Name "NewWebServer"

# Clone and start immediately
New-VergeVMClone -SourceVM "Template-Windows" -Name "DevServer" -PowerOn -PassThru
```

---

### Get-VergeVMConsole

Gets the console URL for a VM.

**Syntax:**
```powershell
Get-VergeVMConsole -Name <String>
Get-VergeVMConsole -VM <Object>
```

**Examples:**

```powershell
# Get console URL
$url = Get-VergeVMConsole -Name "WebServer01"
Start-Process $url
```

## Snapshot Cmdlets

### New-VergeVMSnapshot

Creates a point-in-time snapshot of a VM.

**Syntax:**
```powershell
New-VergeVMSnapshot -VMName <String> -Name <String> [-Description <String>] [-PassThru]
```

**Examples:**

```powershell
# Create a snapshot
New-VergeVMSnapshot -VMName "WebServer01" -Name "Pre-Update"

# Create with description
New-VergeVMSnapshot -VMName "Database01" -Name "Before-Migration" -Description "Snapshot before schema migration"

# Batch snapshot
Get-VergeVM -Name "Prod-*" | ForEach-Object {
    New-VergeVMSnapshot -VMName $_.Name -Name "Daily-$(Get-Date -Format 'yyyyMMdd')"
}
```

---

### Get-VergeVMSnapshot

Lists snapshots for a VM.

**Syntax:**
```powershell
Get-VergeVMSnapshot -VMName <String>
```

**Examples:**

```powershell
# List all snapshots
Get-VergeVMSnapshot -VMName "WebServer01"

# Find old snapshots
Get-VergeVMSnapshot -VMName "WebServer01" | Where-Object { $_.Created -lt (Get-Date).AddDays(-7) }
```

---

### Restore-VergeVMSnapshot

Restores a VM to a previous snapshot state.

**Syntax:**
```powershell
Restore-VergeVMSnapshot -VMName <String> -SnapshotName <String> [-Confirm]
```

**Examples:**

```powershell
# Restore to snapshot
Restore-VergeVMSnapshot -VMName "WebServer01" -SnapshotName "Pre-Update"
```

---

### Remove-VergeVMSnapshot

Deletes a VM snapshot.

**Syntax:**
```powershell
Remove-VergeVMSnapshot -VMName <String> -SnapshotName <String> [-Confirm]
```

**Examples:**

```powershell
# Remove a specific snapshot
Remove-VergeVMSnapshot -VMName "WebServer01" -SnapshotName "Old-Snapshot"

# Remove old snapshots
$cutoff = (Get-Date).AddDays(-30)
Get-VergeVMSnapshot -VMName "WebServer01" |
    Where-Object { $_.Created -lt $cutoff } |
    Remove-VergeVMSnapshot -Confirm:$false
```

## Hardware Cmdlets

### Get-VergeDrive

Lists drives attached to a VM.

**Syntax:**
```powershell
Get-VergeDrive -VM <String>
```

---

### New-VergeDrive

Adds a drive to a VM.

**Syntax:**
```powershell
New-VergeDrive -VM <Object> -Name <String> [-SizeGB <Int32>] [-Tier <Int32>]
    [-Interface <String>] [-Media <String>] [-PassThru]
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-VM` | Object | Yes | VM name or object |
| `-Name` | String | Yes | Drive name |
| `-SizeGB` | Int32 | No | Size in gigabytes |
| `-Tier` | Int32 | No | Storage tier (1=fast, 3=capacity) |
| `-Interface` | String | No | virtio-scsi, sata, ide |
| `-Media` | String | No | disk, cdrom |

**Examples:**

```powershell
# Add a data drive
New-VergeDrive -VM "WebServer01" -Name "Data" -SizeGB 100 -Tier 1 -Interface virtio-scsi

# Add a CD-ROM drive
New-VergeDrive -VM "WebServer01" -Name "ISO" -Media cdrom
```

---

### Set-VergeDrive

Modifies drive configuration.

**Syntax:**
```powershell
Set-VergeDrive -Drive <Object> [-MediaSource <Int32>] [-PassThru]
```

**Examples:**

```powershell
# Mount an ISO to a CD-ROM drive
$cdrom = Get-VergeDrive -VM "Server01" | Where-Object Media -eq 'cdrom'
Set-VergeDrive -Drive $cdrom -MediaSource $isoKey
```

---

### Remove-VergeDrive

Removes a drive from a VM.

---

### Get-VergeNIC

Lists network interfaces attached to a VM.

---

### New-VergeNIC

Adds a network interface to a VM.

**Syntax:**
```powershell
New-VergeNIC -VM <Object> -NetworkName <String> [-Name <String>] [-Interface <String>] [-PassThru]
```

**Examples:**

```powershell
# Add a NIC to a VM
New-VergeNIC -VM "WebServer01" -NetworkName "Internal" -Interface virtio
```

---

### Set-VergeNIC

Modifies NIC configuration.

---

### Remove-VergeNIC

Removes a network interface from a VM.

## Common Workflows

### Pre-Maintenance Snapshot

```powershell
$vmName = "Production-DB"

# Create snapshot before maintenance
$snapshot = New-VergeVMSnapshot -VMName $vmName -Name "Pre-Maintenance-$(Get-Date -Format 'yyyyMMdd')" -PassThru
Write-Host "Created snapshot: $($snapshot.Name)"

# Perform maintenance...

# If something goes wrong, restore
# Restore-VergeVMSnapshot -VMName $vmName -SnapshotName $snapshot.Name
```

### Bulk VM Shutdown

```powershell
# Record running VMs
$runningVMs = Get-VergeVM -Cluster "Production" -PowerState Running
$runningVMs | Select-Object Name, Key | Export-Csv "running-vms.csv"

# Gracefully stop all
$runningVMs | Stop-VergeVM -Confirm:$false

# After maintenance, restart
Import-Csv "running-vms.csv" | ForEach-Object { Start-VergeVM -Key $_.Key }
```

### VM Inventory Report

```powershell
Get-VergeVM | Select-Object Name, PowerState, CPUCores,
    @{N='RAM_GB';E={$_.RAM/1024}}, Cluster, Node |
    Export-Csv "vm-inventory.csv" -NoTypeInformation
```
