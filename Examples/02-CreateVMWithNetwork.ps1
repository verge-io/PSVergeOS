<#
.SYNOPSIS
    Complete example: Create a network and VM with drives and ISO.

.DESCRIPTION
    This script demonstrates a complete workflow for deploying infrastructure:
    1. Create an internal network routed through External
    2. Create a VM with specific CPU/RAM configuration
    3. Add multiple drives on different storage tiers
    4. Attach an ISO for installation
    5. Connect the VM to the network and power it on

    This is a common pattern for deploying new servers or nested VergeOS environments.

.NOTES
    Prerequisites:
    - PowerShell 7.4 or later
    - PSVergeOS module installed
    - Connected to a VergeOS system (see 01-Connection.ps1)
    - "External" network must exist
    - ISO file must be uploaded to media catalog

.EXAMPLE
    # Run the entire script after customizing variables
    .\02-CreateVMWithNetwork.ps1
#>

# Import the module (if not already loaded)
Import-Module PSVergeOS -ErrorAction Stop

#region Configuration Variables
# ============================================================================
# CUSTOMIZE THESE VARIABLES FOR YOUR ENVIRONMENT
# ============================================================================

# Network Configuration
$NetworkName        = "Lab-Internal"              # Name for the new network
$NetworkAddress     = "10.100.0.0/24"             # Network CIDR
$NetworkGateway     = "10.100.0.1"                # Gateway IP (network router)
$DHCPRangeStart     = "10.100.0.100"              # DHCP pool start
$DHCPRangeStop      = "10.100.0.200"              # DHCP pool end
$UplinkNetwork      = "External"                  # Route traffic through this network

# VM Configuration
$VMName             = "VergeOS-Nested"            # Name for the new VM
$VMDescription      = "Nested VergeOS installation for testing"
$CPUCores           = 4                           # Number of CPU cores
$RAMSizeMB          = 8192                        # RAM in MB (8GB)

# Storage Configuration
$BootDriveSizeGB    = 200                         # Boot/OS drive size
$BootDriveTier      = 1                           # Fast tier for OS (SSD/NVMe)
$DataDriveSizeGB    = 500                         # Data drive size
$DataDriveTier      = 3                           # Capacity tier for data

# ISO Configuration
$ISOFileName        = "verge-io-install-26.0.1.2.iso"   # ISO to mount

#endregion

#region Pre-flight Checks
# ============================================================================
# VERIFY PREREQUISITES BEFORE PROCEEDING
# ============================================================================

Write-Host "Performing pre-flight checks..." -ForegroundColor Cyan

# Verify connection
$connection = Get-VergeConnection -Default
if (-not $connection) {
    throw "Not connected to VergeOS. Run Connect-VergeOS first."
}
Write-Host "  Connected to: $($connection.Server)" -ForegroundColor Green

# Verify uplink network exists
$uplinkNet = Get-VergeNetwork -Name $UplinkNetwork -ErrorAction SilentlyContinue
if (-not $uplinkNet) {
    throw "Uplink network '$UplinkNetwork' not found. Please verify the network name."
}
Write-Host "  Uplink network '$UplinkNetwork' found (Key: $($uplinkNet.Key))" -ForegroundColor Green

# Find the ISO file
$isoFile = Get-VergeFile -Name $ISOFileName -Type iso -ErrorAction SilentlyContinue
if (-not $isoFile) {
    Write-Warning "ISO file '$ISOFileName' not found in media catalog."
    Write-Host "  Available ISO files:" -ForegroundColor Yellow
    Get-VergeFile -Type iso | ForEach-Object { Write-Host "    - $($_.Name)" -ForegroundColor Yellow }
    throw "Upload the ISO or update the `$ISOFileName variable."
}
Write-Host "  ISO file found: $($isoFile.Name) (Key: $($isoFile.Key))" -ForegroundColor Green

# Check if network already exists
$existingNet = Get-VergeNetwork -Name $NetworkName -ErrorAction SilentlyContinue
if ($existingNet) {
    Write-Warning "Network '$NetworkName' already exists (Key: $($existingNet.Key))"
    $useExisting = Read-Host "Use existing network? (Y/N)"
    if ($useExisting -ne 'Y') {
        throw "Network already exists. Change `$NetworkName or delete existing network."
    }
}

# Check if VM already exists
$existingVM = Get-VergeVM -Name $VMName -ErrorAction SilentlyContinue
if ($existingVM) {
    throw "VM '$VMName' already exists (Key: $($existingVM.Key)). Change `$VMName or delete existing VM."
}

Write-Host "Pre-flight checks passed!" -ForegroundColor Green
Write-Host ""

#endregion

#region Create Network
# ============================================================================
# STEP 1: CREATE INTERNAL NETWORK WITH EXTERNAL ROUTING
# ============================================================================

