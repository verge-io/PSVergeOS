<#
.SYNOPSIS
    Examples for VergeOS system management and monitoring.

.DESCRIPTION
    This script demonstrates system administration tasks:
    - Checking VergeOS version information
    - Managing clusters (list, create, modify, remove)
    - Managing nodes
    - Node maintenance operations
    - System statistics and dashboard overview
    - System settings management
    - License information
    - Hardware device discovery (PCI, USB, GPU)

.NOTES
    Prerequisites:
    - PowerShell 7.4 or later
    - PSVergeOS module installed
    - Connected to a VergeOS system
#>

# Import the module
Import-Module PSVergeOS

#region Version Information
# ============================================================================
# GETTING VERGEOS VERSION INFORMATION
# ============================================================================

# Get version information from the connected system
Get-VergeVersion

# Display version in a formatted way
$version = Get-VergeVersion
Write-Host "Connected to VergeOS $($version.VergeOSVersion)"
Write-Host "  Kernel: $($version.KernelVersion)"
Write-Host "  vSAN:   $($version.vSANVersion)"
Write-Host "  QEMU:   $($version.QEMUVersion)"

# Use version in scripts for compatibility checks
$ver = Get-VergeVersion
$majorVersion = [int]($ver.VergeOSVersion -split '\.')[0]
if ($majorVersion -lt 26) {
    Write-Warning "This script requires VergeOS 26.0 or later"
}

#endregion

#region Cluster Management
# ============================================================================
# MANAGING CLUSTERS
# ============================================================================

# List all clusters
Get-VergeCluster

# Get a specific cluster by name
Get-VergeCluster -Name "Production"

# View cluster resource utilization
Get-VergeCluster | Format-Table Name, Status, OnlineNodes, UsedCores, OnlineCores, UsedRAM, OnlineRAM

# Check cluster capacity
Get-VergeCluster | ForEach-Object {
    $cpuPct = if ($_.OnlineCores -gt 0) { [math]::Round(($_.UsedCores / $_.OnlineCores) * 100, 1) } else { 0 }
    $ramPct = if ($_.OnlineRAM -gt 0) { [math]::Round(($_.UsedRAM / $_.OnlineRAM) * 100, 1) } else { 0 }

    [PSCustomObject]@{
        Cluster    = $_.Name
        Status     = $_.Status
        CPUUsed    = "$($_.UsedCores)/$($_.OnlineCores) ($cpuPct%)"
        RAMUsed    = "$([math]::Round($_.UsedRAM/1024, 1))/$([math]::Round($_.OnlineRAM/1024, 1)) GB ($ramPct%)"
        VMs        = $_.RunningMachines
    }
} | Format-Table

# Get cluster details including CPU type
Get-VergeCluster | Select-Object Name, DefaultCPUType, RecommendedCPUType, NestedVirtualization

#endregion

#region Cluster Creation and Modification
# ============================================================================
# CREATING AND MODIFYING CLUSTERS
# ============================================================================

# Create a basic cluster
# New-VergeCluster -Name "Development" -Description "Development workloads"

# Create a cluster with compute enabled and resource limits
# New-VergeCluster -Name "Production" -Description "Production VMs" -Compute -MaxRAMPerVM 131072 -MaxCoresPerVM 32

# Create a cluster optimized for nested virtualization
# New-VergeCluster -Name "Lab-Cluster" -Compute -NestedVirtualization -AllowNestedVirtMigration $true -PassThru

# Create a cluster with specific CPU type and power settings
# New-VergeCluster -Name "HPC-Cluster" -Compute `
#     -DefaultCPUType "EPYC-Milan" `
#     -EnergyPerfPolicy Performance `
#     -ScalingGovernor Performance `
#     -PassThru

# Create a cluster for GPU workloads
# New-VergeCluster -Name "GPU-Cluster" -Compute `
#     -NestedVirtualization `
#     -AllowVGPUMigration `
#     -Description "GPU passthrough workloads" `
#     -PassThru

