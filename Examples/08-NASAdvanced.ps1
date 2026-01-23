<#
.SYNOPSIS
    Advanced NAS setup with users, CIFS shares, and NFS shares.

.DESCRIPTION
    This script demonstrates advanced NAS configuration:
    - Deploy a NAS service on the external network
    - Create local NAS users
    - Create three volumes
    - Set up CIFS (SMB) shares with user restrictions
    - Set up NFS shares with host restrictions
    - Modify advanced NAS service settings

.NOTES
    Prerequisites:
    - PowerShell 7.4 or later
    - PSVergeOS module installed
    - Connected to a VergeOS system
    - An external network available (or modify to use internal)
#>

# Import the module
Import-Module PSVergeOS

#region Configuration
# ============================================================================
# CONFIGURATION - Modify these values as needed
# ============================================================================

$NASName = "pstest-nas-advanced"
$NetworkName = "internal"  # Change to "External" or your external network name
$NASCores = 4
$NASMemoryGB = 8

# Volume configuration
$Volumes = @(
    @{ Name = "UserData"; SizeGB = 100; Description = "User home directories and data" }
    @{ Name = "Shared"; SizeGB = 200; Description = "Department shared files" }
    @{ Name = "LinuxApps"; SizeGB = 50; Description = "Linux application data via NFS" }
)

# User configuration (passwords must be 8+ chars and meet complexity requirements)
$Users = @(
    @{ Name = "nasadmin"; Password = "NasAdminPass123!@"; DisplayName = "NAS Administrator" }
    @{ Name = "jdoe"; Password = "JohnDoePass456!@"; DisplayName = "John Doe" }
    @{ Name = "svcbackup"; Password = "SvcBackupPass789!@"; DisplayName = "Backup Service Account" }
)

# Network for NFS access (CIDR notation)
$NFSAllowedNetwork = "192.168.10.0/24"

#endregion

#region Deploy NAS Service
# ============================================================================
# STEP 1: DEPLOY NAS SERVICE WITH CUSTOM RESOURCES
# ============================================================================

Write-Host "`n=== Deploying NAS Service ===" -ForegroundColor Cyan

Write-Host "Deploying NAS: $NASName ($NASCores cores, ${NASMemoryGB}GB RAM)..."
$nas = New-VergeNASService -Name $NASName -Network $NetworkName -Cores $NASCores -MemoryGB $NASMemoryGB -PassThru

if (-not $nas) {
    Write-Error "Failed to deploy NAS service. Exiting."
    return
}

Write-Host "NAS service deployed:" -ForegroundColor Green
Write-Host "  Key:       $($nas.Key)"
Write-Host "  VM Key:    $($nas.VMKey)"
Write-Host "  Hostname:  $($nas.Hostname)"

#endregion

#region Start and Wait for NAS
# ============================================================================
# STEP 2: START AND WAIT FOR NAS SERVICE
# ============================================================================

Write-Host "`n=== Starting NAS Service ===" -ForegroundColor Cyan

# Start the NAS VM (NAS services are backed by VMs)
Write-Host "Starting NAS VM..."
Start-VergeVM -Key $nas.VMKey

# Wait for the NAS to come online
$maxWaitSeconds = 180
$waitInterval = 10
$elapsed = 0

while ($elapsed -lt $maxWaitSeconds) {
    $nasStatus = Get-VergeNASService -Name $NASName
    Write-Host "  Status: $($nasStatus.Status)"

    if ($nasStatus.IsRunning) {
        Write-Host "NAS service is running!" -ForegroundColor Green
        Write-Host "  IP Address: $($nasStatus.IPAddress)"
        break
    }

    Start-Sleep -Seconds $waitInterval
    $elapsed += $waitInterval
}

if (-not $nasStatus.IsRunning) {
    Write-Warning "NAS service did not start within $maxWaitSeconds seconds."
    return
}

# Additional initialization time
Write-Host "Waiting for NAS service to fully initialize..."
Start-Sleep -Seconds 15

#endregion

#region Configure Advanced Settings
# ============================================================================
# STEP 3: CONFIGURE ADVANCED NAS SETTINGS
# ============================================================================

Write-Host "`n=== Configuring Advanced Settings ===" -ForegroundColor Cyan

