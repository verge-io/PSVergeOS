---
title: Backup & Disaster Recovery Cmdlets
description: Cmdlets for managing snapshot profiles, cloud snapshots, site synchronization, and disaster recovery
tags: [backup, disaster-recovery, snapshot, cloud-snapshot, site-sync, replication, dr, get-vergesnapshotprofile, get-vergecloudsnapshot, get-vergesitesync, restore, retention]
categories: [Backup]
---

# Backup & Disaster Recovery Cmdlets

Cmdlets for managing snapshots, cloud backups, and site synchronization.

## Overview

Backup cmdlets provide comprehensive disaster recovery capabilities including snapshot profiles, cloud snapshots, and site-to-site synchronization for business continuity.

## Snapshot Profiles

### Get-VergeSnapshotProfile

Lists snapshot profiles.

**Syntax:**
```powershell
Get-VergeSnapshotProfile [-Name <String>]
```

**Examples:**

```powershell
# List all profiles
Get-VergeSnapshotProfile

# View profile details
Get-VergeSnapshotProfile -Name "Daily-7day" | Format-List *
```

---

### New-VergeSnapshotProfile

Creates a snapshot profile.

**Syntax:**
```powershell
New-VergeSnapshotProfile -Name <String> -Schedule <String> -Retention <Int32>
    [-Description <String>] [-PassThru]
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Name` | String | Yes | Profile name |
| `-Schedule` | String | Yes | Cron-style schedule |
| `-Retention` | Int32 | Yes | Days to retain snapshots |
| `-Description` | String | No | Profile description |

**Examples:**

```powershell
# Create daily profile with 7-day retention
New-VergeSnapshotProfile -Name "Daily-7day" -Schedule "0 2 * * *" `
    -Retention 7 -Description "Daily snapshots at 2 AM, keep 7 days"

# Hourly profile for critical systems
New-VergeSnapshotProfile -Name "Hourly-24hr" -Schedule "0 * * * *" `
    -Retention 1 -Description "Hourly snapshots, keep 24 hours"
```

---

### Set-VergeSnapshotProfile

Modifies a snapshot profile.

---

### Remove-VergeSnapshotProfile

Deletes a snapshot profile.

## Cloud Snapshots

### Get-VergeCloudSnapshot

Lists cloud snapshots (system-level backups).

**Syntax:**
```powershell
Get-VergeCloudSnapshot [-Name <String>]
```

**Examples:**

```powershell
# List all cloud snapshots
Get-VergeCloudSnapshot

# Recent snapshots
Get-VergeCloudSnapshot | Sort-Object Created -Descending | Select-Object -First 10
```

---

### New-VergeCloudSnapshot

Creates a cloud snapshot.

**Syntax:**
```powershell
New-VergeCloudSnapshot -Name <String> [-Description <String>] [-PassThru]
```

**Examples:**

```powershell
# Create manual cloud snapshot
New-VergeCloudSnapshot -Name "Pre-Upgrade-$(Get-Date -Format 'yyyyMMdd')" `
    -Description "Snapshot before system upgrade"
```

---

### Remove-VergeCloudSnapshot

Deletes a cloud snapshot.

```powershell
Remove-VergeCloudSnapshot -Name "Old-Snapshot" -Confirm:$false
```

---

### Restore-VergeVMFromCloudSnapshot

Restores a VM from a cloud snapshot.

**Syntax:**
```powershell
Restore-VergeVMFromCloudSnapshot -CloudSnapshot <String> -VMName <String>
    [-NewName <String>] [-PassThru]
```

**Examples:**

```powershell
# Restore VM from cloud snapshot
Restore-VergeVMFromCloudSnapshot -CloudSnapshot "Daily-20260122" `
    -VMName "WebServer01" -NewName "WebServer01-Restored"
```

---

### Restore-VergeTenantFromCloudSnapshot

Restores a tenant from a cloud snapshot.

**Syntax:**
```powershell
Restore-VergeTenantFromCloudSnapshot -CloudSnapshot <String> -TenantName <String>
    [-NewName <String>] [-PassThru]
```

**Examples:**

```powershell
# Restore tenant from cloud snapshot
Restore-VergeTenantFromCloudSnapshot -CloudSnapshot "Weekly-20260119" `
    -TenantName "Customer-ABC" -NewName "Customer-ABC-Restored"
```

## Sites

### Get-VergeSite

Lists remote VergeOS sites.

**Syntax:**
```powershell
Get-VergeSite [-Name <String>]
```

**Examples:**

```powershell
# List all sites
Get-VergeSite

# View site details
Get-VergeSite -Name "DR-Site" | Format-List *
```

---

### New-VergeSite

Configures a remote site connection.

**Syntax:**
```powershell
New-VergeSite -Name <String> -Host <String> [-Port <Int32>]
    -Username <String> -Password <SecureString> [-PassThru]
