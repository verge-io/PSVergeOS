<#
.SYNOPSIS
    Examples for generating RVtools-style inventory reports from VergeOS.

.DESCRIPTION
    This script demonstrates how to create comprehensive infrastructure
    inventory reports similar to RVtools for VMware environments.

    Includes examples for:
    - Quick summary reports
    - Detailed VM inventory with hardware details
    - Network configuration reports
    - Storage capacity planning
    - Multi-worksheet Excel exports
    - Custom CSV reports
    - HTML reports for sharing

.NOTES
    Prerequisites:
    - PowerShell 7.4 or later
    - PSVergeOS module installed
    - Connected to a VergeOS system
    - (Optional) ImportExcel module for Excel exports
#>

# Import the module
Import-Module PSVergeOS

#region Quick Summary
# ============================================================================
# QUICK INVENTORY SUMMARY
# ============================================================================

# Get a quick summary of all resources
Get-VergeInventory -Summary

# Display summary in a formatted list
Get-VergeInventory -Summary | Format-List

# Custom summary display
$summary = Get-VergeInventory -Summary
Write-Host "`n=== VergeOS Infrastructure Summary ==="
Write-Host "Server:       $($summary.Server)"
Write-Host "Generated:    $($summary.GeneratedAt)"
Write-Host ""
Write-Host "Virtual Machines"
Write-Host "  Total:      $($summary.VMsTotal)"
Write-Host "  Running:    $($summary.VMsRunning)"
Write-Host "  Stopped:    $($summary.VMsStopped)"
Write-Host "  Total vCPU: $($summary.TotalCPUCores)"
Write-Host "  Total RAM:  $($summary.TotalRAMGB) GB"
Write-Host "  Total Disk: $($summary.TotalDiskGB) GB"
Write-Host ""
Write-Host "Networks"
Write-Host "  Total:      $($summary.NetworksTotal)"
Write-Host "  Running:    $($summary.NetworksRunning)"
Write-Host ""
Write-Host "Storage"
Write-Host "  Tiers:      $($summary.StorageTiers)"
Write-Host "  Capacity:   $($summary.StorageCapacityGB) GB"
Write-Host "  Used:       $($summary.StorageUsedGB) GB"
Write-Host ""
Write-Host "Infrastructure"
Write-Host "  Clusters:   $($summary.ClustersTotal)"
Write-Host "  Nodes:      $($summary.NodesTotal) ($($summary.NodesOnline) online)"
Write-Host "  Tenants:    $($summary.TenantsTotal) ($($summary.TenantsOnline) online)"
Write-Host "  Snapshots:  $($summary.SnapshotsTotal)"
Write-Host ""

#endregion

#region Filtered Inventory
# ============================================================================
# FILTERED INVENTORY QUERIES
# ============================================================================

# Get only VM inventory
$vmInventory = Get-VergeInventory -ResourceType VMs
$vmInventory.VMs | Format-Table Name, PowerState, CPUCores, RAMGB, TotalDiskGB, Cluster

# Get only network inventory
$netInventory = Get-VergeInventory -ResourceType Networks
$netInventory.Networks | Format-Table Name, Type, PowerState, NetworkAddress, DHCPEnabled

# Get VMs and Networks together
$inventory = Get-VergeInventory -ResourceType VMs, Networks
Write-Host "VMs: $($inventory.VMs.Count), Networks: $($inventory.Networks.Count)"

# Exclude powered-off VMs
$runningVMs = Get-VergeInventory -ResourceType VMs -IncludePoweredOff:$false
Write-Host "Running VMs: $($runningVMs.VMs.Count)"

# Include snapshots in the inventory
$withSnapshots = Get-VergeInventory -ResourceType VMs, Snapshots -IncludeSnapshots
Write-Host "VMs (including snapshot VMs): $($withSnapshots.VMs.Count)"
Write-Host "Snapshots: $($withSnapshots.Snapshots.Count)"

#endregion

#region CSV Export
# ============================================================================
# CSV EXPORT EXAMPLES
# ============================================================================

# Export full inventory to separate CSV files
$inventory = Get-VergeInventory
$datestamp = Get-Date -Format 'yyyyMMdd'

