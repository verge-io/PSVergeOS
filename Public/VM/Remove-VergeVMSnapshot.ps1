function Remove-VergeVMSnapshot {
    <#
    .SYNOPSIS
        Removes a snapshot from a VergeOS virtual machine.

    .DESCRIPTION
        Remove-VergeVMSnapshot permanently deletes one or more VM snapshots.
        This operation cannot be undone.

    .PARAMETER Snapshot
        A snapshot object from Get-VergeVMSnapshot. Accepts pipeline input.

    .PARAMETER VMName
        The name of the VM that owns the snapshot.

    .PARAMETER VMKey
        The key (ID) of the VM that owns the snapshot.

    .PARAMETER Name
        The name of the snapshot to remove. Use with -VMName or -VMKey.

    .PARAMETER Key
        The key (ID) of the snapshot to remove.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeVMSnapshot -VMName "WebServer01" -Name "Pre-Update"

        Removes the snapshot named "Pre-Update" from the specified VM.

    .EXAMPLE
        Get-VergeVMSnapshot -VMName "WebServer01" | Remove-VergeVMSnapshot

        Removes all snapshots for the VM (with confirmation for each).

    .EXAMPLE
        Get-VergeVM | Get-VergeVMSnapshot | Where-Object { $_.Expires -lt (Get-Date) } | Remove-VergeVMSnapshot -Confirm:$false

        Removes all expired snapshots without confirmation.

    .EXAMPLE
        Remove-VergeVMSnapshot -Key 123 -Confirm:$false

        Removes a snapshot by its key without confirmation.

    .OUTPUTS
        None.

    .NOTES
        This is a destructive operation that cannot be undone.
        Consider using Get-VergeVMSnapshot to verify which snapshots will be affected.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'BySnapshot')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'BySnapshot')]
        [PSTypeName('Verge.VMSnapshot')]
        [PSCustomObject]$Snapshot,

        [Parameter(Mandatory, ParameterSetName = 'ByVMAndName')]
        [string]$VMName,

        [Parameter(Mandatory, ParameterSetName = 'ByVMKeyAndName')]
        [int]$VMKey,

        [Parameter(Mandatory, ParameterSetName = 'ByVMAndName')]
        [Parameter(Mandatory, ParameterSetName = 'ByVMKeyAndName')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

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
        $snapshotsToRemove = switch ($PSCmdlet.ParameterSetName) {
            'BySnapshot' {
                $Snapshot
            }
            'ByVMAndName' {
                Get-VergeVMSnapshot -VMName $VMName -Name $Name -Server $Server
            }
            'ByVMKeyAndName' {
                Get-VergeVMSnapshot -VMKey $VMKey -Name $Name -Server $Server
            }
            'ByKey' {
                # Query directly by key
                try {
                    $response = Invoke-VergeAPI -Method GET -Endpoint "machine_snapshots/$Key" -Connection $Server
                    if ($response) {
                        [PSCustomObject]@{
                            Key    = $Key
                            Name   = $response.name
                            VMName = 'Unknown'
                        }
                    }
                }
                catch {
                    Write-Error -Message "Snapshot with key $Key not found" -ErrorId 'SnapshotNotFound'
                    return
                }
            }
        }

        foreach ($targetSnapshot in $snapshotsToRemove) {
            if (-not $targetSnapshot) {
                continue
            }

            $snapshotKey = $targetSnapshot.Key
            $snapshotName = $targetSnapshot.Name
            $vmName = if ($targetSnapshot.VMName) { $targetSnapshot.VMName } else { 'Unknown' }

            if ($PSCmdlet.ShouldProcess("$snapshotName (VM: $vmName)", 'Remove snapshot')) {
                try {
                    Write-Verbose "Removing snapshot '$snapshotName' (Key: $snapshotKey) from VM '$vmName'"
                    Invoke-VergeAPI -Method DELETE -Endpoint "machine_snapshots/$snapshotKey" -Connection $Server | Out-Null
                    Write-Verbose "Snapshot '$snapshotName' removed successfully"
                }
                catch {
                    Write-Error -Message "Failed to remove snapshot '$snapshotName': $($_.Exception.Message)" -ErrorId 'SnapshotRemoveFailed'
                }
            }
        }
    }
}