```

**Examples:**

```powershell
# Add DR site
$password = Read-Host -AsSecureString -Prompt "Site Password"
New-VergeSite -Name "DR-Site" -Host "dr.vergeos.local" `
    -Username "sync-user" -Password $password
```

---

### Remove-VergeSite

Removes a site configuration.

## Site Synchronization

### Get-VergeSiteSync

Lists outgoing site sync configurations.

**Syntax:**
```powershell
Get-VergeSiteSync [-Name <String>]
```

**Examples:**

```powershell
# List sync configurations
Get-VergeSiteSync | Format-Table Name, Site, Status, LastSync
```

---

### Start-VergeSiteSync

Starts site synchronization.

**Syntax:**
```powershell
Start-VergeSiteSync -Name <String> [-PassThru]
```

**Examples:**

```powershell
# Start sync
Start-VergeSiteSync -Name "Production-to-DR"

# Start and wait for completion
$task = Start-VergeSiteSync -Name "Production-to-DR" -PassThru
Wait-VergeTask -Task $task
```

---

### Stop-VergeSiteSync

Stops a running sync.

```powershell
Stop-VergeSiteSync -Name "Production-to-DR"
```

---

### Invoke-VergeSiteSync

Triggers an immediate synchronization.

**Syntax:**
```powershell
Invoke-VergeSiteSync -Name <String> [-Full] [-PassThru]
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Name` | String | Yes | Sync configuration name |
| `-Full` | Switch | No | Force full sync (not incremental) |

**Examples:**

```powershell
# Trigger immediate sync
Invoke-VergeSiteSync -Name "Production-to-DR"

# Full resync
Invoke-VergeSiteSync -Name "Production-to-DR" -Full
```

---

### Get-VergeSiteSyncIncoming

Lists incoming syncs from remote sites.

```powershell
Get-VergeSiteSyncIncoming | Format-Table Name, SourceSite, Status, LastReceived
```

---

### Get-VergeSiteSyncSchedule

Lists sync schedules.

---

### New-VergeSiteSyncSchedule

Creates a sync schedule.

**Syntax:**
```powershell
New-VergeSiteSyncSchedule -SiteSync <String> -Schedule <String> [-PassThru]
```

**Examples:**

```powershell
# Schedule hourly sync
New-VergeSiteSyncSchedule -SiteSync "Production-to-DR" -Schedule "0 * * * *"
```

---

### Remove-VergeSiteSyncSchedule

Deletes a sync schedule.

## Common Workflows

### Pre-Maintenance Backup

```powershell
# Create cloud snapshot before major changes
$snapshotName = "Pre-Maintenance-$(Get-Date -Format 'yyyyMMdd-HHmm')"
New-VergeCloudSnapshot -Name $snapshotName -Description "Before system maintenance"
Write-Host "Created cloud snapshot: $snapshotName"

# Verify snapshot created
Get-VergeCloudSnapshot -Name $snapshotName
```

### Configure DR Replication

```powershell
# 1. Add DR site
$password = Read-Host -AsSecureString -Prompt "DR Site Password"
New-VergeSite -Name "DR-Datacenter" -Host "dr.company.com" `
    -Username "replication" -Password $password

# 2. Verify connectivity
Get-VergeSite -Name "DR-Datacenter"

# 3. Start initial sync
Start-VergeSiteSync -Name "Production-Sync"

# 4. Schedule regular syncs
New-VergeSiteSyncSchedule -SiteSync "Production-Sync" -Schedule "0 */4 * * *"
```

### Disaster Recovery Test

```powershell
# List available cloud snapshots
$snapshots = Get-VergeCloudSnapshot | Sort-Object Created -Descending
Write-Host "Available snapshots:"
$snapshots | Select-Object -First 5 | Format-Table Name, Created

# Restore specific VM for testing
$testSnapshot = $snapshots[0].Name
Restore-VergeVMFromCloudSnapshot -CloudSnapshot $testSnapshot `
    -VMName "WebServer01" -NewName "WebServer01-DR-Test"

# Start the restored VM
Start-VergeVM -Name "WebServer01-DR-Test"
```

### Manage Snapshot Retention

```powershell
# Remove old cloud snapshots
$cutoffDate = (Get-Date).AddDays(-30)
Get-VergeCloudSnapshot | Where-Object { $_.Created -lt $cutoffDate } | ForEach-Object {
    Write-Host "Removing snapshot: $($_.Name)"
    Remove-VergeCloudSnapshot -Name $_.Name -Confirm:$false
}
```

### Monitor Replication Status

```powershell
# Check all sync status
Get-VergeSiteSync | ForEach-Object {
    [PSCustomObject]@{
        Name = $_.Name
        Site = $_.Site
        Status = $_.Status
        LastSync = $_.LastSync
        BytesSynced = $_.BytesSynced
    }
} | Format-Table

# Alert on sync failures
$failedSyncs = Get-VergeSiteSync | Where-Object Status -eq 'Failed'
if ($failedSyncs) {
    Write-Warning "Failed syncs detected:"
    $failedSyncs | Format-Table Name, LastError
}
```