# Set advanced NAS service settings
Write-Host "Configuring NAS service settings..."
Set-VergeNASService -Name $NASName `
    -MaxImports 3 `
    -MaxSyncs 2 `
    -ReadAheadKB 1024 `
    -Description "Advanced NAS for testing - production-style configuration"

Write-Host "  MaxImports: 3" -ForegroundColor Green
Write-Host "  MaxSyncs: 2" -ForegroundColor Green
Write-Host "  ReadAheadKB: 1024" -ForegroundColor Green

#endregion

#region Create Users
# ============================================================================
# STEP 4: CREATE LOCAL NAS USERS
# ============================================================================

Write-Host "`n=== Creating NAS Users ===" -ForegroundColor Cyan

foreach ($user in $Users) {
    Write-Host "Creating user: $($user.Name)..."

    try {
        # Note: Can pass plain text or SecureString for password
        New-VergeNASUser -NASServiceName $NASName `
            -Name $user.Name `
            -Password $user.Password `
            -DisplayName $user.DisplayName `
            -PassThru | Out-Null

        Write-Host "  User '$($user.Name)' created" -ForegroundColor Green
    }
    catch {
        Write-Warning "  Failed to create user '$($user.Name)': $($_.Exception.Message)"
    }
}

# List created users
Write-Host "`nNAS Users:" -ForegroundColor Yellow
Get-VergeNASUser -NASServiceName $NASName | Format-Table Name, DisplayName, Enabled

#endregion

#region Create Volumes
# ============================================================================
# STEP 5: CREATE VOLUMES
# ============================================================================

Write-Host "`n=== Creating Volumes ===" -ForegroundColor Cyan

