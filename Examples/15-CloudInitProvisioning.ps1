<#
.SYNOPSIS
    Deploy a VM using cloud-init for automated provisioning.

.DESCRIPTION
    This script demonstrates deploying a cloud-ready VM image with cloud-init:
    1. Create a VM configured for cloud-init
    2. Import a cloud image (Ubuntu/Debian cloud image)
    3. Add a network interface
    4. Create cloud-init files for automated provisioning
    5. Power on the VM (cloud-init runs on first boot)

    Cloud-init automatically configures the VM on first boot based on the
    user-data, meta-data, and network-config files you provide.

.NOTES
    Prerequisites:
    - PowerShell 7.4 or later
    - PSVergeOS module installed
    - Connected to a VergeOS system
    - A cloud image uploaded (e.g., noble-server-cloudimg-amd64.ova)

    Cloud-init file types:
    - /user-data: User configuration (packages, users, SSH keys, run commands)
    - /meta-data: Instance metadata (instance-id, hostname)
    - /network-config: Network configuration (DHCP or static IP)

.EXAMPLE
    # Customize the variables below and run the script
    .\15-CloudInitProvisioning.ps1
#>

# Import the module
Import-Module PSVergeOS -ErrorAction Stop

#region Configuration Variables
# ============================================================================
# CUSTOMIZE THESE VARIABLES FOR YOUR ENVIRONMENT
# ============================================================================

# VM Configuration
$VMName             = "pstest-cloudinit"          # Name for the new VM
$VMDescription      = "Ubuntu server deployed via cloud-init"
$CPUCores           = 2                            # Number of CPU cores
$RAMSizeMB          = 2048                         # RAM in MB (2GB)

# Cloud Image (must be uploaded to VergeOS files)
$CloudImageName     = "noble-server-cloudimg-amd64.ova"

# Network Configuration
$NetworkName        = "External"                   # Network to connect to

# Cloud-Init User Configuration
$Hostname           = "ubuntu-server"              # VM hostname
$Username           = "admin"                      # User to create
$SSHPublicKey       = ""                           # Your SSH public key (optional)
$Packages           = @("curl", "htop", "vim")     # Packages to install

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

# Verify cloud image exists
$cloudImage = Get-VergeFile -Name $CloudImageName -ErrorAction SilentlyContinue
if (-not $cloudImage) {
    Write-Warning "Cloud image '$CloudImageName' not found."
    Write-Host "  Available importable files:" -ForegroundColor Yellow
    Get-VergeFile | Where-Object { $_.Name -match '\.(ova|ovf|qcow2|vmdk)$' } |
        ForEach-Object { Write-Host "    - $($_.Name)" -ForegroundColor Yellow }
    throw "Upload a cloud image or update the `$CloudImageName variable."
}
Write-Host "  Cloud image found: $($cloudImage.Name)" -ForegroundColor Green

# Verify network exists
$network = Get-VergeNetwork -Name $NetworkName -ErrorAction SilentlyContinue
if (-not $network) {
    throw "Network '$NetworkName' not found."
}
Write-Host "  Network '$NetworkName' found (Key: $($network.Key))" -ForegroundColor Green

# Check if VM already exists
$existingVM = Get-VergeVM -Name $VMName -ErrorAction SilentlyContinue
if ($existingVM) {
    throw "VM '$VMName' already exists (Key: $($existingVM.Key)). Change `$VMName or delete existing VM."
}

Write-Host "Pre-flight checks passed!" -ForegroundColor Green
Write-Host ""

#endregion

#region Create VM
# ============================================================================
# STEP 1: CREATE THE VIRTUAL MACHINE
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
    -PassThru

Write-Host "  VM created (Key: $($vm.Key))" -ForegroundColor Green
Write-Host ""

#endregion

#region Import Cloud Image
# ============================================================================
# STEP 2: IMPORT CLOUD IMAGE AS BOOT DRIVE
# ============================================================================

Write-Host "Importing cloud image as boot drive..." -ForegroundColor Cyan

Import-VergeDrive `
    -VM $vm `
    -FileName $CloudImageName `
    -Name "Boot" `
    -Interface virtio-scsi `
    -Tier 1

Write-Host "  Cloud image imported successfully" -ForegroundColor Green
Write-Host ""

#endregion

#region Add Network Interface
# ============================================================================
# STEP 3: ADD NETWORK INTERFACE
# ============================================================================

Write-Host "Adding network interface..." -ForegroundColor Cyan

$nic = New-VergeNIC `
    -VM $vm `
    -NetworkName $NetworkName `
    -Name "eth0" `
    -Interface virtio `
    -PassThru

Write-Host "  NIC connected to '$NetworkName' (Key: $($nic.Key))" -ForegroundColor Green
Write-Host ""

#endregion

#region Create Cloud-Init Files
# ============================================================================
# STEP 4: CREATE CLOUD-INIT CONFIGURATION FILES
# ============================================================================

