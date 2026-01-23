function Set-VergeNASVolume {
    <#
    .SYNOPSIS
        Modifies an existing NAS volume in VergeOS.

    .DESCRIPTION
        Set-VergeNASVolume modifies the configuration of an existing NAS volume.
        You can change the description, size, tier, and other settings.

    .PARAMETER Name
        The name of the volume to modify.

    .PARAMETER Key
        The unique key (ID) of the volume to modify.

    .PARAMETER Volume
        A volume object from Get-VergeNASVolume.

    .PARAMETER Description
        New description for the volume.

    .PARAMETER SizeGB
        New maximum size in gigabytes.

    .PARAMETER Tier
        New preferred storage tier (1-5).

    .PARAMETER Enabled
        Enable or disable the volume.

    .PARAMETER ReadOnly
        Set the volume to read-only or read-write.

    .PARAMETER Discard
        Enable or disable automatic discard of deleted files.

    .PARAMETER OwnerUser
        New owner user for the volume directory.

    .PARAMETER OwnerGroup
        New owner group for the volume directory.

    .PARAMETER SnapshotProfile
        New snapshot profile for the volume.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Set-VergeNASVolume -Name "FileShare" -SizeGB 1000

        Increases the FileShare volume to 1TB.

    .EXAMPLE
        Get-VergeNASVolume -Name "Archive" | Set-VergeNASVolume -Tier 3

        Changes the Archive volume to tier 3 storage.

    .EXAMPLE
        Set-VergeNASVolume -Name "OldData" -Enabled $false

        Disables a volume.

    .OUTPUTS
        Verge.Volume object representing the modified volume.

    .NOTES
        Some changes may require the volume to be unmounted first.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [string]$Key,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [PSTypeName('Verge.NASVolume')]
        [PSCustomObject]$Volume,

        [Parameter()]
        [ValidateLength(0, 2048)]
        [string]$Description,

        [Parameter()]
        [Alias('Size', 'MaxSize')]
        [ValidateRange(1, 524288)]
        [int]$SizeGB,

        [Parameter()]
        [ValidateRange(1, 5)]
        [int]$Tier,

        [Parameter()]
        [bool]$Enabled,

        [Parameter()]
        [bool]$ReadOnly,

        [Parameter()]
        [bool]$Discard,

        [Parameter()]
        [string]$OwnerUser,

        [Parameter()]
        [string]$OwnerGroup,

        [Parameter()]
        [object]$SnapshotProfile,

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
            # Resolve volume to key
            $volumeKey = $null
            $volumeName = $null

            switch ($PSCmdlet.ParameterSetName) {
                'ByKey' {
                    $volumeKey = $Key
                }
                'ByName' {
                    $volumeName = $Name
                    $existingVolume = Get-VergeNASVolume -Name $Name -Server $Server
                    if (-not $existingVolume) {
                        throw "Volume '$Name' not found"
                    }
                    $volumeKey = $existingVolume.Key
                    $volumeName = $existingVolume.Name
                }
                'ByObject' {
                    $volumeKey = $Volume.Key
                    $volumeName = $Volume.Name
                }
            }

            if (-not $volumeKey) {
                throw "Could not resolve volume key"
            }

            # Build request body with only changed properties
            $body = @{}

            if ($PSBoundParameters.ContainsKey('Description')) {
                $body['description'] = $Description
            }

            if ($PSBoundParameters.ContainsKey('SizeGB')) {
                $body['maxsize'] = $SizeGB * 1073741824
            }

            if ($PSBoundParameters.ContainsKey('Tier')) {
                $body['preferred_tier'] = $Tier.ToString()
            }

            if ($PSBoundParameters.ContainsKey('Enabled')) {
                $body['enabled'] = $Enabled
            }

            if ($PSBoundParameters.ContainsKey('ReadOnly')) {
                $body['read_only'] = $ReadOnly
            }

            if ($PSBoundParameters.ContainsKey('Discard')) {
                $body['discard'] = $Discard
            }

            if ($PSBoundParameters.ContainsKey('OwnerUser')) {
                $body['owner_user'] = $OwnerUser
            }

            if ($PSBoundParameters.ContainsKey('OwnerGroup')) {
                $body['owner_group'] = $OwnerGroup
            }

            if ($PSBoundParameters.ContainsKey('SnapshotProfile')) {
                if ($null -eq $SnapshotProfile) {
                    $body['snapshot_profile'] = $null
                }
                elseif ($SnapshotProfile -is [int]) {
                    $body['snapshot_profile'] = $SnapshotProfile
                }
                elseif ($SnapshotProfile.Key) {
                    $body['snapshot_profile'] = $SnapshotProfile.Key
                }
            }

            if ($body.Count -eq 0) {
                Write-Warning "No changes specified for volume '$volumeName'"
                return
            }

            $displayName = $volumeName ?? $volumeKey
            if ($PSCmdlet.ShouldProcess("Volume '$displayName'", 'Modify')) {
                Write-Verbose "Modifying volume '$displayName' (key: $volumeKey)"
                $null = Invoke-VergeAPI -Method PUT -Endpoint "volumes/$volumeKey" -Body $body -Connection $Server

                # Return the updated volume
                Get-VergeNASVolume -Key $volumeKey -Server $Server
            }
        }
        catch {
            $displayName = $volumeName ?? $volumeKey ?? 'unknown'
            Write-Error -Message "Failed to modify volume '$displayName': $($_.Exception.Message)" -ErrorId 'SetVolumeFailed'
        }
    }
}
