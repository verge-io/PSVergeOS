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

## Tag Categories

Tag categories organize tags and define which resource types can be tagged.

### Get-VergeTagCategory

Lists tag categories.

**Syntax:**
```powershell
Get-VergeTagCategory [-Name <String>] [-Key <Int32>]
```

**Examples:**

```powershell
# List all tag categories
Get-VergeTagCategory

# Get a specific category
Get-VergeTagCategory -Name "Environment"

# View which resources can be tagged
Get-VergeTagCategory | Format-Table Name, TaggableVMs, TaggableNetworks, TaggableTenants, SingleTagSelection
```

---

### New-VergeTagCategory

Creates a new tag category.

**Syntax:**
```powershell
New-VergeTagCategory -Name <String> [-Description <String>] [-SingleTagSelection]
    [-TaggableVMs] [-TaggableNetworks] [-TaggableTenants] [-TaggableNodes]
    [-TaggableClusters] [-TaggableUsers] [-TaggableGroups] [-PassThru]
```

**Examples:**

```powershell
# Create environment category (single tag per resource)
New-VergeTagCategory -Name "Environment" `
    -Description "Deployment environment" `
    -TaggableVMs -TaggableNetworks -TaggableTenants `
    -SingleTagSelection

# Create application category (multiple tags allowed)
New-VergeTagCategory -Name "Application" `
    -Description "Application tier tags" `
    -TaggableVMs -PassThru
```

---

### Set-VergeTagCategory

Modifies a tag category.

**Syntax:**
```powershell
Set-VergeTagCategory -Name <String> [-Description <String>] [-TaggableVMs <Boolean>]
    [-TaggableNetworks <Boolean>] [-PassThru]
```

**Examples:**

```powershell
# Enable additional resource types
Set-VergeTagCategory -Name "Environment" -TaggableNodes $true -TaggableClusters $true

# Update description
Set-VergeTagCategory -Name "Application" -Description "Application and service identification"
```

---

### Remove-VergeTagCategory

Deletes a tag category.

> **Note:** Category must have no tags before deletion.

**Syntax:**
```powershell
Remove-VergeTagCategory -Name <String> [-Confirm:$false]
```

**Examples:**

```powershell
# Remove an empty category
Remove-VergeTagCategory -Name "UnusedCategory"

# Force removal without confirmation
Remove-VergeTagCategory -Name "OldCategory" -Confirm:$false
```

## Tags

Tags are labels within categories that can be assigned to resources.

### Get-VergeTag

Lists tags.

**Syntax:**
```powershell
Get-VergeTag [-Name <String>] [-Key <Int32>] [-Category <Object>]
```

**Examples:**

```powershell
# List all tags
Get-VergeTag

# List tags in a category
Get-VergeTag -Category "Environment"

# Find tags by name pattern
Get-VergeTag -Name "Prod*"

# Pipeline from category
Get-VergeTagCategory -Name "Environment" | Get-VergeTag

# View tags with category info
Get-VergeTag | Format-Table Name, CategoryName, Description
```

---

### New-VergeTag

Creates a new tag within a category.

**Syntax:**
```powershell
New-VergeTag -Name <String> -Category <Object> [-Description <String>] [-PassThru]
```

**Examples:**

```powershell
# Create environment tags
New-VergeTag -Name "Production" -Category "Environment" -Description "Production workloads"
New-VergeTag -Name "Development" -Category "Environment" -Description "Development workloads"

# Create and return the tag
$tag = New-VergeTag -Name "WebServer" -Category "Application" -PassThru
```

---

### Set-VergeTag

Modifies a tag.

**Syntax:**
```powershell
Set-VergeTag -Name <String> [-Description <String>] [-PassThru]
```

**Examples:**

```powershell
# Update description
Set-VergeTag -Name "Production" -Description "Production environment - critical workloads"
```

---

### Remove-VergeTag

Deletes a tag and all its assignments.

**Syntax:**
```powershell
Remove-VergeTag -Name <String> [-Confirm:$false]
```

**Examples:**

```powershell
# Remove a tag
Remove-VergeTag -Name "OldTag"

