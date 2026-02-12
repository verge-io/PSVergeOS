---
title: Storage Cmdlets
description: Cmdlets for managing NAS services, volumes, CIFS/NFS shares, volume sync, and storage tiers
tags: [storage, nas, volume, cifs, smb, nfs, share, vsan, tier, snapshot, sync, get-vergenasservice, new-vergenasvolume, get-vergestoragetier, file-share]
categories: [Storage]
---

# Storage Cmdlets

Cmdlets for managing NAS services, volumes, and file shares.

## Overview

Storage cmdlets provide management of VergeOS NAS services including volume creation, CIFS/SMB and NFS share management, volume synchronization, and local user administration.

## NAS Service Management

### Get-VergeNASService

Lists NAS service instances.

**Syntax:**
```powershell
Get-VergeNASService [-Name <String>]
```

**Examples:**

```powershell
# List all NAS services
Get-VergeNASService

# Get specific service
Get-VergeNASService -Name "NAS-Primary"
```

---

### New-VergeNASService

Deploys a new NAS service VM.

**Syntax:**
```powershell
New-VergeNASService -Name <String> -Network <String> [-Cluster <String>]
    [-CPUCores <Int32>] [-RAM <Int32>] [-PowerOn] [-PassThru]
```

**Examples:**

```powershell
# Deploy NAS service
New-VergeNASService -Name "NAS-Primary" -Network "Internal" `
    -CPUCores 4 -RAM 8192 -PowerOn -PassThru
```

---

### Set-VergeNASService

Modifies NAS service settings.

---

### Remove-VergeNASService

Removes a NAS service.

## Volume Management

### Get-VergeNASVolume

Lists NAS volumes.

**Syntax:**
```powershell
Get-VergeNASVolume [-NASService <String>] [-Name <String>]
```

**Examples:**

```powershell
# List volumes on a NAS
Get-VergeNASVolume -NASService "NAS-Primary"

# Show volume details
Get-VergeNASVolume -Name "Data" | Format-List *
```

---

### New-VergeNASVolume

Creates a new volume.

**Syntax:**
```powershell
New-VergeNASVolume -NASService <String> -Name <String> [-SizeGB <Int32>]
    [-Tier <Int32>] [-Description <String>] [-PassThru]
```

**Examples:**

```powershell
# Create a volume
New-VergeNASVolume -NASService "NAS-Primary" -Name "UserData" `
    -SizeGB 500 -Tier 1 -Description "User home directories"
```

---

### Set-VergeNASVolume

Modifies volume settings.

---

### Remove-VergeNASVolume

Deletes a volume.

---

### Get-VergeNASVolumeSnapshot

Lists volume snapshots.

---

### New-VergeNASVolumeSnapshot

Creates a volume snapshot.

**Syntax:**
```powershell
New-VergeNASVolumeSnapshot -Volume <String> -Name <String> [-PassThru]
```

---

### Remove-VergeNASVolumeSnapshot

Deletes a volume snapshot.

## CIFS/SMB Shares

### Get-VergeNASCIFSShare

Lists CIFS/SMB shares.

**Syntax:**
```powershell
Get-VergeNASCIFSShare [-NASService <String>] [-Volume <String>]
```

---

### New-VergeNASCIFSShare

Creates a CIFS share.

**Syntax:**
```powershell
New-VergeNASCIFSShare -NASService <String> -Volume <String> -Name <String>
    -Path <String> [-Description <String>] [-ReadOnly] [-GuestAccess] [-PassThru]
```

**Examples:**

```powershell
# Create a CIFS share
New-VergeNASCIFSShare -NASService "NAS-Primary" -Volume "UserData" `
    -Name "Users" -Path "/" -Description "User home directories"

# Create read-only share
New-VergeNASCIFSShare -NASService "NAS-Primary" -Volume "Software" `
    -Name "Software" -Path "/" -ReadOnly
```

---

### Set-VergeNASCIFSShare

Modifies CIFS share settings.

---

### Remove-VergeNASCIFSShare

Deletes a CIFS share.

---

### Get-VergeNASCIFSSettings

Retrieves CIFS service settings.

---

### Set-VergeNASCIFSSettings

Modifies CIFS service settings including workgroup and AD integration.

## NFS Shares

### Get-VergeNASNFSShare