if (-not $existingNet) {
    Write-Host "Creating network '$NetworkName'..." -ForegroundColor Cyan

    # Create the network with DHCP enabled and routed through External
    $network = New-VergeNetwork `
        -Name $NetworkName `
        -Type Internal `
        -NetworkAddress $NetworkAddress `
        -IPAddress $NetworkGateway `
        -Gateway $NetworkGateway `
        -InterfaceNetwork $UplinkNetwork `
        -DHCPEnabled `
        -DHCPStart $DHCPRangeStart `
        -DHCPStop $DHCPRangeStop `
        -Description "Lab network routed through $UplinkNetwork" `
        -PowerOn `
        -PassThru

    Write-Host "  Network created and powered on (Key: $($network.Key))" -ForegroundColor Green
}
else {
    $network = $existingNet
    Write-Host "Using existing network '$NetworkName' (Key: $($network.Key))" -ForegroundColor Yellow
}

Write-Host ""

#endregion

#region Create VM
# ============================================================================
# STEP 2: CREATE THE VIRTUAL MACHINE
# ============================================================================

Write-Host "Creating VM '$VMName'..." -ForegroundColor Cyan

$vm = New-VergeVM `
    -Name $VMName `
    -Description $VMDescription `
    -CPUCores $CPUCores `
    -RAM $RAMSizeMB `
    -OSFamily Linux `
    -UEFI `
    -GuestAgent `
    -BootOrder CDDisk `
    -PassThru

Write-Host "  VM created (Key: $($vm.Key))" -ForegroundColor Green
Write-Host "  CPU: $($vm.CPUCores) cores, RAM: $($vm.RAM) MB" -ForegroundColor Green
Write-Host ""

#endregion

#region Add Drives
# ============================================================================
# STEP 3: ADD STORAGE DRIVES
# ============================================================================

Write-Host "Adding drives to VM..." -ForegroundColor Cyan

# Add boot drive on fast tier
$bootDrive = New-VergeDrive `
    -VM $vm `
    -Name "Boot" `
    -SizeGB $BootDriveSizeGB `
    -Tier $BootDriveTier `
    -Interface virtio-scsi `
    -Description "Boot/OS drive" `
    -PassThru

Write-Host "  Boot drive: ${BootDriveSizeGB}GB on Tier $BootDriveTier (Key: $($bootDrive.Key))" -ForegroundColor Green

# Add data drive on capacity tier
$dataDrive = New-VergeDrive `
    -VM $vm `
    -Name "Data" `
    -SizeGB $DataDriveSizeGB `
    -Tier $DataDriveTier `
    -Interface virtio-scsi `
    -Description "Data/storage drive" `
    -PassThru

Write-Host "  Data drive: ${DataDriveSizeGB}GB on Tier $DataDriveTier (Key: $($dataDrive.Key))" -ForegroundColor Green

# Add CD-ROM drive and mount the ISO
$cdromDrive = New-VergeDrive `
    -VM $vm `
    -Name "ISO" `
    -Media cdrom `
    -Description "Installation media" `
    -PassThru

Write-Host "  CD-ROM drive added (Key: $($cdromDrive.Key))" -ForegroundColor Green

# Mount the ISO to the CD-ROM drive
Set-VergeDrive -Drive $cdromDrive -MediaSource $isoFile.Key
Write-Host "  ISO '$ISOFileName' mounted to CD-ROM" -ForegroundColor Green

Write-Host ""

#endregion

#region Add Network Interface
# ============================================================================
# STEP 4: ADD NETWORK INTERFACE
# ============================================================================

Write-Host "Adding network interface..." -ForegroundColor Cyan

$nic = New-VergeNIC `
    -VM $vm `
    -NetworkName $NetworkName `
    -Name "eth0" `
    -Interface virtio `
    -Description "Primary network interface" `
    -PassThru

Write-Host "  NIC added: $($nic.Name) connected to '$NetworkName' (Key: $($nic.Key))" -ForegroundColor Green
Write-Host ""

#endregion

#region Power On VM
# ============================================================================
# STEP 5: START THE VIRTUAL MACHINE
# ============================================================================

Write-Host "Starting VM '$VMName'..." -ForegroundColor Cyan

Start-VergeVM -VM $vm

Write-Host "  VM power-on command sent" -ForegroundColor Green
Write-Host ""

#endregion

#region Summary
# ============================================================================
# DEPLOYMENT SUMMARY
# ============================================================================

Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "DEPLOYMENT COMPLETE" -ForegroundColor Green
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host ""
Write-Host "Network: $NetworkName" -ForegroundColor White
Write-Host "  Address: $NetworkAddress"
Write-Host "  Gateway: $NetworkGateway"
Write-Host "  DHCP:    $DHCPRangeStart - $DHCPRangeStop"
Write-Host "  Uplink:  $UplinkNetwork"
Write-Host ""
Write-Host "VM: $VMName" -ForegroundColor White
Write-Host "  CPU:     $CPUCores cores"
Write-Host "  RAM:     $($RAMSizeMB / 1024) GB"
Write-Host "  Boot:    ${BootDriveSizeGB}GB (Tier $BootDriveTier)"
Write-Host "  Data:    ${DataDriveSizeGB}GB (Tier $DataDriveTier)"
Write-Host "  ISO:     $ISOFileName"
Write-Host "  Network: $NetworkName"
Write-Host ""

# Get console URL
$consoleUrl = Get-VergeVMConsole -VM $vm
if ($consoleUrl) {
    Write-Host "Console URL:" -ForegroundColor White
    Write-Host "  $consoleUrl" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "The VM is booting from the ISO. Connect to the console to complete installation." -ForegroundColor Yellow

#endregion
