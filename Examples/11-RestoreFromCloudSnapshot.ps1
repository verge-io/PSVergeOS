#Requires -Version 7.4
#Requires -Modules PSVergeOS

<#
.SYNOPSIS
    Interactive script to restore a VM or Tenant from a cloud snapshot.

.DESCRIPTION
    This script provides an interactive workflow to:
    1. Search for a VM or tenant across all cloud snapshots
    2. Display available snapshots containing the target
    3. Let the user select which snapshot to restore from
    4. Choose to restore as a new object or replace existing

.PARAMETER Name
    The name of the VM or tenant to restore.

.PARAMETER Type
    Specifies whether to restore a VM or Tenant.
    Valid values: VM, Tenant

.PARAMETER Server
    Optional VergeOS server address. If not specified, uses the current connection.

.EXAMPLE
    ./11-RestoreFromCloudSnapshot.ps1 -Name "WebServer01" -Type VM

    Searches for VM "WebServer01" in all cloud snapshots and guides through restore.

.EXAMPLE
    ./11-RestoreFromCloudSnapshot.ps1 -Name "CustomerA" -Type Tenant

    Searches for tenant "CustomerA" in all cloud snapshots and guides through restore.

.NOTES
    Requires an active connection to VergeOS (use Connect-VergeOS first).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$Name,

    [Parameter(Mandatory, Position = 1)]
    [ValidateSet('VM', 'Tenant')]
    [string]$Type,

    [Parameter()]
    [string]$Server
)

#region Helper Functions

function Write-Header {
    param([string]$Text)
    $line = "=" * 60
    Write-Host "`n$line" -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host "$line" -ForegroundColor Cyan
}

function Write-Step {
    param([int]$Number, [string]$Text)
    Write-Host "`n[$Number] $Text" -ForegroundColor Yellow
}

function Get-UserSelection {
    param(
        [array]$Options,
        [string]$Prompt = "Select an option"
    )

    if ($Options.Count -eq 0) {
        return $null
    }

    Write-Host ""
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host "  [$($i + 1)] $($Options[$i])" -ForegroundColor White
    }
    Write-Host "  [0] Cancel" -ForegroundColor DarkGray
    Write-Host ""

    do {
        $selection = Read-Host $Prompt
        if ($selection -eq '0') {
            return $null
        }
        $index = [int]$selection - 1
    } while ($index -lt 0 -or $index -ge $Options.Count)

    return $index
}

function Format-SnapshotInfo {
    param($Snapshot, $ItemCount, $ItemType)

    $created = if ($Snapshot.Created) { $Snapshot.Created.ToString("yyyy-MM-dd HH:mm") } else { "Unknown" }
    $expires = if ($Snapshot.NeverExpires) {
        "Never"
    } elseif ($Snapshot.Expires) {
        $Snapshot.Expires.ToString("yyyy-MM-dd HH:mm")
    } else {
        "Unknown"
    }

    return "$($Snapshot.Name) | Created: $created | Expires: $expires | $ItemCount ${ItemType}(s)"
}

#endregion

#region Main Script

Write-Header "VergeOS Cloud Snapshot Restore"
Write-Host "  Target: $Name ($Type)"

# Verify connection
Write-Step 1 "Verifying VergeOS connection..."

$connection = Get-VergeConnection -ErrorAction SilentlyContinue
if (-not $connection) {
    Write-Host "  ERROR: Not connected to VergeOS." -ForegroundColor Red
    Write-Host "  Please run Connect-VergeOS first." -ForegroundColor Red
    exit 1
}
Write-Host "  Connected to: $($connection.Server)" -ForegroundColor Green

# Get all cloud snapshots
Write-Step 2 "Searching cloud snapshots for '$Name'..."

$allSnapshots = Get-VergeCloudSnapshot -IncludeExpired
if (-not $allSnapshots -or $allSnapshots.Count -eq 0) {
    Write-Host "  ERROR: No cloud snapshots found on this system." -ForegroundColor Red
    exit 1
}

Write-Host "  Found $($allSnapshots.Count) total cloud snapshots"

# Search for the target in each snapshot
$matchingSnapshots = @()