# Modify cluster settings - update resource limits
# Set-VergeCluster -Name "Production" -MaxRAMPerVM 262144 -MaxCoresPerVM 64

# Enable nested virtualization on existing cluster
# Set-VergeCluster -Name "Development" -NestedVirtualization $true

# Change cluster CPU type
# Set-VergeCluster -Name "Production" -DefaultCPUType "Cascadelake-Server"

# Update power management settings
# Set-VergeCluster -Name "Production" -EnergyPerfPolicy BalancePerformance -ScalingGovernor OnDemand

# Rename a cluster
# Set-VergeCluster -Name "OldName" -NewName "NewName" -PassThru

# Modify cluster using pipeline
# Get-VergeCluster -Name "Development" | Set-VergeCluster -Description "Updated description" -PassThru

# Disable a cluster
# Set-VergeCluster -Name "Maintenance-Cluster" -Enabled $false

# Update storage settings
# Set-VergeCluster -Name "Production" -StorageCachePerNode 8192 -StorageHugepages $true

# Configure temperature monitoring
# Set-VergeCluster -Name "Production" -MaxCoreTemp 85 -CriticalCoreTemp 95 -MaxCoreTempWarnPercent 10

#endregion

#region Cluster Deletion
# ============================================================================
# REMOVING CLUSTERS
# ============================================================================

# Remove a cluster by name (requires confirmation)
# Remove-VergeCluster -Name "Test-Cluster"

# Remove without confirmation prompt
# Remove-VergeCluster -Name "Temp-Cluster" -Confirm:$false

# Remove using pipeline
# Get-VergeCluster -Name "Temp-*" | Remove-VergeCluster

# Preview what would be deleted (WhatIf)
# Remove-VergeCluster -Name "Development" -WhatIf

# Safe cluster removal workflow
$clusterName = "Cluster-To-Remove"

# 1. Check if cluster has nodes or VMs
$cluster = Get-VergeCluster -Name $clusterName
if ($cluster) {
    Write-Host "Cluster: $($cluster.Name)"
    Write-Host "  Total Nodes: $($cluster.TotalNodes)"
    Write-Host "  Running VMs: $($cluster.RunningMachines)"

    if ($cluster.TotalNodes -gt 0) {
        Write-Warning "Cluster has $($cluster.TotalNodes) nodes. Reassign nodes before deletion."
        # Get-VergeNode -Cluster $clusterName
    }
    elseif ($cluster.RunningMachines -gt 0) {
        Write-Warning "Cluster has $($cluster.RunningMachines) running VMs. Stop/move VMs before deletion."
    }
    else {
        Write-Host "Cluster can be safely removed." -ForegroundColor Green
        # Remove-VergeCluster -Name $clusterName -Confirm:$false
    }
}

#endregion

#region Node Management
# ============================================================================
# MANAGING NODES
# ============================================================================

# List all nodes
Get-VergeNode

# List nodes with key information
Get-VergeNode | Format-Table Name, Status, Cluster, Cores, @{N='RAM_GB';E={[math]::Round($_.RAM/1024,1)}}, MaintenanceMode

# Find a specific node
Get-VergeNode -Name "node1"

# Filter nodes by cluster
Get-VergeNode -Cluster "Production"

# Find nodes in maintenance mode
Get-VergeNode -MaintenanceMode $true

# Check node health
Get-VergeNode | ForEach-Object {
    [PSCustomObject]@{
        Node          = $_.Name
        Status        = $_.Status
        NeedsRestart  = $_.NeedsRestart
        RestartReason = $_.RestartReason
        IOMMU         = $_.IOMMU
        Maintenance   = $_.MaintenanceMode
    }
} | Format-Table

# Get node version information
Get-VergeNode | Select-Object Name, VergeOSVersion, KernelVersion, vSANVersion

# Check for nodes needing restart
$needRestart = Get-VergeNode | Where-Object NeedsRestart
if ($needRestart) {
    Write-Warning "The following nodes need to be restarted:"
    $needRestart | Format-Table Name, RestartReason
}