# Export each resource type to its own CSV
$inventory.VMs | Export-Csv -Path "VergeOS_VMs_$datestamp.csv" -NoTypeInformation
$inventory.Networks | Export-Csv -Path "VergeOS_Networks_$datestamp.csv" -NoTypeInformation
$inventory.Storage | Export-Csv -Path "VergeOS_Storage_$datestamp.csv" -NoTypeInformation
$inventory.Nodes | Export-Csv -Path "VergeOS_Nodes_$datestamp.csv" -NoTypeInformation
$inventory.Clusters | Export-Csv -Path "VergeOS_Clusters_$datestamp.csv" -NoTypeInformation

Write-Host "CSV files exported with prefix 'VergeOS_*_$datestamp.csv'"

# Quick single-file VM export
Get-VergeInventory -ResourceType VMs |
    Select-Object -ExpandProperty VMs |
    Export-Csv -Path "VM_Report.csv" -NoTypeInformation

#endregion

#region Excel Export
# ============================================================================
# EXCEL EXPORT (Requires ImportExcel module)
# ============================================================================

# Check if ImportExcel is available
if (Get-Module -ListAvailable -Name ImportExcel) {
    Import-Module ImportExcel

    $inventory = Get-VergeInventory
    $excelPath = "VergeOS_Inventory_$(Get-Date -Format 'yyyyMMdd').xlsx"

    # Export to Excel with multiple worksheets (RVtools-style)
    # VMs worksheet
    $inventory.VMs | Export-Excel -Path $excelPath -WorksheetName "vInfo" -AutoSize -FreezeTopRow -BoldTopRow

    # Networks worksheet
    $inventory.Networks | Export-Excel -Path $excelPath -WorksheetName "vNetwork" -AutoSize -FreezeTopRow -BoldTopRow

    # Storage worksheet
    $inventory.Storage | Export-Excel -Path $excelPath -WorksheetName "vDisk" -AutoSize -FreezeTopRow -BoldTopRow

    # Nodes worksheet
    $inventory.Nodes | Export-Excel -Path $excelPath -WorksheetName "vHost" -AutoSize -FreezeTopRow -BoldTopRow

    # Clusters worksheet
    $inventory.Clusters | Export-Excel -Path $excelPath -WorksheetName "vCluster" -AutoSize -FreezeTopRow -BoldTopRow

    # Tenants worksheet
    $inventory.Tenants | Export-Excel -Path $excelPath -WorksheetName "vTenant" -AutoSize -FreezeTopRow -BoldTopRow

    # VM Snapshots worksheet (individual VM point-in-time snapshots)
    $inventory.VMSnapshots | Export-Excel -Path $excelPath -WorksheetName "vSnapshot" -AutoSize -FreezeTopRow -BoldTopRow

    # Cloud Snapshots worksheet (system-wide snapshots with immutability)
    $inventory.CloudSnapshots | Export-Excel -Path $excelPath -WorksheetName "vCloudSnapshot" -AutoSize -FreezeTopRow -BoldTopRow

    # Summary worksheet with conditional formatting
    $inventory.Summary | Export-Excel -Path $excelPath -WorksheetName "Summary" -AutoSize

    Write-Host "Excel report exported to: $excelPath"

    # Alternative: Export with styling and charts
    # $inventory.VMs | Export-Excel -Path $excelPath -WorksheetName "VMs" `
    #     -AutoSize -FreezeTopRow -BoldTopRow `
    #     -ConditionalText $(
    #         New-ConditionalText -Text "Running" -BackgroundColor LightGreen
    #         New-ConditionalText -Text "Stopped" -BackgroundColor LightPink
    #     )
}
else {
    Write-Host "ImportExcel module not installed. Install with: Install-Module ImportExcel"
    Write-Host "Falling back to CSV export..."
}

#endregion

#region Custom Reports
# ============================================================================
# CUSTOM REPORT EXAMPLES
# ============================================================================

# VM Capacity Report
Write-Host "`n=== VM Capacity Report ==="
$inventory = Get-VergeInventory -ResourceType VMs, Clusters

# VMs by cluster
$inventory.VMs | Group-Object Cluster | ForEach-Object {
    [PSCustomObject]@{
        Cluster   = $_.Name
        VMCount   = $_.Count
        TotalCPU  = ($_.Group | Measure-Object CPUCores -Sum).Sum
        TotalRAM  = [math]::Round(($_.Group | Measure-Object RAMGB -Sum).Sum, 1)
        TotalDisk = [math]::Round(($_.Group | Measure-Object TotalDiskGB -Sum).Sum, 1)
    }
} | Format-Table

