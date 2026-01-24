# System Administration Cmdlets

Cmdlets for managing clusters, nodes, and system settings.

## Overview

System cmdlets provide administration of VergeOS infrastructure including cluster management, node operations, and system configuration.

## Version Information

### Get-VergeVersion

Retrieves VergeOS version information.

**Syntax:**
```powershell
Get-VergeVersion
```

**Examples:**

```powershell
# Get version info
$version = Get-VergeVersion
Write-Host "VergeOS: $($version.VergeOSVersion)"
Write-Host "Kernel: $($version.KernelVersion)"
Write-Host "vSAN: $($version.vSANVersion)"

# Version check in scripts
$ver = Get-VergeVersion
$major = [int]($ver.VergeOSVersion -split '\.')[0]
if ($major -lt 26) {
    Write-Warning "Requires VergeOS 26.0 or later"
}
```

## Cluster Management

### Get-VergeCluster

Lists clusters.

**Syntax:**
```powershell
Get-VergeCluster [-Name <String>]
```

**Examples:**

```powershell
# List all clusters
Get-VergeCluster

# View cluster resources
Get-VergeCluster | Format-Table Name, Status, OnlineNodes, UsedCores, OnlineCores, UsedRAM, OnlineRAM

# Check capacity
Get-VergeCluster | ForEach-Object {
    $cpuPct = [math]::Round(($_.UsedCores / $_.OnlineCores) * 100, 1)
    $ramPct = [math]::Round(($_.UsedRAM / $_.OnlineRAM) * 100, 1)
    [PSCustomObject]@{
        Cluster = $_.Name
        CPUUsed = "$($_.UsedCores)/$($_.OnlineCores) ($cpuPct%)"
        RAMUsed = "$([math]::Round($_.UsedRAM/1024, 1))/$([math]::Round($_.OnlineRAM/1024, 1)) GB ($ramPct%)"
    }
} | Format-Table
```

---

### New-VergeCluster

Creates a new cluster.

**Syntax:**
```powershell
New-VergeCluster -Name <String> [-Description <String>] [-Compute]
    [-NestedVirtualization] [-MaxRAMPerVM <Int32>] [-MaxCoresPerVM <Int32>] [-PassThru]
```

**Examples:**

```powershell
# Create a compute cluster
New-VergeCluster -Name "Production" -Description "Production workloads" -Compute

# Cluster for nested virtualization
New-VergeCluster -Name "Lab" -Compute -NestedVirtualization -PassThru
```

---

### Set-VergeCluster

Modifies cluster settings.

**Examples:**

```powershell
# Update resource limits
Set-VergeCluster -Name "Production" -MaxRAMPerVM 262144 -MaxCoresPerVM 64

# Enable nested virtualization
Set-VergeCluster -Name "Development" -NestedVirtualization $true
```

---

### Remove-VergeCluster

Deletes a cluster.

> **Note:** Cluster must have no nodes or VMs before deletion.

## Node Management

### Get-VergeNode

Lists nodes.

**Syntax:**
```powershell
Get-VergeNode [-Name <String>] [-Cluster <String>] [-MaintenanceMode <Boolean>]
```

**Examples:**

```powershell
# List all nodes
Get-VergeNode

# View node details
Get-VergeNode | Format-Table Name, Status, Cluster, Cores, @{N='RAM_GB';E={[math]::Round($_.RAM/1024,1)}}, MaintenanceMode

# Find nodes needing restart
Get-VergeNode | Where-Object NeedsRestart | Format-Table Name, RestartReason

# Nodes in a specific cluster
Get-VergeNode -Cluster "Production"
```

---

### Enable-VergeNodeMaintenance

Puts a node into maintenance mode, migrating VMs off.

**Syntax:**
```powershell
Enable-VergeNodeMaintenance -Name <String> [-WhatIf]
```

**Examples:**

```powershell
# Preview maintenance
Enable-VergeNodeMaintenance -Name "node2" -WhatIf

# Enable maintenance mode
Enable-VergeNodeMaintenance -Name "node2"
```

---

### Disable-VergeNodeMaintenance

Takes a node out of maintenance mode.

```powershell
Disable-VergeNodeMaintenance -Name "node2"
```

---

### Restart-VergeNode

Performs a safe maintenance reboot with VM migration.

**Syntax:**
```powershell
Restart-VergeNode -Name <String> [-WhatIf]
```

**Examples:**

```powershell
# Preview reboot
Restart-VergeNode -Name "node2" -WhatIf

# Perform maintenance reboot
Restart-VergeNode -Name "node2"
```

## Hardware Discovery

### Get-VergeNodeDevice

Lists hardware devices (PCI, USB, GPU).

**Syntax:**
```powershell
Get-VergeNodeDevice [-Node <String>] -DeviceType <String> [-DeviceClass <String>]
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Node` | String | No | Filter by node |
| `-DeviceType` | String | Yes | PCI, USB, GPU |
| `-DeviceClass` | String | No | Filter by device class |

**Examples:**