#endregion

#region Node Maintenance Operations
# ============================================================================
# NODE MAINTENANCE MODE AND REBOOT
# ============================================================================

# Enable maintenance mode on a node (migrates VMs off)
# Enable-VergeNodeMaintenance -Name "node2"

# Preview what would happen (WhatIf)
Enable-VergeNodeMaintenance -Name "node2" -WhatIf

# Disable maintenance mode (allows VMs to run again)
# Disable-VergeNodeMaintenance -Name "node2"

# Preview disabling maintenance
Disable-VergeNodeMaintenance -Name "node2" -WhatIf

# Perform a maintenance reboot (safe reboot with VM migration)
# Restart-VergeNode -Name "node2"

# Preview maintenance reboot
Restart-VergeNode -Name "node2" -WhatIf

# Pipeline: Find and put specific nodes in maintenance
# Get-VergeNode -Cluster "Development" | Enable-VergeNodeMaintenance

# Maintenance workflow example
$nodeName = "node2"

# Check current state
$node = Get-VergeNode -Name $nodeName
Write-Host "Node: $($node.Name)"
Write-Host "  Status: $($node.Status)"
Write-Host "  Maintenance Mode: $($node.MaintenanceMode)"
Write-Host "  Running VMs on this node: Check via Get-VergeVM"

# To perform maintenance:
# 1. Enable maintenance mode (VMs will migrate)
# Enable-VergeNodeMaintenance -Name $nodeName

# 2. Wait for VMs to migrate off
# while ((Get-VergeNode -Name $nodeName).Status -ne 'Maintenance') {
#     Start-Sleep -Seconds 10
# }

# 3. Perform reboot if needed
# Restart-VergeNode -Name $nodeName

# 4. When done, disable maintenance
# Disable-VergeNodeMaintenance -Name $nodeName

#endregion

#region System Statistics
# ============================================================================
# SYSTEM DASHBOARD AND STATISTICS
# ============================================================================

# Get overall system statistics
Get-VergeSystemStatistics

# Quick health check
$stats = Get-VergeSystemStatistics
Write-Host "`nSystem Health Overview"
Write-Host "======================"
Write-Host "VMs:       $($stats.VMsOnline) running / $($stats.VMsTotal) total"
Write-Host "Nodes:     $($stats.NodesOnline) online / $($stats.NodesTotal) total"
Write-Host "Networks:  $($stats.NetworksOnline) online / $($stats.NetworksTotal) total"
Write-Host "Tenants:   $($stats.TenantsOnline) online / $($stats.TenantsTotal) total"
Write-Host "Alarms:    $($stats.AlarmsTotal) ($($stats.AlarmsWarning) warnings, $($stats.AlarmsError) errors)"

# Check for issues
$stats = Get-VergeSystemStatistics
$issues = @()

if ($stats.NodesOnline -lt $stats.NodesTotal) {
    $issues += "WARN: Not all nodes online ($($stats.NodesOnline)/$($stats.NodesTotal))"
}
if ($stats.ClustersOnline -lt $stats.ClustersTotal) {
    $issues += "WARN: Not all clusters online ($($stats.ClustersOnline)/$($stats.ClustersTotal))"
}
if ($stats.AlarmsError -gt 0) {
    $issues += "ERROR: $($stats.AlarmsError) error alarm(s) present"
}
if ($stats.ClusterTiersError -gt 0) {
    $issues += "ERROR: $($stats.ClusterTiersError) storage tier(s) in error state"
}

if ($issues.Count -eq 0) {
    Write-Host "`n[OK] All systems healthy" -ForegroundColor Green
} else {
    Write-Host "`n[ATTENTION] Issues detected:" -ForegroundColor Yellow
    $issues | ForEach-Object { Write-Host "  - $_" }
}