foreach ($snapshot in $allSnapshots) {
    Write-Host "  Scanning: $($snapshot.Name)..." -NoNewline

    if ($Type -eq 'VM') {
        $snapWithItems = Get-VergeCloudSnapshot -Key $snapshot.Key -IncludeVMs
        $items = $snapWithItems.VMs | Where-Object { $_.Name -like "*$Name*" }
    }
    else {
        $snapWithItems = Get-VergeCloudSnapshot -Key $snapshot.Key -IncludeTenants
        $items = $snapWithItems.Tenants | Where-Object { $_.Name -like "*$Name*" }
    }

    if ($items -and @($items).Count -gt 0) {
        Write-Host " FOUND ($(@($items).Count) matches)" -ForegroundColor Green
        $matchingSnapshots += [PSCustomObject]@{
            Snapshot = $snapWithItems
            Items    = @($items)
        }
    }
    else {
        Write-Host " none" -ForegroundColor DarkGray
    }
}

if ($matchingSnapshots.Count -eq 0) {
    Write-Host "`n  No snapshots found containing '$Name'" -ForegroundColor Red
    Write-Host "  Tip: The name search is case-insensitive and supports partial matches." -ForegroundColor Yellow
    exit 1
}

# Display matching snapshots
Write-Step 3 "Select a snapshot to restore from"

$snapshotOptions = $matchingSnapshots | ForEach-Object {
    Format-SnapshotInfo -Snapshot $_.Snapshot -ItemCount $_.Items.Count -ItemType $Type
}

$snapshotIndex = Get-UserSelection -Options $snapshotOptions -Prompt "Enter snapshot number"
if ($null -eq $snapshotIndex) {
    Write-Host "`n  Restore cancelled." -ForegroundColor Yellow
    exit 0
}

$selectedSnapshot = $matchingSnapshots[$snapshotIndex]
Write-Host "  Selected: $($selectedSnapshot.Snapshot.Name)" -ForegroundColor Green

# If multiple items match, let user select specific one
Write-Step 4 "Select the $Type to restore"

if ($selectedSnapshot.Items.Count -eq 1) {
    $selectedItem = $selectedSnapshot.Items[0]
    Write-Host "  Found: $($selectedItem.Name)" -ForegroundColor Green
}
else {
    $itemOptions = $selectedSnapshot.Items | ForEach-Object {
        if ($Type -eq 'VM') {
            "$($_.Name) | CPU: $($_.CPUCores) | RAM: $($_.RAMMB) MB"
        }
        else {
            "$($_.Name) | Nodes: $($_.Nodes) | CPU: $($_.CPUCores) | RAM: $($_.RAMMB) MB"
        }
    }

    $itemIndex = Get-UserSelection -Options $itemOptions -Prompt "Enter $Type number"
    if ($null -eq $itemIndex) {
        Write-Host "`n  Restore cancelled." -ForegroundColor Yellow
        exit 0
    }

    $selectedItem = $selectedSnapshot.Items[$itemIndex]
}

Write-Host "  Selected: $($selectedItem.Name)" -ForegroundColor Green

# Ask about restore mode
Write-Step 5 "Choose restore mode"

$restoreModes = @(
    "Restore as NEW (create a copy with new name)"
    "Restore OVER EXISTING (replace current $Type)"
)

$modeIndex = Get-UserSelection -Options $restoreModes -Prompt "Enter restore mode"
if ($null -eq $modeIndex) {
    Write-Host "`n  Restore cancelled." -ForegroundColor Yellow
    exit 0
}

$restoreAsNew = ($modeIndex -eq 0)