```powershell
# List all GPUs
Get-VergeNodeDevice -DeviceType GPU | Format-Table Node, Name, Vendor

# List network controllers
Get-VergeNodeDevice -DeviceType PCI -DeviceClass "Network controller" |
    Format-Table Node, Name, Vendor, Driver

# USB devices on specific node
Get-VergeNodeDevice -Node "node1" -DeviceType USB

# Find SR-IOV capable devices
Get-VergeNodeDevice -DeviceType PCI |
    Where-Object { $_.SRIOVTotalVFs -gt 0 } |
    Format-Table Node, Name, SRIOVTotalVFs
```

---

### Get-VergeNodeDriver

Lists custom drivers installed on nodes.

**Syntax:**
```powershell
Get-VergeNodeDriver [-Node <String>] [-Status <String>]
```

**Examples:**

```powershell
# List all drivers
Get-VergeNodeDriver

# Find NVIDIA drivers
Get-VergeNodeDriver | Where-Object DriverName -like "*nvidia*"

# Check driver status
Get-VergeNodeDriver | Format-Table Node, DriverName, Status, StatusInfo
```

## System Statistics

### Get-VergeSystemStatistics

Retrieves system dashboard statistics.

**Syntax:**
```powershell
Get-VergeSystemStatistics
```

**Examples:**

```powershell
# Quick health check
$stats = Get-VergeSystemStatistics
Write-Host "VMs: $($stats.VMsOnline) running / $($stats.VMsTotal) total"
Write-Host "Nodes: $($stats.NodesOnline) online / $($stats.NodesTotal) total"
Write-Host "Alarms: $($stats.AlarmsTotal) ($($stats.AlarmsError) errors)"

# Check for issues
$stats = Get-VergeSystemStatistics
if ($stats.NodesOnline -lt $stats.NodesTotal) {
    Write-Warning "Not all nodes online"
}
if ($stats.AlarmsError -gt 0) {
    Write-Warning "$($stats.AlarmsError) error alarms present"
}
```

## System Settings

### Get-VergeSystemSetting

Lists system configuration settings.

**Syntax:**
```powershell
Get-VergeSystemSetting [-Key <String>]
```

**Examples:**

```powershell
# List all settings
Get-VergeSystemSetting | Format-Table Key, Value, DefaultValue

# Find specific setting
Get-VergeSystemSetting -Key "cloud_name"

# Find modified settings
Get-VergeSystemSetting | Where-Object IsModified | Format-Table Key, Value, DefaultValue
```

## License Information

### Get-VergeLicense

Retrieves license information.

**Syntax:**
```powershell
Get-VergeLicense
```

**Examples:**

```powershell
# Check license
$license = Get-VergeLicense | Select-Object -First 1
Write-Host "License: $($license.Name)"
Write-Host "Valid: $($license.IsValid)"
Write-Host "Expires: $($license.ValidUntil)"

# Check expiration
if ($license.ValidUntil) {
    $daysLeft = ($license.ValidUntil - (Get-Date)).Days
    if ($daysLeft -lt 30) {
        Write-Warning "License expires in $daysLeft days"
    }
}
```

## Common Workflows

### System Health Check

```powershell
function Get-VergeHealthReport {
    $report = @{}

    # Version
    $version = Get-VergeVersion
    $report['Version'] = $version.VergeOSVersion

    # Clusters
    $clusters = Get-VergeCluster
    $report['Clusters'] = "$($clusters.Count) total"

    # Nodes
    $nodes = Get-VergeNode
    $onlineNodes = ($nodes | Where-Object Status -eq 'Running').Count
    $report['Nodes'] = "$onlineNodes/$($nodes.Count) online"
    $report['NodesNeedRestart'] = ($nodes | Where-Object NeedsRestart).Count

    # Statistics
    $stats = Get-VergeSystemStatistics
    $report['VMs'] = "$($stats.VMsOnline)/$($stats.VMsTotal) running"
    $report['Alarms'] = "$($stats.AlarmsTotal) ($($stats.AlarmsError) errors)"

    [PSCustomObject]$report | Format-List
}

Get-VergeHealthReport
```

### Node Maintenance Workflow

```powershell
$nodeName = "node2"

# 1. Check current state
$node = Get-VergeNode -Name $nodeName
Write-Host "Node: $($node.Name), Status: $($node.Status)"

# 2. Enable maintenance mode
Enable-VergeNodeMaintenance -Name $nodeName

# 3. Wait for VMs to migrate
while ((Get-VergeNode -Name $nodeName).Status -ne 'Maintenance') {
    Write-Host "Waiting for maintenance mode..."
    Start-Sleep -Seconds 10
}

# 4. Perform reboot if needed
Restart-VergeNode -Name $nodeName

# 5. Disable maintenance when done
Disable-VergeNodeMaintenance -Name $nodeName
```

### Hardware Inventory

```powershell
Write-Host "Hardware Summary"
Write-Host "================"
$pci = Get-VergeNodeDevice -DeviceType PCI
$usb = Get-VergeNodeDevice -DeviceType USB
$gpu = Get-VergeNodeDevice -DeviceType GPU

Write-Host "PCI Devices: $($pci.Count)"
Write-Host "USB Devices: $($usb.Count)"
Write-Host "GPUs: $($gpu.Count)"

# Group by class
Write-Host "`nPCI Devices by Class:"
$pci | Group-Object Class | Sort-Object Count -Descending | Format-Table Name, Count
```
