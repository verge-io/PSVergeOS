<#
.SYNOPSIS
    NAS Volume Sync example - two NAS services with volume synchronization.

.DESCRIPTION
    This script demonstrates NAS volume synchronization:
    - Deploy two NAS services on an internal network
    - Create one volume on each NAS
    - Set up a volume sync job between them
    - Run the sync and verify

.NOTES
    Prerequisites:
    - PowerShell 7.4 or later
    - PSVergeOS module installed
    - Connected to a VergeOS system
    - An internal network available
#>

# Import the module
Import-Module PSVergeOS

#region Configuration
# ============================================================================
# CONFIGURATION - Modify these values as needed
# ============================================================================

$NAS1Name = "pstest-nas-primary"
$NAS2Name = "pstest-nas-replica"
$NetworkName = "internal"
$SourceVolumeName = "Production"
$DestVolumeName = "Backup"
$SyncJobName = "Prod-to-Backup-Sync"
$VolumeSizeGB = 50

#endregion

#region Deploy NAS Services
# ============================================================================
# STEP 1: DEPLOY TWO NAS SERVICES
# ============================================================================

Write-Host "`n=== Deploying NAS Services ===" -ForegroundColor Cyan

# Deploy primary NAS
Write-Host "Deploying primary NAS: $NAS1Name..."
$nas1 = New-VergeNASService -Name $NAS1Name -Network $NetworkName -PassThru

if (-not $nas1) {
    Write-Error "Failed to deploy primary NAS. Exiting."
    return
}
Write-Host "  Primary NAS deployed (Key: $($nas1.Key))" -ForegroundColor Green

# Deploy replica NAS
Write-Host "Deploying replica NAS: $NAS2Name..."
$nas2 = New-VergeNASService -Name $NAS2Name -Network $NetworkName -PassThru

if (-not $nas2) {
    Write-Error "Failed to deploy replica NAS. Exiting."
    return
}
Write-Host "  Replica NAS deployed (Key: $($nas2.Key), VM Key: $($nas2.VMKey))" -ForegroundColor Green

#endregion

#region Start and Wait for NAS Services
# ============================================================================
# STEP 2: START AND WAIT FOR BOTH NAS SERVICES
# ============================================================================

Write-Host "`n=== Starting NAS Services ===" -ForegroundColor Cyan

# Start both NAS VMs (NAS services are backed by VMs)
Write-Host "Starting primary NAS VM..."
Start-VergeVM -Key $nas1.VMKey

Write-Host "Starting replica NAS VM..."
Start-VergeVM -Key $nas2.VMKey

Write-Host "`nWaiting for NAS services to come online..."

$maxWaitSeconds = 180
$waitInterval = 10
$elapsed = 0

while ($elapsed -lt $maxWaitSeconds) {
    $nas1Status = Get-VergeNASService -Name $NAS1Name
    $nas2Status = Get-VergeNASService -Name $NAS2Name

    $nas1Running = $nas1Status.IsRunning
    $nas2Running = $nas2Status.IsRunning

    Write-Host "  $NAS1Name : $($nas1Status.Status) | $NAS2Name : $($nas2Status.Status)"

    if ($nas1Running -and $nas2Running) {
        Write-Host "Both NAS services are running!" -ForegroundColor Green
        break
    }

    Start-Sleep -Seconds $waitInterval
    $elapsed += $waitInterval
}

if (-not ($nas1Status.IsRunning -and $nas2Status.IsRunning)) {
    Write-Warning "NAS services did not start within $maxWaitSeconds seconds."
    return
}

# Additional initialization time
Write-Host "Waiting for NAS services to fully initialize..."
Start-Sleep -Seconds 15

#endregion

#region Create Volumes
# ============================================================================
# STEP 3: CREATE VOLUMES ON EACH NAS
# ============================================================================

Write-Host "`n=== Creating Volumes ===" -ForegroundColor Cyan

# Create source volume on primary NAS
Write-Host "Creating source volume: $SourceVolumeName on $NAS1Name..."
$sourceVol = New-VergeNASVolume -Name $SourceVolumeName -NASService $NAS1Name -SizeGB $VolumeSizeGB -Description "Production data volume"

if ($sourceVol) {
    Write-Host "  Source volume created (Key: $($sourceVol.Key))" -ForegroundColor Green
} else {
    Write-Error "Failed to create source volume"
    return
}

