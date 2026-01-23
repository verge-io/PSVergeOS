function Remove-VergeSnapshotProfile {
    <#
    .SYNOPSIS
        Removes a snapshot profile from VergeOS.

    .DESCRIPTION
        Remove-VergeSnapshotProfile deletes a snapshot profile from the VergeOS system.
        The profile must not be in use by any VMs, volumes, or cloud snapshots.

    .PARAMETER Profile
        A snapshot profile object from Get-VergeSnapshotProfile. Accepts pipeline input.

    .PARAMETER Key
        The key (ID) of the snapshot profile to remove.

    .PARAMETER Name
        The name of the snapshot profile to remove.

    .PARAMETER Force
        Bypasses the confirmation prompt.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeSnapshotProfile -Name "Test Profile"

        Removes the snapshot profile named "Test Profile" with confirmation.

    .EXAMPLE
        Remove-VergeSnapshotProfile -Key 6 -Force

        Removes the snapshot profile with key 6 without confirmation.

    .EXAMPLE
        Get-VergeSnapshotProfile -Name "PSTest*" | Remove-VergeSnapshotProfile -Force

        Removes all snapshot profiles matching "PSTest*" without confirmation.

    .NOTES
        Cannot remove profiles that are assigned to VMs, volumes, or cloud snapshot schedules.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [PSTypeName('Verge.SnapshotProfile')]
        [PSCustomObject]$Profile,

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
        # Resolve the profile
        $targetProfile = switch ($PSCmdlet.ParameterSetName) {
            'ByObject' { $Profile }
            'ByKey' { Get-VergeSnapshotProfile -Key $Key -Server $Server }
            'ByName' { Get-VergeSnapshotProfile -Name $Name -Server $Server }
        }

        if (-not $targetProfile) {
            $identifier = if ($Key) { "Key: $Key" } else { "Name: $Name" }
            Write-Error -Message "Snapshot profile not found ($identifier)" -ErrorId 'ProfileNotFound'
            return
        }

        # Handle multiple profiles (from wildcard)
        $profiles = @($targetProfile)
        foreach ($prof in $profiles) {
            $displayName = $prof.Name
            $profileKey = $prof.Key

            if ($PSCmdlet.ShouldProcess("Snapshot Profile '$displayName' (Key: $profileKey)", 'Remove')) {
                try {
                    Write-Verbose "Removing snapshot profile '$displayName' (Key: $profileKey)"

                    # Use the snapshot_profile_actions endpoint with delete action
                    $body = @{
                        snapshot_profile = $profileKey
                        action = 'delete'
                    }

                    $null = Invoke-VergeAPI -Method POST -Endpoint 'snapshot_profile_actions' -Body $body -Connection $Server

                    Write-Verbose "Successfully removed snapshot profile '$displayName'"
                }
                catch {
                    Write-Error -Message "Failed to remove snapshot profile '$displayName': $($_.Exception.Message)" -ErrorId 'RemoveSnapshotProfileFailed'
                }
            }
        }
    }
}