foreach ($vol in $Volumes) {
    Write-Host "Creating volume: $($vol.Name) ($($vol.SizeGB) GB)..."

    try {
        $volume = New-VergeNASVolume -Name $vol.Name `
            -NASService $NASName `
            -SizeGB $vol.SizeGB `
            -Description $vol.Description

        Write-Host "  Volume '$($vol.Name)' created (Key: $($volume.Key))" -ForegroundColor Green
    }
    catch {
        Write-Warning "  Failed to create volume '$($vol.Name)': $($_.Exception.Message)"
    }
}

# List volumes
Write-Host "`nVolumes:" -ForegroundColor Yellow
Get-VergeNASVolume -NASService $NASName | Format-Table Name, @{N='MaxSize (GB)';E={[math]::Round($_.MaxSizeGB,1)}}, Description

#endregion

#region Create CIFS Shares
# ============================================================================
# STEP 6: CREATE CIFS (SMB) SHARES
# ============================================================================

Write-Host "`n=== Creating CIFS Shares ===" -ForegroundColor Cyan

# Share 1: User data with restricted access
Write-Host "Creating CIFS share: users (on UserData volume)..."
$cifsShare1 = New-VergeNASCIFSShare -Volume "UserData" `
    -Name "users" `
    -Comment "User home directories" `
    -ValidUsers @("nasadmin", "jdoe") `
    -ShadowCopy

if ($cifsShare1) {
    Write-Host "  Share 'users' created - access restricted to admin, jdoe" -ForegroundColor Green
}

# Share 2: Department shared with broader access
Write-Host "Creating CIFS share: shared (on Shared volume)..."
$cifsShare2 = New-VergeNASCIFSShare -Volume "Shared" `
    -Name "shared" `
    -Comment "Department shared files" `
    -Description "Read-write access for all authenticated users"

if ($cifsShare2) {
    Write-Host "  Share 'shared' created - all authenticated users" -ForegroundColor Green
}

# List CIFS shares
Write-Host "`nCIFS Shares:" -ForegroundColor Yellow
Get-VergeNASCIFSShare -NASService $NASName | Format-Table Name, VolumeName, Comment, GuestOK, ReadOnly

#endregion

#region Create NFS Share
# ============================================================================
# STEP 7: CREATE NFS SHARE
# ============================================================================

Write-Host "`n=== Creating NFS Share ===" -ForegroundColor Cyan

# NFS share for Linux clients
Write-Host "Creating NFS share: linuxapps (on LinuxApps volume)..."
$nfsShare = New-VergeNASNFSShare -Volume "LinuxApps" `
    -Name "linuxapps" `
    -AllowedHosts $NFSAllowedNetwork `
    -DataAccess ReadWrite `
    -Squash SquashRoot `
    -Description "NFS share for Linux application data"

if ($nfsShare) {
    Write-Host "  Share 'linuxapps' created" -ForegroundColor Green
    Write-Host "  Allowed hosts: $NFSAllowedNetwork"
    Write-Host "  Data access: ReadWrite"
    Write-Host "  Squash: SquashRoot"
}

# List NFS shares
Write-Host "`nNFS Shares:" -ForegroundColor Yellow
Get-VergeNASNFSShare -NASService $NASName | Format-Table Name, VolumeName, DataAccess, Squash, AllowedHosts

#endregion

#region Final Summary
# ============================================================================
# STEP 8: FINAL CONFIGURATION SUMMARY
# ============================================================================

Write-Host "`n" + "="*60 -ForegroundColor Cyan
Write-Host "=== CONFIGURATION COMPLETE ===" -ForegroundColor Cyan
Write-Host "="*60 -ForegroundColor Cyan

# NAS Service
$finalNAS = Get-VergeNASService -Name $NASName
Write-Host "`nNAS Service:" -ForegroundColor Yellow
Write-Host "  Name:       $($finalNAS.Name)"
Write-Host "  Status:     $($finalNAS.Status)"
Write-Host "  Hostname:   $($finalNAS.Hostname)"
Write-Host "  IP Address: $($finalNAS.IPAddress)"
Write-Host "  CPU Cores:  $($finalNAS.VMCores)"
Write-Host "  RAM:        $($finalNAS.VMRAMGB) GB"
Write-Host "  MaxImports: $($finalNAS.MaxImports)"
Write-Host "  MaxSyncs:   $($finalNAS.MaxSyncs)"

# Users
Write-Host "`nUsers:" -ForegroundColor Yellow
Get-VergeNASUser -NASServiceName $NASName | ForEach-Object {
    Write-Host "  - $($_.Name) ($($_.DisplayName))"
}

# Volumes
Write-Host "`nVolumes:" -ForegroundColor Yellow
Get-VergeNASVolume -NASService $NASName | ForEach-Object {
    Write-Host "  - $($_.Name): $([math]::Round($_.MaxSizeGB, 1)) GB"
}

# CIFS Shares
Write-Host "`nCIFS Shares (access via \\$($finalNAS.IPAddress)\sharename):" -ForegroundColor Yellow
Get-VergeNASCIFSShare -NASService $NASName | ForEach-Object {
    Write-Host "  - \\$($finalNAS.IPAddress)\$($_.Name)"
}

# NFS Shares
Write-Host "`nNFS Shares (mount with: mount -t nfs server:/share /mnt):" -ForegroundColor Yellow
Get-VergeNASNFSShare -NASService $NASName | ForEach-Object {
    Write-Host "  - $($finalNAS.IPAddress):/$($_.Name)"
}

#endregion

#region Cleanup Instructions
# ============================================================================
# CLEANUP - Run these commands to remove the test resources
# ============================================================================

Write-Host "`n=== Cleanup Commands ===" -ForegroundColor Magenta
Write-Host "To remove these test resources, run the following commands in order:"
Write-Host ""
Write-Host "# 1. Remove shares"
Write-Host "Get-VergeNASCIFSShare -NASService '$NASName' | Remove-VergeNASCIFSShare -Confirm:`$false"
Write-Host "Get-VergeNASNFSShare -NASService '$NASName' | Remove-VergeNASNFSShare -Confirm:`$false"
Write-Host ""
Write-Host "# 2. Remove users"
Write-Host "Get-VergeNASUser -NASServiceName '$NASName' | Remove-VergeNASUser -Confirm:`$false"
Write-Host ""
Write-Host "# 3. Remove volumes"
Write-Host "Get-VergeNASVolume -NASService '$NASName' | Remove-VergeNASVolume -Confirm:`$false"
Write-Host ""
Write-Host "# 4. Remove NAS service"
Write-Host "Remove-VergeNASService -Name '$NASName' -Confirm:`$false"

#endregion
