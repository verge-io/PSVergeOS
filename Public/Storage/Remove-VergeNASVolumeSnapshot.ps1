function Remove-VergeNASVolumeSnapshot {
    <#
    .SYNOPSIS
        Removes a volume snapshot from VergeOS.

    .DESCRIPTION
        Remove-VergeNASVolumeSnapshot deletes a snapshot of a NAS volume.
        This operation cannot be undone.

    .PARAMETER Key
        The unique key of the snapshot to remove.

    .PARAMETER Snapshot
        A snapshot object from Get-VergeNASVolumeSnapshot.

    .PARAMETER Volume
        The volume name or object, combined with -Name to identify the snapshot.

    .PARAMETER Name
        The name of the snapshot to remove (requires -Volume).

    .PARAMETER Force
        Bypasses the confirmation prompt.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeNASVolumeSnapshot -Volume "FileShare" -Name "OldSnapshot"

        Removes a specific snapshot by volume and name.

    .EXAMPLE
        Get-VergeNASVolumeSnapshot -Volume "FileShare" | Where-Object { $_.Created -lt (Get-Date).AddDays(-30) } | Remove-VergeNASVolumeSnapshot -Force

        Removes all snapshots older than 30 days.

    .EXAMPLE
        Remove-VergeNASVolumeSnapshot -Key 123 -Force

        Removes a snapshot by key without confirmation.

    .NOTES
        Snapshots that are in use by mounted snapshot volumes cannot be deleted
        until those volumes are unmounted.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByVolumeAndName')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [PSTypeName('Verge.NASVolumeSnapshot')]
        [PSCustomObject]$Snapshot,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByVolumeAndName')]
        [object]$Volume,

        [Parameter(Mandatory, Position = 1, ParameterSetName = 'ByVolumeAndName')]
        [string]$Name,

        [Parameter()]
        [switch]$Force,

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
        try {
            $snapshotKey = $null
            $snapshotName = $null

            switch ($PSCmdlet.ParameterSetName) {
                'ByKey' {
                    $snapshotKey = $Key
                }
                'ByObject' {
                    $snapshotKey = $Snapshot.Key
                    $snapshotName = $Snapshot.Name
                }
                'ByVolumeAndName' {
                    $snapshotData = Get-VergeNASVolumeSnapshot -Volume $Volume -Name $Name -Server $Server
                    if (-not $snapshotData) {
                        throw "Snapshot '$Name' not found for volume '$Volume'"
                    }
                    $snapshotKey = $snapshotData.Key
                    $snapshotName = $snapshotData.Name
                }
            }

            if (-not $snapshotKey) {
                throw "Could not resolve snapshot key"
            }

            $displayName = $snapshotName ?? "Key: $snapshotKey"
            $shouldProcess = $Force -or $PSCmdlet.ShouldProcess(
                "Volume snapshot '$displayName'",
                'Remove'
            )

            if ($shouldProcess) {
                Write-Verbose "Removing volume snapshot '$displayName'"
                $null = Invoke-VergeAPI -Method DELETE -Endpoint "volume_snapshots/$snapshotKey" -Connection $Server
                Write-Verbose "Snapshot '$displayName' removed successfully"
            }
        }
        catch {
            $displayName = $snapshotName ?? $snapshotKey ?? 'unknown'
            Write-Error -Message "Failed to remove snapshot '$displayName': $($_.Exception.Message)" -ErrorId 'RemoveVolumeSnapshotFailed'
        }
    }
}
