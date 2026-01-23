<#
.SYNOPSIS
    Examples for VergeOS alarms and system log management.

.DESCRIPTION
    This script demonstrates monitoring operations:
    - Listing and filtering alarms
    - Alarm history and details
    - Snoozing and resolving alarms
    - Querying system logs
    - Filtering logs by level, type, user, and time
    - Building monitoring workflows

.NOTES
    Prerequisites:
    - PowerShell 7.4 or later
    - PSVergeOS module installed
    - Connected to a VergeOS system
#>

# Import the module
Import-Module PSVergeOS

#region Listing Alarms
# ============================================================================
# LISTING ACTIVE ALARMS
# ============================================================================

# List all active alarms (excludes snoozed by default)
Get-VergeAlarm

# List alarms with key details
Get-VergeAlarm | Format-Table Key, Level, Status, Owner, Created -AutoSize

# Include snoozed alarms in results
Get-VergeAlarm -IncludeSnoozed

# Get a specific alarm by key
Get-VergeAlarm -Key 1

# Filter by severity level
Get-VergeAlarm -Level Critical
Get-VergeAlarm -Level Error
Get-VergeAlarm -Level Warning
Get-VergeAlarm -Level Critical, Error  # Multiple levels

# Filter by owner type
Get-VergeAlarm -OwnerType VM
Get-VergeAlarm -OwnerType Network
Get-VergeAlarm -OwnerType Node
Get-VergeAlarm -OwnerType System

# Combine filters
Get-VergeAlarm -Level Critical, Error -OwnerType VM

#endregion

#region Alarm Details
# ============================================================================
# VIEWING ALARM DETAILS
# ============================================================================

# Get detailed alarm information
$alarm = Get-VergeAlarm | Select-Object -First 1
if ($alarm) {
    Write-Host "Alarm Details"
    Write-Host "============="
    Write-Host "Key:         $($alarm.Key)"
    Write-Host "Level:       $($alarm.Level)"
    Write-Host "Status:      $($alarm.Status)"
    Write-Host "Description: $($alarm.Description)"
    Write-Host "Owner:       $($alarm.Owner) ($($alarm.OwnerType))"
    Write-Host "Created:     $($alarm.Created)"
    Write-Host "Resolvable:  $($alarm.Resolvable)"
    Write-Host "Is Snoozed:  $($alarm.IsSnoozed)"
    if ($alarm.IsSnoozed) {
        Write-Host "Snoozed Until: $($alarm.SnoozeUntil)"
        Write-Host "Snoozed By:    $($alarm.SnoozedBy)"
    }
}

# Group alarms by level
Get-VergeAlarm -IncludeSnoozed | Group-Object Level | Format-Table Name, Count

# Group alarms by owner type
Get-VergeAlarm | Group-Object OwnerType | Format-Table Name, Count

# Find resolvable alarms
Get-VergeAlarm | Where-Object Resolvable | Format-Table Key, Level, Status, ResolveText

#endregion

#region Alarm History
# ============================================================================
# VIEWING ALARM HISTORY
# ============================================================================

# Get alarm history (resolved/lowered alarms)
Get-VergeAlarm -History

# View recent alarm history
Get-VergeAlarm -History | Select-Object -First 20 |
    Format-Table Key, Level, Status, RaisedAt, LoweredAt -AutoSize

# Find alarms resolved today
$today = (Get-Date).Date
Get-VergeAlarm -History | Where-Object { $_.LoweredAt -ge $today } |
    Format-Table Key, Level, Status, LoweredAt

#endregion

#region Snoozing Alarms
# ============================================================================
# SNOOZING AND UNSNOOZING ALARMS
# ============================================================================

# Snooze an alarm for 24 hours (default)
# Set-VergeAlarm -Key 1 -Snooze

# Snooze for a specific number of hours
# Set-VergeAlarm -Key 1 -Snooze -SnoozeHours 48

# Snooze until a specific date/time
# Set-VergeAlarm -Key 1 -Snooze -SnoozeUntil (Get-Date).AddDays(7)