# Get new name if restoring as new
$newName = $null
if ($restoreAsNew) {
    Write-Host ""
    $defaultName = "$($selectedItem.Name)-restored"
    $newName = Read-Host "  Enter new name (default: $defaultName)"
    if ([string]::IsNullOrWhiteSpace($newName)) {
        $newName = $defaultName
    }
    Write-Host "  Will restore as: $newName" -ForegroundColor Green
}
else {
    Write-Host ""
    Write-Host "  WARNING: This will replace the existing $Type '$($selectedItem.Name)'" -ForegroundColor Red
    Write-Host "  The current $Type will be DELETED and replaced with the snapshot version." -ForegroundColor Red
    $confirm = Read-Host "  Type 'YES' to confirm"
    if ($confirm -ne 'YES') {
        Write-Host "`n  Restore cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# Perform the restore
Write-Step 6 "Executing restore..."

Write-Host "  Snapshot: $($selectedSnapshot.Snapshot.Name)"
Write-Host "  $Type`: $($selectedItem.Name)"
Write-Host "  Mode: $(if ($restoreAsNew) { 'New copy' } else { 'Replace existing' })"
if ($newName) {
    Write-Host "  New Name: $newName"
}
Write-Host ""

try {
    if ($Type -eq 'VM') {
        if ($restoreAsNew) {
            $result = Restore-VergeVMFromCloudSnapshot `
                -CloudSnapshotKey $selectedSnapshot.Snapshot.Key `
                -VMKey $selectedItem.Key `
                -NewName $newName `
                -Verbose
        }
        else {
            # For overwrite, we need to:
            # 1. Delete the existing VM
            # 2. Restore with the original name
            Write-Host "  Removing existing VM '$($selectedItem.Name)'..." -ForegroundColor Yellow
            $existingVM = Get-VergeVM -Name $selectedItem.Name -ErrorAction SilentlyContinue
            if ($existingVM) {
                # Stop if running
                if ($existingVM.PowerState -eq 'Running') {
                    Write-Host "  Stopping VM..." -ForegroundColor Yellow
                    Stop-VergeVM -Key $existingVM.Key -Force -Confirm:$false
                    Start-Sleep -Seconds 5
                }
                Remove-VergeVM -Key $existingVM.Key -Force -Confirm:$false
                Start-Sleep -Seconds 2
            }

            Write-Host "  Restoring from snapshot..." -ForegroundColor Yellow
            $result = Restore-VergeVMFromCloudSnapshot `
                -CloudSnapshotKey $selectedSnapshot.Snapshot.Key `
                -VMKey $selectedItem.Key `
                -Verbose
        }
    }
    else {
        # Tenant restore
        if ($restoreAsNew) {
            $result = Restore-VergeTenantFromCloudSnapshot `
                -CloudSnapshotKey $selectedSnapshot.Snapshot.Key `
                -TenantKey $selectedItem.Key `
                -NewName $newName `
                -Verbose
        }
        else {
            # For overwrite, we need to:
            # 1. Stop and delete the existing tenant
            # 2. Restore with the original name
            Write-Host "  Removing existing Tenant '$($selectedItem.Name)'..." -ForegroundColor Yellow
            $existingTenant = Get-VergeTenant -Name $selectedItem.Name -ErrorAction SilentlyContinue
            if ($existingTenant) {
                # Stop if running
                if ($existingTenant.Status -eq 'online') {
                    Write-Host "  Stopping Tenant..." -ForegroundColor Yellow
                    Stop-VergeTenant -Key $existingTenant.Key -Force -Confirm:$false
                    Start-Sleep -Seconds 10
                }
                Remove-VergeTenant -Key $existingTenant.Key -Force -Confirm:$false
                Start-Sleep -Seconds 5
            }

            Write-Host "  Restoring from snapshot..." -ForegroundColor Yellow
            $result = Restore-VergeTenantFromCloudSnapshot `
                -CloudSnapshotKey $selectedSnapshot.Snapshot.Key `
                -TenantKey $selectedItem.Key `
                -Verbose
        }
    }

    Write-Header "Restore Initiated Successfully"

    if ($result) {
        Write-Host "  Status: $($result.Status)" -ForegroundColor Green
        Write-Host "  $Type`: $($result."${Type}Name")"
        if ($result.RestoredAs) {
            Write-Host "  Restored As: $($result.RestoredAs)"
        }
        if ($result.TaskKey) {
            Write-Host "  Task ID: $($result.TaskKey)"
            Write-Host ""
            Write-Host "  Monitor progress with: Get-VergeTask -Key $($result.TaskKey)" -ForegroundColor Cyan
        }
    }

    Write-Host ""
    Write-Host "  Note: The restore operation runs asynchronously." -ForegroundColor Yellow
    Write-Host "  Use Get-VergeVM or Get-VergeTenant to check when complete." -ForegroundColor Yellow
}
catch {
    Write-Host ""
    Write-Host "  ERROR: Restore failed!" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

#endregion