# Largest VMs
Write-Host "`n=== Top 10 Largest VMs by RAM ==="
$inventory.VMs |
    Sort-Object RAMGB -Descending |
    Select-Object -First 10 Name, RAMGB, CPUCores, TotalDiskGB |
    Format-Table

# VMs without guest agent
Write-Host "`n=== VMs without Guest Agent ==="
$inventory.VMs |
    Where-Object { -not $_.GuestAgent -and $_.PowerState -eq 'Running' } |
    Select-Object Name, PowerState, OSFamily |
    Format-Table

# Storage Utilization Report
Write-Host "`n=== Storage Tier Utilization ==="
$storageInventory = Get-VergeInventory -ResourceType Storage
$storageInventory.Storage | ForEach-Object {
    $bar = '#' * [math]::Floor($_.UsedPercent / 5)
    $empty = '-' * (20 - $bar.Length)
    Write-Host ("Tier {0}: [{1}{2}] {3,5:N1}% ({4:N0} GB / {5:N0} GB)" -f
        $_.Tier, $bar, $empty, $_.UsedPercent, $_.UsedGB, $_.CapacityGB)
}

# Network Summary
Write-Host "`n=== Network Summary by Type ==="
$netInventory = Get-VergeInventory -ResourceType Networks
$netInventory.Networks |
    Group-Object Type |
    Select-Object @{N='Type';E={$_.Name}}, @{N='Count';E={$_.Count}},
                  @{N='Running';E={($_.Group | Where-Object PowerState -eq 'Running').Count}} |
    Format-Table

# VM Snapshot Age Report
Write-Host "`n=== VM Snapshots Older Than 30 Days ==="
$snapInventory = Get-VergeInventory -ResourceType VMSnapshots
$thirtyDaysAgo = (Get-Date).AddDays(-30)
$snapInventory.VMSnapshots |
    Where-Object { $_.Created -and $_.Created -lt $thirtyDaysAgo } |
    Select-Object VMName, Name, Created,
                  @{N='AgeDays';E={[math]::Round(((Get-Date) - $_.Created).TotalDays)}} |
    Sort-Object AgeDays -Descending |
    Format-Table

# Cloud Snapshot Immutability Report
Write-Host "`n=== Cloud Snapshot Immutability Status ==="
$cloudSnapInventory = Get-VergeInventory -ResourceType CloudSnapshots
$cloudSnapInventory.CloudSnapshots |
    Select-Object Name, Created, Immutable, ImmutableStatus, ImmutableLockExpires, RemoteSync |
    Format-Table

#endregion

#region Scheduled Reports
# ============================================================================
# SCHEDULED REPORT GENERATION
# ============================================================================

# Function to generate and save a full inventory report
function Export-VergeInventoryReport {
    param(
        [string]$OutputPath = ".",
        [switch]$Excel,
        [switch]$CSV,
        [switch]$JSON
    )

    $datestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $inventory = Get-VergeInventory

    if ($CSV) {
        $csvPath = Join-Path $OutputPath "VergeOS_Inventory_$datestamp"
        New-Item -ItemType Directory -Path $csvPath -Force | Out-Null

        $inventory.VMs | Export-Csv "$csvPath/VMs.csv" -NoTypeInformation
        $inventory.Networks | Export-Csv "$csvPath/Networks.csv" -NoTypeInformation
        $inventory.Storage | Export-Csv "$csvPath/Storage.csv" -NoTypeInformation
        $inventory.Nodes | Export-Csv "$csvPath/Nodes.csv" -NoTypeInformation
        $inventory.Clusters | Export-Csv "$csvPath/Clusters.csv" -NoTypeInformation
        $inventory.Tenants | Export-Csv "$csvPath/Tenants.csv" -NoTypeInformation
        $inventory.VMSnapshots | Export-Csv "$csvPath/VMSnapshots.csv" -NoTypeInformation
        $inventory.CloudSnapshots | Export-Csv "$csvPath/CloudSnapshots.csv" -NoTypeInformation
        $inventory.Summary | Export-Csv "$csvPath/Summary.csv" -NoTypeInformation

        Write-Host "CSV report exported to: $csvPath"
    }

    if ($JSON) {
        $jsonPath = Join-Path $OutputPath "VergeOS_Inventory_$datestamp.json"
        $inventory | ConvertTo-Json -Depth 10 | Set-Content $jsonPath
        Write-Host "JSON report exported to: $jsonPath"
    }

    if ($Excel -and (Get-Module -ListAvailable -Name ImportExcel)) {
        Import-Module ImportExcel
        $excelPath = Join-Path $OutputPath "VergeOS_Inventory_$datestamp.xlsx"

        $inventory.VMs | Export-Excel -Path $excelPath -WorksheetName "VMs" -AutoSize -FreezeTopRow -BoldTopRow
        $inventory.Networks | Export-Excel -Path $excelPath -WorksheetName "Networks" -AutoSize -FreezeTopRow -BoldTopRow
        $inventory.Storage | Export-Excel -Path $excelPath -WorksheetName "Storage" -AutoSize -FreezeTopRow -BoldTopRow
        $inventory.Nodes | Export-Excel -Path $excelPath -WorksheetName "Nodes" -AutoSize -FreezeTopRow -BoldTopRow
        $inventory.Clusters | Export-Excel -Path $excelPath -WorksheetName "Clusters" -AutoSize -FreezeTopRow -BoldTopRow
        $inventory.Tenants | Export-Excel -Path $excelPath -WorksheetName "Tenants" -AutoSize -FreezeTopRow -BoldTopRow
        $inventory.VMSnapshots | Export-Excel -Path $excelPath -WorksheetName "VMSnapshots" -AutoSize -FreezeTopRow -BoldTopRow
        $inventory.CloudSnapshots | Export-Excel -Path $excelPath -WorksheetName "CloudSnapshots" -AutoSize -FreezeTopRow -BoldTopRow

        Write-Host "Excel report exported to: $excelPath"
    }

    return $inventory.Summary
}