# Preview snooze action (WhatIf)
Get-VergeAlarm | Select-Object -First 1 | Set-VergeAlarm -Snooze -WhatIf

# Snooze via pipeline
# Get-VergeAlarm -Level Warning | Set-VergeAlarm -Snooze -SnoozeHours 12

# Snooze and return the updated alarm
# $snoozed = Set-VergeAlarm -Key 1 -Snooze -SnoozeHours 24 -PassThru

# Unsnooze an alarm (make it active again)
# Set-VergeAlarm -Key 1 -Unsnooze

# Unsnooze via pipeline
# Get-VergeAlarm -IncludeSnoozed | Where-Object IsSnoozed | Set-VergeAlarm -Unsnooze

#endregion

#region Resolving Alarms
# ============================================================================
# RESOLVING/ACKNOWLEDGING ALARMS
# ============================================================================

# Resolve a resolvable alarm
# Set-VergeAlarm -Key 1 -Resolve

# Preview resolve action (WhatIf)
Get-VergeAlarm | Where-Object Resolvable | Select-Object -First 1 |
    Set-VergeAlarm -Resolve -WhatIf

# Resolve all resolvable alarms
# Get-VergeAlarm | Where-Object Resolvable | Set-VergeAlarm -Resolve

# Resolve by key
# Set-VergeAlarm -Key 5 -Resolve

#endregion

#region System Logs
# ============================================================================
# QUERYING SYSTEM LOGS
# ============================================================================

# Get recent logs (default: 100 entries)
Get-VergeLog

# Get logs formatted as table
Get-VergeLog -Limit 20 | Format-Table Timestamp, Level, ObjectType, ObjectName, Text -AutoSize

# Limit number of results
Get-VergeLog -Limit 50

# Filter by log level
Get-VergeLog -Level Error
Get-VergeLog -Level Critical
Get-VergeLog -Level Warning
Get-VergeLog -Level Error, Critical  # Multiple levels

# Quick shortcut: Get only errors and critical entries
Get-VergeLog -ErrorsOnly

# Filter by object type
Get-VergeLog -ObjectType VM
Get-VergeLog -ObjectType Network
Get-VergeLog -ObjectType Tenant
Get-VergeLog -ObjectType User
Get-VergeLog -ObjectType System

# Filter by user who performed the action
Get-VergeLog -User "admin"

# Search log text (case-insensitive)
Get-VergeLog -Text "power"
Get-VergeLog -Text "error"
Get-VergeLog -Text "snapshot"

#endregion

#region Time-Based Log Queries
# ============================================================================
# TIME-BASED LOG FILTERING
# ============================================================================

# Logs from the last hour
Get-VergeLog -Since (Get-Date).AddHours(-1)

# Logs from the last 24 hours
Get-VergeLog -Since (Get-Date).AddDays(-1) -Limit 500

# Logs from a specific time range
$startTime = (Get-Date).AddHours(-4)
$endTime = (Get-Date).AddHours(-2)
Get-VergeLog -Since $startTime -Before $endTime

# Logs since midnight today
Get-VergeLog -Since (Get-Date).Date

# Combine time filters with other filters
Get-VergeLog -ObjectType VM -Since (Get-Date).AddHours(-1) |
    Format-Table Timestamp, ObjectName, Text

#endregion

#region Combined Log Queries
# ============================================================================
# ADVANCED LOG QUERIES
# ============================================================================

# Find all VM power events in last hour
Get-VergeLog -ObjectType VM -Text "power" -Since (Get-Date).AddHours(-1) |
    Format-Table Timestamp, ObjectName, Text

# Find errors for a specific user
Get-VergeLog -User "admin" -Level Error, Critical |
    Format-Table Timestamp, Level, Text

# Find all snapshot-related activity
Get-VergeLog -Text "snapshot" -Limit 50 |
    Format-Table Timestamp, ObjectType, ObjectName, Text

