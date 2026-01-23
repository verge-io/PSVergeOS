<#
.SYNOPSIS
    Examples for VergeOS scheduled task management.

.DESCRIPTION
    This script demonstrates task management operations:
    - Listing scheduled automation tasks
    - Filtering tasks by name, status, and state
    - Waiting for task completion
    - Enabling and disabling tasks
    - Creating task monitoring workflows

.NOTES
    Prerequisites:
    - PowerShell 7.4 or later
    - PSVergeOS module installed
    - Connected to a VergeOS system
#>

# Import the module
Import-Module PSVergeOS

#region Listing Tasks
# ============================================================================
# LISTING SCHEDULED TASKS
# ============================================================================

# List all scheduled tasks
Get-VergeTask

# List tasks with key information
Get-VergeTask | Format-Table Name, Type, Enabled, Status, LastRun, NextRun -AutoSize

# Find a specific task by name
Get-VergeTask -Name "Snapshot*"

# Get a task by its key
Get-VergeTask -Key 1

# Filter by status (Running or Idle)
Get-VergeTask -Status Running
Get-VergeTask -Status Idle

# Quick shortcut: Find currently running tasks
Get-VergeTask -Running

# List only enabled tasks
Get-VergeTask | Where-Object Enabled

# List disabled tasks
Get-VergeTask | Where-Object { -not $_.Enabled }

#endregion

#region Task Details
# ============================================================================
# VIEWING TASK DETAILS
# ============================================================================

# Get detailed task information
$task = Get-VergeTask -Name "Snapshot*" | Select-Object -First 1
if ($task) {
    Write-Host "Task Details"
    Write-Host "============"
    Write-Host "Name:       $($task.Name)"
    Write-Host "Type:       $($task.Type)"
    Write-Host "Target:     $($task.TargetName) ($($task.TargetType))"
    Write-Host "Enabled:    $($task.Enabled)"
    Write-Host "Status:     $($task.Status)"
    Write-Host "Running:    $($task.IsRunning)"
    Write-Host "Last Run:   $($task.LastRun)"
    Write-Host "Next Run:   $($task.NextRun)"
}

# View tasks grouped by type
Get-VergeTask | Group-Object Type | Format-Table Name, Count

# Find tasks by target type (VM, Network, Tenant, etc.)
Get-VergeTask | Where-Object TargetType -eq 'vms' | Format-Table Name, TargetName, LastRun

# Tasks scheduled to run soon (within next hour)
$nextHour = (Get-Date).AddHours(1)
Get-VergeTask | Where-Object { $_.NextRun -and $_.NextRun -lt $nextHour } |
    Format-Table Name, NextRun

#endregion

#region Managing Task State
# ============================================================================
# ENABLING AND DISABLING TASKS
# ============================================================================

# Disable a task (prevents future runs)
# Stop-VergeTask -Name "Backup Job"

# Preview what would happen (WhatIf)
Get-VergeTask | Select-Object -First 1 | Stop-VergeTask -WhatIf

# Enable a disabled task
# Enable-VergeTask -Name "Backup Job"

# Preview enabling a task
Get-VergeTask | Where-Object { -not $_.Enabled } | Select-Object -First 1 | Enable-VergeTask -WhatIf

# Disable task by key
# Stop-VergeTask -Key 5

# Enable and return the updated task
# Enable-VergeTask -Name "Backup Job" -PassThru

# Pipeline: Disable all tasks matching a pattern
# Get-VergeTask -Name "Test*" | Stop-VergeTask

# Pipeline: Enable all disabled tasks
# Get-VergeTask | Where-Object { -not $_.Enabled } | Enable-VergeTask

#endregion

#region Waiting for Tasks
# ============================================================================
# WAITING FOR TASK COMPLETION
# ============================================================================

# Wait for a running task to complete
# $task = Get-VergeTask -Running | Select-Object -First 1
# if ($task) {
#     Write-Host "Waiting for task '$($task.Name)' to complete..."
#     Wait-VergeTask -Task $task
#     Write-Host "Task completed!"
# }

# Wait with custom timeout (default is 300 seconds)
# Wait-VergeTask -Name "Long Running Task" -TimeoutSeconds 600

# Wait by key
# Wait-VergeTask -Key 5

# Custom polling interval (check every 5 seconds instead of 2)
# Wait-VergeTask -Name "Quick Task" -PollingIntervalSeconds 5