# Create destination volume on replica NAS
Write-Host "Creating destination volume: $DestVolumeName on $NAS2Name..."
$destVol = New-VergeNASVolume -Name $DestVolumeName -NASService $NAS2Name -SizeGB $VolumeSizeGB -Description "Backup replica volume"

if ($destVol) {
    Write-Host "  Destination volume created (Key: $($destVol.Key))" -ForegroundColor Green
} else {
    Write-Error "Failed to create destination volume"
    return
}

#endregion

#region Create Volume Sync
# ============================================================================
# STEP 4: CREATE VOLUME SYNC JOB
# ============================================================================

Write-Host "`n=== Creating Volume Sync Job ===" -ForegroundColor Cyan

# Create the sync job on the primary NAS
# Note: Volume sync jobs are associated with a NAS service
Write-Host "Creating volume sync job: $SyncJobName..."

$syncJob = New-VergeNASVolumeSync `
    -NASService $NAS1Name `
    -Name $SyncJobName `
    -SourceVolume $SourceVolumeName `
    -DestinationVolume $DestVolumeName `
    -SyncMethod VergeSync `
    -DestinationDelete Never `
    -Workers 4 `
    -Description "Sync production data to backup"

if ($syncJob) {
    Write-Host "  Volume sync job created (Key: $($syncJob.Key))" -ForegroundColor Green
    Write-Host "  Source:      $($syncJob.SourceVolumeName)"
    Write-Host "  Destination: $($syncJob.DestinationVolumeName)"
    Write-Host "  Method:      $($syncJob.SyncMethod)"
} else {
    Write-Error "Failed to create volume sync job"
    return
}

#endregion

#region Run Initial Sync
# ============================================================================
# STEP 5: RUN INITIAL SYNC
# ============================================================================

Write-Host "`n=== Running Initial Sync ===" -ForegroundColor Cyan

Write-Host "Starting sync job..."
Start-VergeNASVolumeSync -NASService $NAS1Name -Name $SyncJobName

# Wait a moment and check status
Start-Sleep -Seconds 3

$syncStatus = Get-VergeNASVolumeSync -NASService $NAS1Name -Name $SyncJobName
Write-Host "  Sync Status: $($syncStatus.Status)"

if ($syncStatus.Status -eq 'Running' -or $syncStatus.Status -eq 'Pending') {
    Write-Host "  Sync job started successfully" -ForegroundColor Green
}

#endregion

#region Verify Configuration
# ============================================================================
# STEP 6: VERIFY CONFIGURATION
# ============================================================================

Write-Host "`n=== Configuration Summary ===" -ForegroundColor Cyan

# Show both NAS services
Write-Host "`nNAS Services:" -ForegroundColor Yellow
Get-VergeNASService -Name "pstest-nas-*" | Format-Table Name, Status, Hostname, IPAddress, IsRunning

# Show all volumes
Write-Host "Volumes:" -ForegroundColor Yellow
@($SourceVolumeName, $DestVolumeName) | ForEach-Object {
    Get-VergeNASVolume -Name $_
} | Format-Table Name, @{N='NASService';E={$_.NASService}}, @{N='Size (GB)';E={[math]::Round($_.MaxSizeGB, 1)}}, Description

# Show sync jobs
Write-Host "Volume Sync Jobs:" -ForegroundColor Yellow
Get-VergeNASVolumeSync -NASService $NAS1Name | Format-Table Name, Status, SourceVolumeName, DestinationVolumeName, SyncMethod

#endregion

#region Cleanup Instructions
# ============================================================================
# CLEANUP - Run these commands to remove the test resources
# ============================================================================

Write-Host "`n=== Cleanup Commands ===" -ForegroundColor Magenta
Write-Host "To remove these test resources, run the following commands in order:"
Write-Host ""
Write-Host "# 1. Remove the sync job"
Write-Host "Remove-VergeNASVolumeSync -NASService '$NAS1Name' -Name '$SyncJobName' -Confirm:`$false"
Write-Host ""
Write-Host "# 2. Remove volumes"
Write-Host "Remove-VergeNASVolume -Name '$SourceVolumeName' -Confirm:`$false"
Write-Host "Remove-VergeNASVolume -Name '$DestVolumeName' -Confirm:`$false"
Write-Host ""
Write-Host "# 3. Remove NAS services"
Write-Host "Remove-VergeNASService -Name '$NAS1Name' -Confirm:`$false"
Write-Host "Remove-VergeNASService -Name '$NAS2Name' -Confirm:`$false"

#endregion