# Remove all tags in a category
Get-VergeTag -Category "OldCategory" | Remove-VergeTag -Confirm:$false
```

## Tag Members

Tag members represent the assignment of tags to resources.

### Get-VergeTagMember

Lists tag assignments.

**Syntax:**
```powershell
Get-VergeTagMember -Tag <Object> [-ResourceType <String>]
Get-VergeTagMember -Key <Int32>
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Tag` | Object | Yes* | Tag name, key, or object |
| `-ResourceType` | String | No | Filter by type: vms, vnets, tenants, etc. |
| `-Key` | Int32 | Yes* | Tag member assignment key |

**Examples:**

```powershell
# List all resources with a tag
Get-VergeTagMember -Tag "Production"

# List only VMs with a tag
Get-VergeTagMember -Tag "Production" -ResourceType vms

# Pipeline from tag
Get-VergeTag -Name "Production" | Get-VergeTagMember

# View assignments
Get-VergeTagMember -Tag "Production" | Format-Table TagName, ResourceType, ResourceKey, ResourceRef

# Count resources per tag
Get-VergeTag -Category "Environment" | ForEach-Object {
    $members = Get-VergeTagMember -Tag $_.Name
    [PSCustomObject]@{
        Tag   = $_.Name
        Count = $members.Count
    }
} | Format-Table
```

---

### Add-VergeTagMember

Assigns a tag to a resource.

**Syntax:**
```powershell
Add-VergeTagMember -Tag <Object> -VM <Object> [-PassThru]
Add-VergeTagMember -Tag <Object> -Network <Object> [-PassThru]
Add-VergeTagMember -Tag <Object> -Tenant <Object> [-PassThru]
Add-VergeTagMember -Tag <Object> -ResourceType <String> -ResourceKey <Int32> [-PassThru]
```

**Examples:**

```powershell
# Tag a VM by name
Add-VergeTagMember -Tag "Production" -VM "WebServer01"

# Tag via pipeline from Get-VergeVM
Get-VergeVM -Name "Web*" | Add-VergeTagMember -Tag "WebServer"

# Tag a network
Add-VergeTagMember -Tag "Production" -Network "DMZ"

# Tag a tenant
Add-VergeTagMember -Tag "Production" -Tenant "CustomerA"

# Generic resource tagging
Add-VergeTagMember -Tag "Production" -ResourceType vms -ResourceKey 123

# Bulk tag all VMs in a cluster
Get-VergeVM -Cluster "Prod-Cluster" | ForEach-Object {
    Add-VergeTagMember -Tag "Production" -VM $_
}
```

---

### Remove-VergeTagMember

Removes a tag from a resource.

**Syntax:**
```powershell
Remove-VergeTagMember -Key <Int32> [-Confirm:$false]
Remove-VergeTagMember -Tag <Object> -VM <Object> [-Confirm:$false]
Remove-VergeTagMember -Tag <Object> -Network <Object> [-Confirm:$false]
Remove-VergeTagMember -TagMember <Object> [-Confirm:$false]
```

**Examples:**

```powershell
# Remove tag from VM by specifying both
Remove-VergeTagMember -Tag "Development" -VM "WebServer01"

# Remove by tag member key
Remove-VergeTagMember -Key 42 -Confirm:$false

# Remove all assignments for a tag via pipeline
Get-VergeTagMember -Tag "Staging" | Remove-VergeTagMember -Confirm:$false

# Remove without confirmation
Remove-VergeTagMember -Tag "Production" -Network "OldNetwork" -Confirm:$false
```

## Common Workflows

### Tagging Workflow

```powershell
# 1. Create tag structure
New-VergeTagCategory -Name "Environment" -TaggableVMs -SingleTagSelection
New-VergeTag -Name "Production" -Category "Environment"
New-VergeTag -Name "Development" -Category "Environment"

# 2. Tag resources
Get-VergeVM -Name "Prod-*" | ForEach-Object {
    Add-VergeTagMember -Tag "Production" -VM $_
}

# 3. Query by tag
Get-VergeTagMember -Tag "Production" -ResourceType vms

# 4. Generate report
Get-VergeTag -Category "Environment" | ForEach-Object {
    $count = (Get-VergeTagMember -Tag $_.Name -ResourceType vms).Count
    [PSCustomObject]@{ Environment = $_.Name; VMCount = $count }
} | Format-Table
```

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