# Wait with verbose output to see progress
# Wait-VergeTask -Name "Backup Job" -Verbose

# Pipeline: Wait for multiple tasks
# Get-VergeTask -Running | Wait-VergeTask

#endregion

#region Task Monitoring Workflows
# ============================================================================
# PRACTICAL TASK MONITORING WORKFLOWS
# ============================================================================

# Check for any running tasks
$runningTasks = Get-VergeTask -Running
if ($runningTasks) {
    Write-Host "`nCurrently Running Tasks:" -ForegroundColor Yellow
    $runningTasks | Format-Table Name, Type, TargetName, Status
} else {
    Write-Host "`nNo tasks currently running." -ForegroundColor Green
}

# Task schedule overview
Write-Host "`nUpcoming Scheduled Tasks (next 24 hours):" -ForegroundColor Cyan
$tomorrow = (Get-Date).AddDays(1)
Get-VergeTask |
    Where-Object { $_.Enabled -and $_.NextRun -and $_.NextRun -lt $tomorrow } |
    Sort-Object NextRun |
    Format-Table Name, Type, NextRun -AutoSize

# Recent task activity
Write-Host "`nRecently Run Tasks:" -ForegroundColor Cyan
Get-VergeTask |
    Where-Object LastRun |
    Sort-Object LastRun -Descending |
    Select-Object -First 10 |
    Format-Table Name, Type, LastRun, Status -AutoSize

# Task health check
function Get-VergeTaskHealth {
    <#
    .SYNOPSIS
        Check the health status of all tasks.
    #>

    $tasks = Get-VergeTask
    $enabled = ($tasks | Where-Object Enabled).Count
    $disabled = ($tasks | Where-Object { -not $_.Enabled }).Count
    $running = ($tasks | Where-Object IsRunning).Count

    [PSCustomObject]@{
        TotalTasks    = $tasks.Count
        Enabled       = $enabled
        Disabled      = $disabled
        CurrentlyRunning = $running
    }
}

Get-VergeTaskHealth | Format-List

#endregion

#region Automation Examples
# ============================================================================
# AUTOMATION SCENARIOS
# ============================================================================

# Scenario 1: Maintenance window - disable all backup tasks
# $backupTasks = Get-VergeTask -Name "*backup*"
# $backupTasks | Stop-VergeTask
# Write-Host "Disabled $($backupTasks.Count) backup tasks for maintenance"
#
# # After maintenance, re-enable
# $backupTasks | ForEach-Object { Enable-VergeTask -Key $_.Key }

# Scenario 2: Wait for all running tasks before system operation
# $running = Get-VergeTask -Running
# if ($running) {
#     Write-Host "Waiting for $($running.Count) task(s) to complete..."
#     $running | ForEach-Object {
#         Write-Host "  Waiting for: $($_.Name)"
#         Wait-VergeTask -Task $_ -TimeoutSeconds 3600
#     }
#     Write-Host "All tasks complete, proceeding with maintenance."
# }

# Scenario 3: Task execution report
function Get-VergeTaskReport {
    <#
    .SYNOPSIS
        Generate a task execution report.
    #>

    Get-VergeTask | ForEach-Object {
        [PSCustomObject]@{
            Name        = $_.Name
            Type        = $_.Type
            Target      = $_.TargetName
            Enabled     = $_.Enabled
            Status      = $_.Status
            IsRunning   = $_.IsRunning
            LastRun     = $_.LastRun
            NextRun     = $_.NextRun
            DaysSinceLastRun = if ($_.LastRun) {
                [math]::Round(((Get-Date) - $_.LastRun).TotalDays, 1)
            } else {
                'Never'
            }
        }
    }
}

Get-VergeTaskReport | Format-Table Name, Type, Enabled, Status, LastRun, DaysSinceLastRun -AutoSize

# Scenario 4: Find stale tasks (enabled but haven't run in 7+ days)
$staleDays = 7
$staleTasks = Get-VergeTask | Where-Object {
    $_.Enabled -and $_.LastRun -and ((Get-Date) - $_.LastRun).TotalDays -gt $staleDays
}

if ($staleTasks) {
    Write-Host "`nWarning: Tasks that haven't run in $staleDays+ days:" -ForegroundColor Yellow
    $staleTasks | Format-Table Name, Type, LastRun, NextRun
}

#endregion
