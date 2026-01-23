function Set-VergeSnapshotProfile {
    <#
    .SYNOPSIS
        Modifies an existing snapshot profile in VergeOS.

    .DESCRIPTION
        Set-VergeSnapshotProfile modifies the properties of an existing snapshot profile.
        You can update the name, description, and warning settings.

    .PARAMETER Profile
        A snapshot profile object from Get-VergeSnapshotProfile. Accepts pipeline input.

    .PARAMETER Key
        The key (ID) of the snapshot profile to modify.

    .PARAMETER Name
        The new name for the snapshot profile.

    .PARAMETER Description
        The new description for the snapshot profile.

    .PARAMETER IgnoreWarnings
        Whether to ignore warnings about snapshot count estimates.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Set-VergeSnapshotProfile -Key 6 -Description "Updated description"

        Updates the description of the snapshot profile with key 6.

    .EXAMPLE
        Get-VergeSnapshotProfile -Name "Test Profile" | Set-VergeSnapshotProfile -Name "Production Profile"

        Renames a snapshot profile using pipeline input.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.SnapshotProfile'

    .NOTES
        To modify schedule periods, use the snapshot_profile_periods API directly or
        remove and recreate periods as needed.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByKey')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [PSTypeName('Verge.SnapshotProfile')]
        [PSCustomObject]$Profile,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter()]
        [ValidateLength(1, 128)]
        [string]$Name,

        [Parameter()]
        [ValidateLength(0, 2048)]
        [string]$Description,

        [Parameter()]
        [bool]$IgnoreWarnings,

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
        # Get the profile key
        $profileKey = if ($PSCmdlet.ParameterSetName -eq 'ByObject') {
            $Profile.Key
        } else {
            $Key
        }

        # Get current profile name for ShouldProcess
        $currentProfile = Get-VergeSnapshotProfile -Key $profileKey -Server $Server
        if (-not $currentProfile) {
            Write-Error -Message "Snapshot profile with key $profileKey not found" -ErrorId 'ProfileNotFound'
            return
        }

        $displayName = $currentProfile.Name

        if ($PSCmdlet.ShouldProcess("Snapshot Profile '$displayName' (Key: $profileKey)", 'Modify')) {
            # Build request body with only changed properties
            $body = @{}

            if ($PSBoundParameters.ContainsKey('Name')) {
                $body['name'] = $Name
            }

            if ($PSBoundParameters.ContainsKey('Description')) {
                $body['description'] = $Description
            }

            if ($PSBoundParameters.ContainsKey('IgnoreWarnings')) {
                $body['ignore_warnings'] = $IgnoreWarnings
            }

            if ($body.Count -eq 0) {
                Write-Warning "No changes specified for snapshot profile '$displayName'"
                return $currentProfile
            }

            try {
                Write-Verbose "Updating snapshot profile '$displayName' (Key: $profileKey)"
                $null = Invoke-VergeAPI -Method PUT -Endpoint "snapshot_profiles/$profileKey" -Body $body -Connection $Server

                # Return the updated profile
                Get-VergeSnapshotProfile -Key $profileKey -Server $Server
            }
            catch {
                Write-Error -Message "Failed to update snapshot profile '$displayName': $($_.Exception.Message)" -ErrorId 'UpdateSnapshotProfileFailed'
            }
        }
    }
}