# Usage examples:
# Export-VergeInventoryReport -CSV -OutputPath "/reports"
# Export-VergeInventoryReport -Excel -JSON -OutputPath "/reports"

#endregion

#region Using Existing Cmdlets
# ============================================================================
# BUILDING CUSTOM INVENTORY WITH EXISTING CMDLETS
# ============================================================================

# For users who want more control, here's how to build inventory manually
# using the existing Get-* cmdlets

# Quick VM inventory using Get-VergeVM
$vms = Get-VergeVM | ForEach-Object {
    $drives = Get-VergeDrive -VMKey $_.Key
    $nics = Get-VergeNIC -VMKey $_.Key

    [PSCustomObject]@{
        Name         = $_.Name
        PowerState   = $_.PowerState
        CPUs         = $_.CPUCores
        RAMGB        = [math]::Round($_.RAM / 1024, 1)
        DiskCount    = $drives.Count
        TotalDiskGB  = [math]::Round(($drives | Measure-Object SizeGB -Sum).Sum, 1)
        NICCount     = $nics.Count
        Networks     = ($nics.NetworkName | Sort-Object -Unique) -join ', '
        Cluster      = $_.Cluster
        Node         = $_.Node
    }
}
$vms | Format-Table

# Network inventory with NIC counts
$networks = Get-VergeNetwork | ForEach-Object {
    $netKey = $_.Key
    # Count NICs on this network (if needed)
    [PSCustomObject]@{
        Name        = $_.Name
        Type        = $_.Type
        Status      = $_.PowerState
        Network     = $_.NetworkAddress
        Gateway     = $_.Gateway
        DHCP        = if ($_.DHCPEnabled) { "$($_.DHCPStart) - $($_.DHCPStop)" } else { "Disabled" }
        MTU         = $_.MTU
    }
}
$networks | Format-Table

# Quick cluster capacity check
Get-VergeCluster | ForEach-Object {
    $cpuPct = if ($_.OnlineCores -gt 0) { [math]::Round(($_.UsedCores / $_.OnlineCores) * 100, 1) } else { 0 }
    $ramPct = if ($_.OnlineRAM -gt 0) { [math]::Round(($_.UsedRAM / $_.OnlineRAM) * 100, 1) } else { 0 }

    [PSCustomObject]@{
        Cluster    = $_.Name
        Nodes      = "$($_.OnlineNodes)/$($_.TotalNodes)"
        VMs        = $_.RunningMachines
        CPU        = "$($_.UsedCores)/$($_.OnlineCores) cores ($cpuPct%)"
        RAM        = "$([math]::Round($_.UsedRAM/1024))/$([math]::Round($_.OnlineRAM/1024)) GB ($ramPct%)"
    }
} | Format-Table -AutoSize

#endregion
