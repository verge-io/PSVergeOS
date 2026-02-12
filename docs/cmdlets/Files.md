---
title: Files & Media Cmdlets
description: Cmdlets for managing media files, ISOs, disk images, and VM imports
tags: [files, media, iso, import, upload, download, get-vergefile, send-vergefile, save-vergefile, import-vergevm, import-vergedrive, disk-image]
categories: [Files]
---

# Files & Media Cmdlets

Cmdlets for managing files, ISOs, and imports.

## Overview

File cmdlets provide management of media files in VergeOS including ISOs, disk images, and VM imports.

## File Management

### Get-VergeFile

Lists files in the media catalog.

**Syntax:**
```powershell
Get-VergeFile [-Name <String>] [-Type <String>]
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Name` | String | No | File name (supports wildcards) |
| `-Type` | String | No | iso, raw, qcow2, vmdk |

**Examples:**

```powershell
# List all files
Get-VergeFile

# List ISO files
Get-VergeFile -Type iso

# Find specific ISO
Get-VergeFile -Name "*ubuntu*" -Type iso

# View file details
Get-VergeFile | Format-Table Name, Type, SizeGB, Created
```

---

### Send-VergeFile

Uploads a file to VergeOS.

**Syntax:**
```powershell
Send-VergeFile -Path <String> [-Name <String>] [-Type <String>] [-PassThru]
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Path` | String | Yes | Local file path |
| `-Name` | String | No | Name in catalog (default: filename) |
| `-Type` | String | No | File type (auto-detected if not specified) |

**Examples:**

```powershell
# Upload an ISO
Send-VergeFile -Path "C:\ISOs\ubuntu-22.04-server.iso"

# Upload with custom name
Send-VergeFile -Path "C:\ISOs\win2022.iso" -Name "Windows-Server-2022"

# Upload and return object
$file = Send-VergeFile -Path "C:\ISOs\centos-9.iso" -PassThru
```

---

### Save-VergeFile

Downloads a file from VergeOS.

**Syntax:**
```powershell
Save-VergeFile -Name <String> -Path <String>
```

**Examples:**

```powershell
# Download an ISO
Save-VergeFile -Name "ubuntu-22.04-server.iso" -Path "C:\Downloads\"

# Download specific file
$file = Get-VergeFile -Name "backup-image"
Save-VergeFile -Name $file.Name -Path "D:\Backups\$($file.Name)"
```

---

### Remove-VergeFile

Deletes a file from the media catalog.

**Syntax:**
```powershell
Remove-VergeFile -Name <String> [-Confirm]
```

**Examples:**

```powershell
# Remove a file
Remove-VergeFile -Name "old-iso.iso"

# Remove multiple files
Get-VergeFile -Name "*temp*" | ForEach-Object {
    Remove-VergeFile -Name $_.Name -Confirm:$false
}
```

## Import Operations

### Import-VergeDrive

Imports a drive image into a VM.

**Syntax:**
```powershell
Import-VergeDrive -VM <String> -File <String> [-Name <String>] [-Tier <Int32>] [-PassThru]
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-VM` | String | Yes | Target VM |
| `-File` | String | Yes | Source file name |
| `-Name` | String | No | Drive name |
| `-Tier` | Int32 | No | Storage tier |

**Examples:**

```powershell
# Import drive image
Import-VergeDrive -VM "NewServer" -File "server-backup.qcow2" -Name "Boot" -Tier 1
```

---

### Import-VergeVM

Imports a VM from an exported file.

**Syntax:**
```powershell
Import-VergeVM -File <String> [-Name <String>] [-Cluster <String>] [-PassThru]
```

**Examples:**

```powershell
# Import VM
Import-VergeVM -File "exported-vm.tar" -Name "Imported-Server"

# Import with specific cluster
Import-VergeVM -File "production-backup.tar" -Name "Restored-VM" -Cluster "Production"
```

## Common Workflows

### Upload and Mount ISO

```powershell
# 1. Upload ISO
$iso = Send-VergeFile -Path "C:\ISOs\install-media.iso" -PassThru
Write-Host "Uploaded: $($iso.Name) (Key: $($iso.Key))"

# 2. Get VM CD-ROM drive
$vm = Get-VergeVM -Name "NewServer"
$cdrom = Get-VergeDrive -VM $vm.Name | Where-Object Media -eq 'cdrom'

# 3. Mount ISO
Set-VergeDrive -Drive $cdrom -MediaSource $iso.Key
Write-Host "ISO mounted to $($vm.Name)"
```

### Manage Media Library

```powershell
# Inventory report
Get-VergeFile | Group-Object Type | Format-Table Name, Count

# Find large files
Get-VergeFile | Where-Object { $_.SizeGB -gt 10 } |
    Sort-Object SizeGB -Descending |
    Format-Table Name, Type, SizeGB

# Calculate total storage
$totalGB = (Get-VergeFile | Measure-Object -Property SizeGB -Sum).Sum
Write-Host "Media catalog total: $([math]::Round($totalGB, 2)) GB"
```

### Backup VM to File

```powershell
# Export VM drives
$vm = Get-VergeVM -Name "ImportantServer"
$drives = Get-VergeDrive -VM $vm.Name

foreach ($drive in $drives) {
    $filename = "$($vm.Name)-$($drive.Name)-$(Get-Date -Format 'yyyyMMdd').qcow2"
    Write-Host "Exporting $($drive.Name) to $filename..."
    # Export process via task
}
```

### Clean Up Old ISOs

```powershell
# Find ISOs older than 90 days
$cutoff = (Get-Date).AddDays(-90)
$oldISOs = Get-VergeFile -Type iso | Where-Object { $_.Created -lt $cutoff }

if ($oldISOs) {
    Write-Host "Found $($oldISOs.Count) ISOs older than 90 days:"
    $oldISOs | Format-Table Name, Created, SizeGB

    # Optionally remove
    # $oldISOs | ForEach-Object { Remove-VergeFile -Name $_.Name -Confirm:$false }
}
```
