<#
.SYNOPSIS
    Examples for VM lifecycle management operations.

.DESCRIPTION
    This script demonstrates common VM management tasks:
    - Listing and filtering VMs
    - Starting, stopping, and restarting VMs
    - Cloning VMs
    - Working with snapshots
    - Bulk operations using the pipeline

.NOTES
    Prerequisites:
    - PowerShell 7.4 or later
    - PSVergeOS module installed
    - Connected to a VergeOS system
#>

# Import the module
Import-Module PSVergeOS

#region Listing VMs
# ============================================================================
# QUERYING VMs WITH FILTERS
# ============================================================================

# List all VMs
Get-VergeVM

# List only running VMs
Get-VergeVM -PowerState Running

# List stopped VMs
Get-VergeVM -PowerState Stopped

# Find VMs by name (exact match)
Get-VergeVM -Name "WebServer01"

# Find VMs by name pattern (wildcard)
Get-VergeVM -Name "Web*"
Get-VergeVM -Name "*-Prod-*"

# Get a specific VM by its key
Get-VergeVM -Key 123

# Filter VMs by cluster
Get-VergeVM -Cluster "Production"

# Combine filters: stopped VMs with "Test" in the name
Get-VergeVM -Name "*Test*" -PowerState Stopped

# Advanced filtering with Where-Object
# VMs with more than 4GB RAM
Get-VergeVM | Where-Object { $_.RAM -gt 4096 }

# VMs running on a specific node
Get-VergeVM | Where-Object { $_.Node -eq "node01" }

# VMs without a snapshot profile
Get-VergeVM | Where-Object { -not $_.SnapshotProfile }

#endregion

#region VM Power Operations
# ============================================================================
# STARTING, STOPPING, AND RESTARTING VMs
# ============================================================================

# Start a VM by name
Start-VergeVM -Name "WebServer01"

# Start and return the VM object
$vm = Start-VergeVM -Name "WebServer01" -PassThru

# Start all VMs matching a pattern
Start-VergeVM -Name "Web*"

# Stop a VM gracefully (sends ACPI shutdown signal)
Stop-VergeVM -Name "WebServer01"

# Force stop a VM (hard power off - use with caution)
Stop-VergeVM -Name "WebServer01" -Force

# Stop without confirmation prompt (for scripts)
Stop-VergeVM -Name "WebServer01" -Confirm:$false

# Restart a VM (graceful reboot)
Restart-VergeVM -Name "WebServer01"

# Force restart (hard reset)
Restart-VergeVM -Name "WebServer01" -Force

#endregion

#region Pipeline Operations
# ============================================================================
# BULK OPERATIONS USING THE PIPELINE
# ============================================================================

# Start all stopped VMs in Production cluster
Get-VergeVM -Cluster "Production" -PowerState Stopped | Start-VergeVM

# Stop all test VMs
Get-VergeVM -Name "*-Test-*" | Stop-VergeVM -Confirm:$false

# Restart all web servers
Get-VergeVM -Name "Web*" | Restart-VergeVM

# Start VMs and collect results
$startedVMs = Get-VergeVM -Name "App*" -PowerState Stopped | Start-VergeVM -PassThru
$startedVMs | Format-Table Name, PowerState, Node

#endregion

#region VM Snapshots
# ============================================================================
# WORKING WITH VM SNAPSHOTS
# ============================================================================

# List snapshots for a VM
Get-VergeVMSnapshot -VMName "WebServer01"

# Create a snapshot
New-VergeVMSnapshot -VMName "WebServer01" -Name "Before-Update"

# Create snapshot with description
New-VergeVMSnapshot -VMName "WebServer01" -Name "Pre-Patch" -Description "Snapshot before applying security patches"

# Create snapshot and return the object
$snapshot = New-VergeVMSnapshot -VMName "WebServer01" -Name "Checkpoint" -PassThru

