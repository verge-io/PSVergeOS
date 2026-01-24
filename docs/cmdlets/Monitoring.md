# Monitoring Cmdlets

Cmdlets for managing alarms, logs, and tasks.

## Overview

Monitoring cmdlets provide visibility into system health through alarms, log access, and task management for tracking long-running operations.

## Alarms

### Get-VergeAlarm

Lists active alarms.

**Syntax:**
```powershell
Get-VergeAlarm [-Severity <String>] [-Acknowledged <Boolean>]
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Severity` | String | No | Warning, Error, Critical |
| `-Acknowledged` | Boolean | No | Filter by acknowledgment status |

**Examples:**

```powershell
# List all alarms
Get-VergeAlarm

# Get error alarms only
Get-VergeAlarm -Severity Error

# Unacknowledged alarms
Get-VergeAlarm -Acknowledged $false

# Alarm summary
Get-VergeAlarm | Group-Object Severity | Format-Table Name, Count
```

---

### Set-VergeAlarm

Acknowledges or snoozes alarms.

**Syntax:**
```powershell
Set-VergeAlarm -Key <Int32> [-Acknowledge] [-Snooze <Int32>] [-Notes <String>]
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Key` | Int32 | Yes | Alarm identifier |
| `-Acknowledge` | Switch | No | Mark alarm as acknowledged |
| `-Snooze` | Int32 | No | Snooze duration in minutes |
| `-Notes` | String | No | Add notes to the alarm |

**Examples:**

```powershell
# Acknowledge an alarm
Set-VergeAlarm -Key 123 -Acknowledge -Notes "Investigating issue"

# Snooze for 1 hour
Set-VergeAlarm -Key 123 -Snooze 60

# Acknowledge all warning alarms
Get-VergeAlarm -Severity Warning | ForEach-Object {
    Set-VergeAlarm -Key $_.Key -Acknowledge
}
```

## Logs

### Get-VergeLog

Lists system log entries.

**Syntax:**
```powershell
Get-VergeLog [-Type <String>] [-Severity <String>] [-StartTime <DateTime>]
    [-EndTime <DateTime>] [-Limit <Int32>]
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Type` | String | No | Log type filter |
| `-Severity` | String | No | info, warning, error |
| `-StartTime` | DateTime | No | Start of time range |
| `-EndTime` | DateTime | No | End of time range |
| `-Limit` | Int32 | No | Maximum entries to return |

**Examples:**

```powershell
# Recent logs
Get-VergeLog -Limit 50

# Error logs
Get-VergeLog -Severity error -Limit 100

# Logs from last hour
Get-VergeLog -StartTime (Get-Date).AddHours(-1) -Severity warning

# Export logs
Get-VergeLog -Limit 1000 | Export-Csv "system-logs.csv" -NoTypeInformation
```

## Tasks

### Get-VergeTask

Lists running and recent tasks.

**Syntax:**
```powershell
Get-VergeTask [-Status <String>] [-Type <String>]
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Status` | String | No | running, completed, failed |
| `-Type` | String | No | Task type filter |

**Examples:**

```powershell
# List running tasks
Get-VergeTask -Status running

# All recent tasks
Get-VergeTask | Format-Table Name, Status, Progress, StartTime

# Failed tasks
Get-VergeTask -Status failed
```

---

### Wait-VergeTask

Waits for a task to complete.

**Syntax:**
```powershell
Wait-VergeTask -Task <Object> [-Timeout <Int32>] [-PassThru]
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Task` | Object | Yes | Task object or key |
| `-Timeout` | Int32 | No | Timeout in seconds |
| `-PassThru` | Switch | No | Return completed task |

**Examples:**

```powershell
# Start operation and wait
$task = New-VergeVMClone -SourceVM "Template" -Name "NewVM" -PassThru
Wait-VergeTask -Task $task -Timeout 300

# Wait with progress
$task = Start-VergeSiteSync -Name "DR-Sync" -PassThru
$result = Wait-VergeTask -Task $task -PassThru
if ($result.Status -eq 'completed') {
    Write-Host "Sync completed successfully"
}
```

---

### Stop-VergeTask

Cancels a running task.

**Syntax:**
```powershell
Stop-VergeTask -Task <Object> [-Confirm]
```

**Examples:**

```powershell
# Cancel a task
Get-VergeTask -Status running | Where-Object Name -like "*sync*" | Stop-VergeTask
```

---

### Enable-VergeTask

Enables a scheduled task.

**Syntax:**
```powershell
Enable-VergeTask -Name <String>
```

## Common Workflows

### Monitor System Health

```powershell
# Check for issues
$alarms = Get-VergeAlarm -Severity Error
$failedTasks = Get-VergeTask -Status failed

if ($alarms.Count -gt 0) {
    Write-Warning "$($alarms.Count) error alarms present"
    $alarms | Format-Table Message, Created
}

if ($failedTasks.Count -gt 0) {
    Write-Warning "$($failedTasks.Count) failed tasks"
    $failedTasks | Format-Table Name, Message, EndTime
}
```

### Wait for Multiple Tasks

```powershell
# Start multiple operations
$tasks = @()
$tasks += New-VergeVMSnapshot -VMName "VM1" -Name "Backup" -PassThru
$tasks += New-VergeVMSnapshot -VMName "VM2" -Name "Backup" -PassThru
$tasks += New-VergeVMSnapshot -VMName "VM3" -Name "Backup" -PassThru

# Wait for all to complete
foreach ($task in $tasks) {
    $result = Wait-VergeTask -Task $task -PassThru
    Write-Host "Task $($task.Name): $($result.Status)"
}
```

### Daily Health Report

```powershell
$report = [ordered]@{
    Timestamp = Get-Date
    ErrorAlarms = (Get-VergeAlarm -Severity Error).Count
    WarningAlarms = (Get-VergeAlarm -Severity Warning).Count
    FailedTasks = (Get-VergeTask -Status failed | Where-Object {
        $_.EndTime -gt (Get-Date).AddDays(-1)
    }).Count
    RecentErrors = (Get-VergeLog -Severity error -StartTime (Get-Date).AddDays(-1)).Count
}

[PSCustomObject]$report | Format-List
```
