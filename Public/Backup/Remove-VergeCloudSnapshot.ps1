function Remove-VergeCloudSnapshot {
    <#
    .SYNOPSIS
        Removes a cloud (system) snapshot from VergeOS.

    .DESCRIPTION
        Remove-VergeCloudSnapshot deletes a cloud snapshot from the VergeOS system.
        Immutable snapshots cannot be deleted until they are unlocked.

    .PARAMETER CloudSnapshot
        A cloud snapshot object from Get-VergeCloudSnapshot. Accepts pipeline input.

    .PARAMETER Key
        The key (ID) of the cloud snapshot to remove.

    .PARAMETER Name
        The name of the cloud snapshot to remove.

    .PARAMETER Force
        Bypasses the confirmation prompt.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeCloudSnapshot -Name "PSTest-CloudSnap-20260123"

        Removes the specified cloud snapshot with confirmation.

    .EXAMPLE
        Remove-VergeCloudSnapshot -Key 2 -Force

        Removes the cloud snapshot with key 2 without confirmation.

    .EXAMPLE
        Get-VergeCloudSnapshot -Name "PSTest*" | Remove-VergeCloudSnapshot -Force

        Removes all cloud snapshots matching "PSTest*" without confirmation.

    .NOTES
        Cannot remove immutable snapshots until they are unlocked.
        Use caution when removing cloud snapshots as they cannot be recovered.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [PSTypeName('Verge.CloudSnapshot')]
        [PSCustomObject]$CloudSnapshot,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
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

        # Override confirmation if Force is specified
        if ($Force -and -not $PSBoundParameters.ContainsKey('Confirm')) {
            $ConfirmPreference = 'None'
        }
    }

    process {
        # Resolve the cloud snapshot
        $targetSnapshot = switch ($PSCmdlet.ParameterSetName) {
            'ByObject' { $CloudSnapshot }
            'ByKey' { Get-VergeCloudSnapshot -Key $Key -IncludeExpired -Server $Server }
            'ByName' { Get-VergeCloudSnapshot -Name $Name -IncludeExpired -Server $Server }
        }

        if (-not $targetSnapshot) {
            $identifier = if ($Key) { "Key: $Key" } else { "Name: $Name" }
            Write-Error -Message "Cloud snapshot not found ($identifier)" -ErrorId 'CloudSnapshotNotFound'
            return
        }

        # Handle multiple snapshots (from wildcard)
        $snapshots = @($targetSnapshot)
        foreach ($snap in $snapshots) {
            $displayName = $snap.Name
            $snapshotKey = $snap.Key

            # Check if immutable
            if ($snap.Immutable -and $snap.ImmutableStatus -eq 'locked') {
                Write-Error -Message "Cannot remove immutable cloud snapshot '$displayName' (Key: $snapshotKey) while locked" -ErrorId 'SnapshotImmutable'
                continue
            }

            if ($PSCmdlet.ShouldProcess("Cloud Snapshot '$displayName' (Key: $snapshotKey)", 'Remove')) {
                try {
                    Write-Verbose "Removing cloud snapshot '$displayName' (Key: $snapshotKey)"

                    # DELETE the cloud snapshot
                    $null = Invoke-VergeAPI -Method DELETE -Endpoint "cloud_snapshots/$snapshotKey" -Connection $Server

                    Write-Verbose "Successfully removed cloud snapshot '$displayName'"
                }
                catch {
                    Write-Error -Message "Failed to remove cloud snapshot '$displayName': $($_.Exception.Message)" -ErrorId 'RemoveCloudSnapshotFailed'
                }
            }
        }
    }
}