# Restore a VM to a snapshot
Restore-VergeVMSnapshot -VMName "WebServer01" -SnapshotName "Before-Update"

# Remove a snapshot
Remove-VergeVMSnapshot -VMName "WebServer01" -SnapshotName "Old-Snapshot"

# Remove all snapshots older than 7 days
$cutoffDate = (Get-Date).AddDays(-7)
Get-VergeVMSnapshot -VMName "WebServer01" |
    Where-Object { $_.Created -lt $cutoffDate } |
    Remove-VergeVMSnapshot -Confirm:$false

#endregion

#region Cloning VMs
# ============================================================================
# CLONING VMs FOR TEMPLATES AND TESTING
# ============================================================================

# Clone a VM with a new name
New-VergeVMClone -SourceVM "Template-Ubuntu22" -Name "NewWebServer"

# Clone and return the new VM
$clonedVM = New-VergeVMClone -SourceVM "Template-Windows2022" -Name "DevServer01" -PassThru

# Clone and start immediately
New-VergeVMClone -SourceVM "Template-CentOS" -Name "TestServer" -PowerOn

# Clone with new description
New-VergeVMClone -SourceVM "BaseTemplate" -Name "ProjectX-Server" -Description "Server for Project X deployment"

#endregion

#region Maintenance Workflows
# ============================================================================
# COMMON MAINTENANCE WORKFLOWS
# ============================================================================

# Workflow: Pre-maintenance snapshot, apply changes, verify
$vmName = "WebServer01"

# 1. Create pre-maintenance snapshot
$snapshot = New-VergeVMSnapshot -VMName $vmName -Name "Pre-Maintenance-$(Get-Date -Format 'yyyyMMdd')" -PassThru
Write-Host "Snapshot created: $($snapshot.Name)"

# 2. Perform maintenance (your changes here)
# ...

# 3. If something goes wrong, restore the snapshot
# Restore-VergeVMSnapshot -VMName $vmName -SnapshotName $snapshot.Name

# Workflow: Shutdown all VMs for maintenance window
$vmsToShutdown = Get-VergeVM -Cluster "Production" -PowerState Running

# Record which VMs were running
$vmsToShutdown | Select-Object Name, Key | Export-Csv "running-vms-backup.csv"

# Gracefully stop all
$vmsToShutdown | Stop-VergeVM -Confirm:$false

# After maintenance, restart them
Import-Csv "running-vms-backup.csv" | ForEach-Object {
    Start-VergeVM -Key $_.Key
}

#endregion

#region Reporting
# ============================================================================
# GENERATING VM REPORTS
# ============================================================================

# Export VM inventory to CSV
Get-VergeVM |
    Select-Object Name, PowerState, CPUCores, @{N='RAM_GB';E={$_.RAM/1024}}, Cluster, Node, Created |
    Export-Csv "vm-inventory.csv" -NoTypeInformation

# Generate summary report
$vms = Get-VergeVM
$report = [PSCustomObject]@{
    TotalVMs      = $vms.Count
    Running       = ($vms | Where-Object PowerState -eq 'Running').Count
    Stopped       = ($vms | Where-Object PowerState -eq 'Stopped').Count
    TotalCPU      = ($vms | Measure-Object -Property CPUCores -Sum).Sum
    TotalRAM_GB   = [math]::Round(($vms | Measure-Object -Property RAM -Sum).Sum / 1024, 2)
}
$report | Format-List

# Find VMs without snapshot protection
Get-VergeVM |
    Where-Object { -not $_.SnapshotProfile } |
    Select-Object Name, Cluster, Created |
    Format-Table

# List large VMs (8+ cores or 32GB+ RAM)
Get-VergeVM |
    Where-Object { $_.CPUCores -ge 8 -or $_.RAM -ge 32768 } |
    Select-Object Name, CPUCores, @{N='RAM_GB';E={$_.RAM/1024}}, PowerState |
    Format-Table

#endregion
