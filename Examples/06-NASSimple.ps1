<#
.SYNOPSIS
    Simple NAS setup example - single NAS with two volumes.

.DESCRIPTION
    This script demonstrates the basic NAS setup workflow:
    - Deploy a NAS service on an internal network
    - Create two volumes with default settings
    - Verify the configuration

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

$NASName = "pstest-nas-simple"
$NetworkName = "internal"  # Use your internal network name
$Volume1Name = "Data"
$Volume2Name = "Archive"
$VolumeSizeGB = 50  # Size in GB for each volume

#endregion

#region Deploy NAS Service
# ============================================================================
# STEP 1: DEPLOY NAS SERVICE
# ============================================================================

Write-Host "`n=== Deploying NAS Service ===" -ForegroundColor Cyan

# Deploy a new NAS service with default settings (4 cores, 8GB RAM)
$nas = New-VergeNASService -Name $NASName -Network $NetworkName -PassThru

if (-not $nas) {
    Write-Error "Failed to deploy NAS service. Exiting."
    return
}

Write-Host "NAS Service deployed successfully:" -ForegroundColor Green
Write-Host "  Name:      $($nas.Name)"
Write-Host "  Status:    $($nas.Status)"
Write-Host "  Hostname:  $($nas.Hostname)"
Write-Host "  VM Key:    $($nas.VMKey)"
Write-Host "  VM Cores:  $($nas.VMCores)"
Write-Host "  VM RAM:    $($nas.VMRAMGB) GB"

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
$maxWaitSeconds = 120
$waitInterval = 10
$elapsed = 0

while ($elapsed -lt $maxWaitSeconds) {
    $nasStatus = Get-VergeNASService -Name $NASName
    if ($nasStatus.IsRunning) {
        Write-Host "NAS service is now running!" -ForegroundColor Green
        Write-Host "  IP Address: $($nasStatus.IPAddress)"
        break
    }
    Write-Host "  Status: $($nasStatus.Status) - waiting..."
    Start-Sleep -Seconds $waitInterval
    $elapsed += $waitInterval
}

if (-not $nasStatus.IsRunning) {
    Write-Warning "NAS service did not start within $maxWaitSeconds seconds. It may still be initializing."
    Write-Warning "You can continue manually once the NAS is running."
    return
}

# Give the NAS a moment to fully initialize
Write-Host "Waiting for NAS service to fully initialize..."
Start-Sleep -Seconds 10

#endregion

#region Create Volumes
# ============================================================================
# STEP 3: CREATE VOLUMES
# ============================================================================

Write-Host "`n=== Creating Volumes ===" -ForegroundColor Cyan

# Create first volume - Data
Write-Host "Creating volume: $Volume1Name ($VolumeSizeGB GB)..."
$vol1 = New-VergeNASVolume -Name $Volume1Name -NASService $NASName -SizeGB $VolumeSizeGB -Description "General data storage"

if ($vol1) {
    Write-Host "  Volume '$Volume1Name' created successfully (Key: $($vol1.Key))" -ForegroundColor Green
}

# Create second volume - Archive
Write-Host "Creating volume: $Volume2Name ($VolumeSizeGB GB)..."
$vol2 = New-VergeNASVolume -Name $Volume2Name -NASService $NASName -SizeGB $VolumeSizeGB -Description "Archive storage"

if ($vol2) {
    Write-Host "  Volume '$Volume2Name' created successfully (Key: $($vol2.Key))" -ForegroundColor Green
}

#endregion

#region Verify Configuration
# ============================================================================
# STEP 4: VERIFY CONFIGURATION
# ============================================================================

Write-Host "`n=== Configuration Summary ===" -ForegroundColor Cyan

# Get final NAS status
$finalNAS = Get-VergeNASService -Name $NASName

Write-Host "`nNAS Service Details:" -ForegroundColor Yellow
$finalNAS | Format-List Name, Status, Hostname, IPAddress, VMCores, VMRAMGB, IsRunning

# List the volumes we created
Write-Host "Volumes on this NAS:" -ForegroundColor Yellow
@($Volume1Name, $Volume2Name) | ForEach-Object {
    Get-VergeNASVolume -Name $_
} | Format-Table Name, @{N='Size (GB)';E={[math]::Round($_.MaxSizeGB, 1)}}, @{N='Used (GB)';E={[math]::Round($_.UsedGB, 2)}}, NASService, Description

#endregion

#region Cleanup Instructions
# ============================================================================
# CLEANUP - Run these commands to remove the test resources
# ============================================================================

Write-Host "`n=== Cleanup Commands ===" -ForegroundColor Magenta
Write-Host "To remove these test resources, run the following commands:"
Write-Host ""
Write-Host "# Remove volumes first"
Write-Host "Remove-VergeNASVolume -Name '$Volume1Name' -Confirm:`$false"
Write-Host "Remove-VergeNASVolume -Name '$Volume2Name' -Confirm:`$false"
Write-Host ""
Write-Host "# Then remove the NAS service"
Write-Host "Remove-VergeNASService -Name '$NASName' -Confirm:`$false"

#endregion