# Generate health report
$stats = Get-VergeSystemStatistics
[PSCustomObject]@{
    Timestamp        = Get-Date
    Server           = $stats.Server
    VMsRunning       = $stats.VMsOnline
    VMsTotal         = $stats.VMsTotal
    NodesOnline      = $stats.NodesOnline
    NodesTotal       = $stats.NodesTotal
    StorageTiers     = $stats.StorageTiersTotal
    ActiveAlarms     = $stats.AlarmsTotal
    AlarmWarnings    = $stats.AlarmsWarning
    AlarmErrors      = $stats.AlarmsError
} | Format-List

#endregion

#region System Settings
# ============================================================================
# SYSTEM SETTINGS
# ============================================================================

# List all system settings
Get-VergeSystemSetting | Format-Table Key, Value, DefaultValue, IsModified

# Find specific settings
Get-VergeSystemSetting -Key "cloud_name"
Get-VergeSystemSetting -Key "max*"

# Find settings that have been modified from defaults
Get-VergeSystemSetting | Where-Object IsModified | Format-Table Key, Value, DefaultValue

# Common settings to check
$importantSettings = @(
    'cloud_name'
    'cloud_domain'
    'ntp_servers'
    'max_connections'
    'default_tenant_network'
)

Write-Host "`nImportant System Settings:"
Write-Host "=========================="
foreach ($key in $importantSettings) {
    $setting = Get-VergeSystemSetting -Key $key
    if ($setting) {
        Write-Host "$($key): $($setting.Value)"
    }
}

# Check network settings
Get-VergeSystemSetting -Key "*network*" | Format-Table Key, Value
Get-VergeSystemSetting -Key "*mtu*" | Format-Table Key, Value

# Check storage-related settings
Get-VergeSystemSetting -Key "*sync*" | Format-Table Key, Value
Get-VergeSystemSetting -Key "*snap*" | Format-Table Key, Value

#endregion

#region License Information
# ============================================================================
# LICENSE MANAGEMENT
# ============================================================================

# Get license information
Get-VergeLicense

# Check license validity
$license = Get-VergeLicense | Select-Object -First 1
if ($license) {
    Write-Host "`nLicense Information"
    Write-Host "==================="
    Write-Host "Name:        $($license.Name)"
    Write-Host "Valid:       $($license.IsValid)"
    Write-Host "Valid Until: $($license.ValidUntil)"
    Write-Host "Auto-Renew:  $($license.AutoRenewal)"

    # Check days until expiration
    if ($license.ValidUntil) {
        $daysRemaining = ($license.ValidUntil - (Get-Date)).Days
        if ($daysRemaining -lt 30) {
            Write-Warning "License expires in $daysRemaining days!"
        } else {
            Write-Host "Days Until Expiration: $daysRemaining"
        }
    }
}

# List all licenses with expiration dates
Get-VergeLicense | Select-Object Name, IsValid, ValidFrom, ValidUntil, AutoRenewal | Format-Table

#endregion

#region Node Drivers
# ============================================================================
# NODE DRIVERS (GPU, NETWORK, ETC.)
# ============================================================================

# List all custom drivers
Get-VergeNodeDriver

# List drivers for a specific node
Get-VergeNodeDriver -Node "node1"

# Filter by driver status
Get-VergeNodeDriver -Status Installed
Get-VergeNodeDriver -Status Verifying
Get-VergeNodeDriver -Status Error

# Find NVIDIA drivers
Get-VergeNodeDriver -DriverName "*nvidia*"

# Check driver status across all nodes
Get-VergeNodeDriver | Format-Table Node, DriverName, Status, StatusInfo

# Pipeline: Get drivers from a specific node
Get-VergeNode -Name "node1" | Get-VergeNodeDriver

#endregion

#region Node Hardware Devices
# ============================================================================
# HARDWARE DEVICE DISCOVERY (PCI, USB, GPU)
# ============================================================================

# List all PCI devices
Get-VergeNodeDevice -DeviceType PCI | Format-Table Node, Name, Class, Vendor -AutoSize