# Get audit trail for user actions
Get-VergeLog -Level Audit -User "admin" -Limit 50 |
    Format-Table Timestamp, ObjectType, ObjectName, Text

#endregion

#region Monitoring Workflows
# ============================================================================
# PRACTICAL MONITORING WORKFLOWS
# ============================================================================

# Alarm summary dashboard
function Get-VergeAlarmSummary {
    <#
    .SYNOPSIS
        Get a summary of current alarm status.
    #>

    $alarms = Get-VergeAlarm -IncludeSnoozed
    $active = $alarms | Where-Object { -not $_.IsSnoozed }
    $snoozed = $alarms | Where-Object IsSnoozed

    [PSCustomObject]@{
        TotalAlarms      = $alarms.Count
        ActiveAlarms     = $active.Count
        SnoozedAlarms    = $snoozed.Count
        Critical         = ($active | Where-Object Level -eq 'Critical').Count
        Error            = ($active | Where-Object Level -eq 'Error').Count
        Warning          = ($active | Where-Object Level -eq 'Warning').Count
        Resolvable       = ($active | Where-Object Resolvable).Count
    }
}

Write-Host "`nAlarm Summary:" -ForegroundColor Cyan
Get-VergeAlarmSummary | Format-List

# Check for critical issues
$criticalAlarms = Get-VergeAlarm -Level Critical, Error
if ($criticalAlarms) {
    Write-Host "`nCritical/Error Alarms Requiring Attention:" -ForegroundColor Red
    $criticalAlarms | Format-Table Key, Level, Status, Owner, Created
} else {
    Write-Host "`nNo critical or error alarms." -ForegroundColor Green
}

# Recent error log summary
Write-Host "`nRecent Errors (last hour):" -ForegroundColor Yellow
$recentErrors = Get-VergeLog -ErrorsOnly -Since (Get-Date).AddHours(-1)
if ($recentErrors) {
    $recentErrors | Format-Table Timestamp, Level, ObjectType, Text -AutoSize
} else {
    Write-Host "  No errors in the last hour." -ForegroundColor Green
}

#endregion

#region System Health Check
# ============================================================================
# COMPREHENSIVE HEALTH CHECK
# ============================================================================

function Get-VergeHealthCheck {
    <#
    .SYNOPSIS
        Perform a comprehensive system health check using alarms and logs.
    #>

    $issues = @()

    # Check for critical alarms
    $criticalAlarms = Get-VergeAlarm -Level Critical
    if ($criticalAlarms) {
        $issues += "[CRITICAL] $($criticalAlarms.Count) critical alarm(s)"
    }

    # Check for error alarms
    $errorAlarms = Get-VergeAlarm -Level Error
    if ($errorAlarms) {
        $issues += "[ERROR] $($errorAlarms.Count) error alarm(s)"
    }

    # Check for recent critical log entries
    $recentCritical = Get-VergeLog -Level Critical -Since (Get-Date).AddHours(-1)
    if ($recentCritical) {
        $issues += "[LOG] $($recentCritical.Count) critical log entries in last hour"
    }

    # Check for recent errors
    $recentErrors = Get-VergeLog -Level Error -Since (Get-Date).AddHours(-1)
    if ($recentErrors) {
        $issues += "[LOG] $($recentErrors.Count) error log entries in last hour"
    }

    # Output results
    [PSCustomObject]@{
        CheckTime       = Get-Date
        HealthStatus    = if ($issues.Count -eq 0) { 'Healthy' } else { 'Issues Detected' }
        IssueCount      = $issues.Count
        Issues          = $issues
        CriticalAlarms  = $criticalAlarms.Count
        ErrorAlarms     = $errorAlarms.Count
        WarningAlarms   = (Get-VergeAlarm -Level Warning).Count
        RecentLogErrors = $recentErrors.Count
    }
}