Write-Host "Creating cloud-init configuration..." -ForegroundColor Cyan

# --- user-data: Main configuration file ---
$userData = @"
#cloud-config

# Set the hostname
hostname: $Hostname
fqdn: $Hostname.local

# Create user account
users:
  - name: $Username
    groups: sudo, adm
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
$(if ($SSHPublicKey) {
"    ssh_authorized_keys:
      - $SSHPublicKey"
})

# Update packages and install specified packages
package_update: true
package_upgrade: true
$(if ($Packages.Count -gt 0) {
"packages:
$(($Packages | ForEach-Object { "  - $_" }) -join "`n")"
})

# Run commands on first boot
runcmd:
  - echo "Cloud-init provisioning complete at `$(date)" >> /var/log/cloud-init-custom.log
  - echo "Hostname: $Hostname" >> /var/log/cloud-init-custom.log

# Final message
final_message: "Cloud-init completed for $VMName in \$UPTIME seconds"
"@

New-VergeCloudInitFile -VMId $vm.Key -Name "/user-data" -Contents $userData -Render No
Write-Host "  /user-data created (user: $Username, packages: $($Packages -join ', '))" -ForegroundColor Green

# --- meta-data: Instance identification ---
$metaData = @"
instance-id: $($vm.Key)-$Hostname
local-hostname: $Hostname
"@

New-VergeCloudInitFile -VMId $vm.Key -Name "/meta-data" -Contents $metaData -Render No
Write-Host "  /meta-data created (instance-id: $($vm.Key)-$Hostname)" -ForegroundColor Green

# --- network-config: Network configuration (DHCP) ---
$networkConfig = @"
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
      dhcp6: false
"@

New-VergeCloudInitFile -VMId $vm.Key -Name "/network-config" -Contents $networkConfig -Render No
Write-Host "  /network-config created (DHCP enabled)" -ForegroundColor Green

Write-Host ""

#endregion

#region Power On VM
# ============================================================================
# STEP 5: START THE VIRTUAL MACHINE
# ============================================================================

Write-Host "Starting VM '$VMName'..." -ForegroundColor Cyan

Start-VergeVM -VM $vm

Write-Host "  VM powered on - cloud-init will run on first boot" -ForegroundColor Green
Write-Host ""

#endregion

#region Summary
# ============================================================================
# DEPLOYMENT SUMMARY
# ============================================================================

Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "CLOUD-INIT DEPLOYMENT COMPLETE" -ForegroundColor Green
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host ""
Write-Host "VM Configuration:" -ForegroundColor White
Write-Host "  Name:      $VMName"
Write-Host "  CPU:       $CPUCores cores"
Write-Host "  RAM:       $($RAMSizeMB / 1024) GB"
Write-Host "  Image:     $CloudImageName"
Write-Host "  Network:   $NetworkName (DHCP)"
Write-Host ""
Write-Host "Cloud-Init Configuration:" -ForegroundColor White
Write-Host "  Hostname:  $Hostname"
Write-Host "  Username:  $Username"
Write-Host "  Packages:  $($Packages -join ', ')"
Write-Host ""

# List created cloud-init files
Write-Host "Cloud-Init Files:" -ForegroundColor White
Get-VergeCloudInitFile -VMId $vm.Key | ForEach-Object {
    Write-Host "  $($_.Name) ($($_.FileSize) bytes)"
}
Write-Host ""

# Get console URL
$consoleUrl = Get-VergeVMConsole -VM $vm
if ($consoleUrl) {
    Write-Host "Console URL:" -ForegroundColor White
    Write-Host "  $consoleUrl" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "The VM is booting. Cloud-init will:" -ForegroundColor Yellow
Write-Host "  1. Set hostname to '$Hostname'"
Write-Host "  2. Create user '$Username' with sudo access"
Write-Host "  3. Configure DHCP networking"
Write-Host "  4. Update packages and install: $($Packages -join ', ')"
Write-Host ""
Write-Host "Check cloud-init status after boot:" -ForegroundColor Yellow
Write-Host "  cloud-init status --wait"
Write-Host "  cat /var/log/cloud-init-output.log"

#endregion

#region Cleanup Helper
# ============================================================================
# CLEANUP FUNCTION (Run manually if needed)
# ============================================================================

<#
# To remove the VM and its cloud-init files:
$vmToRemove = Get-VergeVM -Name "pstest-cloudinit"
if ($vmToRemove) {
    # Stop the VM first
    Stop-VergeVM -VM $vmToRemove -Force -Confirm:$false

    # Remove cloud-init files
    Get-VergeCloudInitFile -VMId $vmToRemove.Key | Remove-VergeCloudInitFile -Confirm:$false

    # Remove the VM
    Remove-VergeVM -VM $vmToRemove -Confirm:$false

    Write-Host "VM and cloud-init files removed."
}
#>

#endregion