Lists NFS exports.

---

### New-VergeNASNFSShare

Creates an NFS export.

**Syntax:**
```powershell
New-VergeNASNFSShare -NASService <String> -Volume <String> -Name <String>
    -Path <String> [-AllowedHosts <String>] [-ReadWrite] [-PassThru]
```

**Examples:**

```powershell
# Create NFS export
New-VergeNASNFSShare -NASService "NAS-Primary" -Volume "VMStorage" `
    -Name "VMs" -Path "/" -AllowedHosts "10.0.0.0/24" -ReadWrite
```

---

### Set-VergeNASNFSShare

Modifies NFS export settings.

---

### Remove-VergeNASNFSShare

Deletes an NFS export.

---

### Get-VergeNASNFSSettings

Retrieves NFS service settings.

---

### Set-VergeNASNFSSettings

Modifies NFS service settings.

## NAS Local Users

### Get-VergeNASUser

Lists local NAS users.

---

### New-VergeNASUser

Creates a local NAS user.

**Syntax:**
```powershell
New-VergeNASUser -NASService <String> -Username <String> -Password <SecureString>
    [-DisplayName <String>] [-HomeShare <String>] [-PassThru]
```

**Examples:**

```powershell
# Create NAS user
$password = Read-Host -AsSecureString -Prompt "Password"
New-VergeNASUser -NASService "NAS-Primary" -Username "jsmith" `
    -Password $password -DisplayName "John Smith"
```

---

### Set-VergeNASUser

Modifies NAS user settings.

---

### Remove-VergeNASUser

Deletes a NAS user.

---

### Enable-VergeNASUser / Disable-VergeNASUser

Enables or disables a NAS user account.

## Volume Synchronization

### Get-VergeNASVolumeSync

Lists volume sync jobs.

---

### New-VergeNASVolumeSync

Creates a volume sync configuration.

**Syntax:**
```powershell
New-VergeNASVolumeSync -SourceVolume <String> -DestinationVolume <String>
    [-Schedule <String>] [-PassThru]
```

---

### Set-VergeNASVolumeSync

Modifies volume sync settings.

---

### Remove-VergeNASVolumeSync

Deletes a volume sync configuration.

---

### Start-VergeNASVolumeSync

Starts a volume sync job.

---

### Stop-VergeNASVolumeSync

Stops a running sync job.

## File Browser

### Get-VergeNASVolumeFile

Browses files within a volume.

**Syntax:**
```powershell
Get-VergeNASVolumeFile -Volume <String> [-Path <String>]
```

**Examples:**

```powershell
# List root of volume
Get-VergeNASVolumeFile -Volume "UserData"

# Browse specific directory
Get-VergeNASVolumeFile -Volume "UserData" -Path "/users/jsmith"
```

## Storage Tiers

### Get-VergeStorageTier

Lists storage tiers with capacity and usage.

**Syntax:**
```powershell
Get-VergeStorageTier
```

**Examples:**

```powershell
# List storage tiers
Get-VergeStorageTier | Format-Table Name, TotalGB, UsedGB, FreeGB, UsedPercent
```

---

### Get-VergevSANStatus

Retrieves vSAN health status.

## Common Workflows

### Deploy NAS with Share

```powershell
# 1. Deploy NAS service
$nas = New-VergeNASService -Name "FileServer" -Network "Internal" `
    -CPUCores 4 -RAM 8192 -PowerOn -PassThru

# Wait for service to start
Start-Sleep -Seconds 60

# 2. Create volume
New-VergeNASVolume -NASService "FileServer" -Name "SharedData" -SizeGB 1000

# 3. Create CIFS share
New-VergeNASCIFSShare -NASService "FileServer" -Volume "SharedData" `
    -Name "Data" -Path "/" -Description "Shared data"

# 4. Create NAS user
$password = ConvertTo-SecureString "TempPass123!" -AsPlainText -Force
New-VergeNASUser -NASService "FileServer" -Username "datauser" -Password $password
```

### Volume Backup Configuration

```powershell
# Create sync to backup volume
New-VergeNASVolumeSync -SourceVolume "Production" -DestinationVolume "Backup" `
    -Schedule "Daily"

# Manual sync trigger
Start-VergeNASVolumeSync -SourceVolume "Production"
```