$health = Get-VergeHealthCheck
Write-Host "`nSystem Health Check" -ForegroundColor Cyan
Write-Host "==================="
Write-Host "Status: $($health.HealthStatus)" -ForegroundColor $(if ($health.HealthStatus -eq 'Healthy') { 'Green' } else { 'Red' })
Write-Host "Alarms: $($health.CriticalAlarms) critical, $($health.ErrorAlarms) error, $($health.WarningAlarms) warning"
Write-Host "Recent Errors: $($health.RecentLogErrors) in last hour"

if ($health.Issues.Count -gt 0) {
    Write-Host "`nIssues:" -ForegroundColor Yellow
    $health.Issues | ForEach-Object { Write-Host "  - $_" }
}

#endregion

#region Log Analysis
# ============================================================================
# LOG ANALYSIS AND REPORTING
# ============================================================================

# Activity by object type (last 24 hours)
Write-Host "`nActivity by Object Type (last 24 hours):" -ForegroundColor Cyan
Get-VergeLog -Since (Get-Date).AddDays(-1) -Limit 1000 |
    Group-Object ObjectType |
    Sort-Object Count -Descending |
    Format-Table @{N='Object Type';E={$_.Name}}, Count

# Activity by user
Write-Host "`nActivity by User (last 24 hours):" -ForegroundColor Cyan
Get-VergeLog -Since (Get-Date).AddDays(-1) -Limit 1000 |
    Where-Object User |
    Group-Object User |
    Sort-Object Count -Descending |
    Select-Object -First 10 |
    Format-Table @{N='User';E={$_.Name}}, Count

# VM activity timeline
Write-Host "`nRecent VM Activity:" -ForegroundColor Cyan
Get-VergeLog -ObjectType VM -Limit 20 |
    Format-Table Timestamp, ObjectName, Text -AutoSize

# Export logs to CSV for external analysis
# Get-VergeLog -Since (Get-Date).AddDays(-7) -Limit 10000 |
#     Export-Csv "vergeos-logs-$(Get-Date -Format 'yyyyMMdd').csv" -NoTypeInformation

#endregion

#region Automated Alerting Example
# ============================================================================
# AUTOMATED ALERTING (EXAMPLE WORKFLOW)
# ============================================================================

<#
This example shows how to build an automated monitoring script that could
be run on a schedule (e.g., via cron or Windows Task Scheduler).
#>

function Send-VergeAlertReport {
    <#
    .SYNOPSIS
        Generate and optionally send an alert report.
    #>
    param(
        [switch]$SendEmail,
        [string]$SmtpServer,
        [string]$To,
        [string]$From
    )

    $report = @()
    $report += "VergeOS Alert Report - $(Get-Date)"
    $report += "=" * 50

    # Critical alarms
    $critical = Get-VergeAlarm -Level Critical
    if ($critical) {
        $report += "`nCRITICAL ALARMS ($($critical.Count)):"
        $critical | ForEach-Object {
            $report += "  - [$($_.Key)] $($_.Status) ($($_.Owner))"
        }
    }

    # Error alarms
    $errors = Get-VergeAlarm -Level Error
    if ($errors) {
        $report += "`nERROR ALARMS ($($errors.Count)):"
        $errors | ForEach-Object {
            $report += "  - [$($_.Key)] $($_.Status) ($($_.Owner))"
        }
    }

    # Recent critical logs
    $criticalLogs = Get-VergeLog -Level Critical -Since (Get-Date).AddHours(-1)
    if ($criticalLogs) {
        $report += "`nCRITICAL LOGS (last hour):"
        $criticalLogs | ForEach-Object {
            $report += "  - $($_.Timestamp): $($_.Text)"
        }
    }

    $reportText = $report -join "`n"

    if ($SendEmail -and $SmtpServer -and $To -and $From) {
        # Send-MailMessage -SmtpServer $SmtpServer -To $To -From $From `
        #     -Subject "VergeOS Alert Report" -Body $reportText
        Write-Host "Email would be sent to $To"
    }

    return $reportText
}

# Generate report (without sending)
# $report = Send-VergeAlertReport
# Write-Host $report

#endregion
