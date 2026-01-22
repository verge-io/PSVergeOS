function Restore-VergeVMSnapshot {
    <#
    .SYNOPSIS
        Restores a VergeOS virtual machine snapshot.

    .DESCRIPTION
        Restore-VergeVMSnapshot restores a VM from a snapshot. By default, it creates
        a NEW VM from the snapshot (clone). Use -ReplaceOriginal to revert the original
        VM to the snapshot state (destructive - all changes since snapshot are lost).

    .PARAMETER Snapshot
        A snapshot object from Get-VergeVMSnapshot. Accepts pipeline input.

    .PARAMETER SnapshotKey
        The key (ID) of the snapshot to restore. Alternative to pipeline input.

    .PARAMETER VMName
        The name of the VM to get the snapshot from.

    .PARAMETER VMKey
        The key (ID) of the VM to get the snapshot from.

    .PARAMETER Name
        The name of the snapshot to restore. Use with -VMName or -VMKey.

    .PARAMETER ReplaceOriginal
        Restore OVER the original VM instead of creating a new VM.
        WARNING: This reverts the original VM to snapshot state. All changes
        made after the snapshot was taken will be LOST.
        The VM must be powered off for this to work.

    .PARAMETER NewName
        The name for the restored VM (only used when creating a new VM).
        If not specified, defaults to "<SnapshotName> restored".

    .PARAMETER PowerOn
        Power on the VM after restoration.

    .PARAMETER PassThru
        Return the VM object after restoration.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Restore-VergeVMSnapshot -VMName "WebServer01" -Name "Pre-Update"

        Creates a new VM named "Pre-Update restored" from the snapshot.

    .EXAMPLE
        Restore-VergeVMSnapshot -VMName "WebServer01" -Name "Pre-Update" -ReplaceOriginal

        Reverts WebServer01 to the "Pre-Update" snapshot state (VM must be off).

    .EXAMPLE
        Restore-VergeVMSnapshot -VMName "WebServer01" -Name "Pre-Update" -NewName "WebServer01-Restored"

        Creates a new VM with a custom name from the snapshot.

    .EXAMPLE
        Get-VergeVMSnapshot -VMName "WebServer01" -Name "Pre-Update" | Restore-VergeVMSnapshot -PowerOn

        Restores using pipeline input and powers on the new VM.

    .EXAMPLE
        Restore-VergeVMSnapshot -SnapshotKey 123 -NewName "RecoveredVM"

        Restores a snapshot directly by its key to a new VM.

    .EXAMPLE
        Get-VergeVMSnapshot -VMName "Database01" | Sort-Object Created -Descending | Select-Object -First 1 | Restore-VergeVMSnapshot -ReplaceOriginal

        Reverts Database01 to its most recent snapshot.

    .OUTPUTS
        None by default. Verge.VM when -PassThru is specified.

    .NOTES
        Default behavior creates a NEW VM from the snapshot (original VM unchanged).
        Use -ReplaceOriginal to revert the original VM to snapshot state.
        When using -ReplaceOriginal, the VM must be powered off.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'BySnapshot')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'BySnapshot')]
        [PSTypeName('Verge.VMSnapshot')]
        [PSCustomObject]$Snapshot,

        [Parameter(Mandatory, ParameterSetName = 'BySnapshotKey')]
        [int]$SnapshotKey,

        [Parameter(Mandatory, ParameterSetName = 'ByVMAndName')]
        [string]$VMName,

        [Parameter(Mandatory, ParameterSetName = 'ByVMKeyAndName')]
        [int]$VMKey,

        [Parameter(Mandatory, ParameterSetName = 'ByVMAndName')]
        [Parameter(Mandatory, ParameterSetName = 'ByVMKeyAndName')]
        [string]$Name,

        [Parameter()]
        [switch]$ReplaceOriginal,

        [Parameter()]
        [ValidateLength(1, 128)]
        [string]$NewName,

        [Parameter()]
        [switch]$PowerOn,

        [Parameter()]
        [switch]$PassThru,

        [Parameter()]
        [object]$Server
    )

    begin {
        # Resolve connection
        if (-not $Server) {
            $Server = $script:DefaultConnection
        }
        if (-not $Server) {
            throw [System.InvalidOperationException]::new(
                'Not connected to VergeOS. Use Connect-VergeOS to establish a connection.'
            )
        }
    }

    process {
        # Resolve snapshot based on parameter set
        $targetSnapshot = switch ($PSCmdlet.ParameterSetName) {
            'BySnapshot' {
                $Snapshot
            }
            'BySnapshotKey' {
                # Query the snapshot directly by key
                $queryParams = @{
                    filter = "`$key eq $SnapshotKey"
                    fields = '$key,name,description,created,expires,quiesced,created_manually,machine,snap_machine'
                }
                $snapResponse = Invoke-VergeAPI -Method GET -Endpoint 'machine_snapshots' -Query $queryParams -Connection $Server
                if ($snapResponse) {
                    $snap = if ($snapResponse -is [array]) { $snapResponse[0] } else { $snapResponse }
                    # Build a minimal snapshot object
                    [PSCustomObject]@{
                        PSTypeName     = 'Verge.VMSnapshot'
                        Key            = [int]$snap.'$key'
                        Name           = $snap.name
                        SnapMachineKey = $snap.snap_machine
                        MachineKey     = $snap.machine
                    }
                }
            }
            'ByVMAndName' {
                Get-VergeVMSnapshot -VMName $VMName -Name $Name -Server $Server | Select-Object -First 1
            }
            'ByVMKeyAndName' {
                Get-VergeVMSnapshot -VMKey $VMKey -Name $Name -Server $Server | Select-Object -First 1
            }
        }

        if (-not $targetSnapshot) {
            Write-Error -Message "Snapshot not found" -ErrorId 'SnapshotNotFound'
            return
        }

        # Validate we have the snap_machine key
        if (-not $targetSnapshot.SnapMachineKey) {
            Write-Error -Message "Snapshot '$($targetSnapshot.Name)' does not have a valid snap_machine reference" -ErrorId 'InvalidSnapshot'
            return
        }

        # Handle -ReplaceOriginal mode (restore over source VM)
        if ($ReplaceOriginal) {
            # Get the original VM to check its state
            $originalVM = if ($targetSnapshot._VM) {
                $targetSnapshot._VM
            } elseif ($targetSnapshot.VMKey) {
                Get-VergeVM -Key $targetSnapshot.VMKey -Server $Server
            } else {
                $null
            }

            if (-not $originalVM) {
                Write-Error -Message "Cannot find original VM for snapshot '$($targetSnapshot.Name)'" -ErrorId 'OriginalVMNotFound'
                return
            }

            # VM must be powered off for in-place restore
            if ($originalVM.PowerState -eq 'Running') {
                Write-Error -Message "Cannot restore over VM '$($originalVM.Name)': VM must be powered off. Use Stop-VergeVM first." -ErrorId 'VMRunning'
                return
            }

            # Build action body for in-place restore
            $body = @{
                vm     = $targetSnapshot.SnapMachineKey
                action = 'restore'
            }

            $warningMessage = "This will REVERT VM '$($originalVM.Name)' to snapshot '$($targetSnapshot.Name)'. All changes since this snapshot will be PERMANENTLY LOST."
            Write-Warning $warningMessage

            if ($PSCmdlet.ShouldProcess($originalVM.Name, "Revert to snapshot '$($targetSnapshot.Name)' from $($targetSnapshot.Created)")) {
                try {
                    Write-Verbose "Reverting VM '$($originalVM.Name)' to snapshot '$($targetSnapshot.Name)'"
                    $response = Invoke-VergeAPI -Method POST -Endpoint 'vm_actions' -Body $body -Connection $Server

                    Write-Verbose "Restore command sent for VM '$($originalVM.Name)'"

                    if ($PowerOn) {
                        Write-Verbose "Powering on restored VM..."
                        Start-Sleep -Seconds 2
                        $powerBody = @{
                            vm     = $originalVM.Key
                            action = 'poweron'
                        }
                        Invoke-VergeAPI -Method POST -Endpoint 'vm_actions' -Body $powerBody -Connection $Server | Out-Null
                    }

                    if ($PassThru) {
                        Start-Sleep -Seconds 2
                        Get-VergeVM -Key $originalVM.Key -Server $Server
                    }
                }
                catch {
                    Write-Error -Message "Failed to restore VM '$($originalVM.Name)': $($_.Exception.Message)" -ErrorId 'RestoreFailed'
                }
            }
        }
        else {
            # Default mode: Clone snapshot to NEW VM
            # Determine the name for the restored VM
            $restoredVMName = if ($NewName) {
                $NewName
            } else {
                "$($targetSnapshot.Name) restored"
            }

            # Build action body - clone the snapshot VM (snap_machine)
            $body = @{
                vm     = $targetSnapshot.SnapMachineKey
                action = 'clone'
                params = @{
                    name = $restoredVMName
                }
            }

            $sourceDesc = if ($targetSnapshot.VMName) { "VM '$($targetSnapshot.VMName)'" } else { "snapshot" }

            if ($PSCmdlet.ShouldProcess($restoredVMName, "Create VM from snapshot '$($targetSnapshot.Name)' ($sourceDesc)")) {
                try {
                    Write-Verbose "Restoring snapshot '$($targetSnapshot.Name)' to new VM '$restoredVMName'"
                    $response = Invoke-VergeAPI -Method POST -Endpoint 'vm_actions' -Body $body -Connection $Server

                    Write-Verbose "Restore command sent, new VM '$restoredVMName' being created"

                    # Get the new VM key from the response
                    $newVMKey = $response.'$key' ?? $response.key

                    if ($PowerOn -and $newVMKey) {
                        Write-Verbose "Powering on restored VM..."
                        Start-Sleep -Seconds 2
                        $powerBody = @{
                            vm     = $newVMKey
                            action = 'poweron'
                        }
                        Invoke-VergeAPI -Method POST -Endpoint 'vm_actions' -Body $powerBody -Connection $Server | Out-Null
                    }

                    if ($PassThru -and $newVMKey) {
                        Start-Sleep -Seconds 2
                        Get-VergeVM -Key $newVMKey -Server $Server
                    }
                    elseif ($PassThru) {
                        # Try to find the new VM by name
                        Start-Sleep -Seconds 2
                        Get-VergeVM -Name $restoredVMName -Server $Server | Select-Object -First 1
                    }
                }
                catch {
                    Write-Error -Message "Failed to restore snapshot '$($targetSnapshot.Name)': $($_.Exception.Message)" -ErrorId 'RestoreFailed'
                }
            }
        }
    }
}