# List all USB devices
Get-VergeNodeDevice -DeviceType USB | Format-Table Node, Name, Vendor, USBVersion

# List all GPUs (display controllers)
Get-VergeNodeDevice -DeviceType GPU | Format-Table Node, Name, Vendor

# Get devices for a specific node
Get-VergeNodeDevice -Node "node1" -DeviceType PCI | Format-Table Name, Class

# Filter by device class
Get-VergeNodeDevice -DeviceType PCI -DeviceClass "Network controller" |
    Format-Table Node, Name, Vendor, Driver

Get-VergeNodeDevice -DeviceType PCI -DeviceClass "Mass storage" |
    Format-Table Node, Name, Vendor, Driver

# Pipeline: Get GPU devices from specific nodes
Get-VergeNode -Name "node1" | Get-VergeNodeDevice -DeviceType GPU

# Find devices with SR-IOV support
Get-VergeNodeDevice -DeviceType PCI |
    Where-Object { $_.SRIOVTotalVFs -gt 0 } |
    Format-Table Node, Name, SRIOVTotalVFs, SRIOVNumVFs

# Hardware inventory report
Write-Host "`nHardware Summary"
Write-Host "================"
$pci = Get-VergeNodeDevice -DeviceType PCI
$usb = Get-VergeNodeDevice -DeviceType USB
$gpu = Get-VergeNodeDevice -DeviceType GPU

Write-Host "PCI Devices: $($pci.Count)"
Write-Host "USB Devices: $($usb.Count)"
Write-Host "GPUs:        $($gpu.Count)"

# Group PCI devices by class
Write-Host "`nPCI Devices by Class:"
Get-VergeNodeDevice -DeviceType PCI |
    Group-Object Class |
    Sort-Object Count -Descending |
    Format-Table @{N='Class';E={$_.Name}}, Count

#endregion

#region System Health Report
# ============================================================================
# COMPREHENSIVE SYSTEM HEALTH REPORT
# ============================================================================

function Get-VergeSystemHealthReport {
    <#
    .SYNOPSIS
        Generates a comprehensive system health report.
    #>

    $report = [ordered]@{}

    # Version info
    $version = Get-VergeVersion
    $report['Version'] = $version.VergeOSVersion
    $report['Server'] = $version.Server

    # Cluster health
    $clusters = Get-VergeCluster
    $report['Clusters'] = "$($clusters.Count) total"
    $report['ClusterStatus'] = ($clusters | ForEach-Object { "$($_.Name): $($_.Status)" }) -join ', '

    # Node health
    $nodes = Get-VergeNode
    $onlineNodes = ($nodes | Where-Object Status -eq 'Running').Count
    $report['Nodes'] = "$onlineNodes/$($nodes.Count) online"
    $needRestart = ($nodes | Where-Object NeedsRestart).Count
    $report['NodesNeedingRestart'] = $needRestart

    # Statistics
    $stats = Get-VergeSystemStatistics
    $report['VMs'] = "$($stats.VMsOnline)/$($stats.VMsTotal) running"
    $report['Networks'] = "$($stats.NetworksOnline)/$($stats.NetworksTotal) online"
    $report['Tenants'] = "$($stats.TenantsOnline)/$($stats.TenantsTotal) online"
    $report['Alarms'] = "$($stats.AlarmsTotal) ($($stats.AlarmsError) errors)"

    # License
    $license = Get-VergeLicense | Select-Object -First 1
    if ($license) {
        $daysRemaining = if ($license.ValidUntil) { ($license.ValidUntil - (Get-Date)).Days } else { 'N/A' }
        $report['LicenseValid'] = $license.IsValid
        $report['LicenseExpires'] = "$daysRemaining days"
    }

    # Output
    [PSCustomObject]$report
}

# Generate the report
Get-VergeSystemHealthReport | Format-List

# Export health report to file
# Get-VergeSystemHealthReport | Export-Csv "health-report-$(Get-Date -Format 'yyyyMMdd').csv" -NoTypeInformation

#endregion
