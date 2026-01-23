function New-VergeVolume {
    <#
    .SYNOPSIS
        Creates a new NAS volume in VergeOS.

    .DESCRIPTION
        New-VergeVolume creates a new NAS volume on a specified NAS service.
        Volumes are virtual filesystems that can be shared via CIFS/SMB or NFS.

    .PARAMETER Name
        The name for the new volume. Must be alphanumeric with underscores/hyphens only.

    .PARAMETER NASService
        The NAS service to create the volume on. Can be a service name or key.

    .PARAMETER SizeGB
        The maximum size of the volume in gigabytes.

    .PARAMETER Tier
        The preferred storage tier (1-5). Defaults to the system default.

    .PARAMETER Description
        Optional description for the volume.

    .PARAMETER ReadOnly
        If specified, creates the volume as read-only.

    .PARAMETER Discard
        If specified, enables automatic discard of deleted files. Defaults to true.

    .PARAMETER OwnerUser
        The user that owns the volume directory.

    .PARAMETER OwnerGroup
        The group that owns the volume directory.

    .PARAMETER SnapshotProfile
        The snapshot profile to apply to this volume.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeVolume -Name "FileShare" -NASService "nas01" -SizeGB 500

        Creates a 500GB volume named FileShare on the nas01 service.

    .EXAMPLE
        New-VergeVolume -Name "Archive" -NASService "nas01" -SizeGB 2000 -Tier 3

        Creates a 2TB volume on storage tier 3.

    .EXAMPLE
        New-VergeVolume -Name "ReadOnlyData" -NASService "nas01" -SizeGB 100 -ReadOnly

        Creates a read-only volume.

    .OUTPUTS
        Verge.Volume object representing the created volume.

    .NOTES
        Volumes require a NAS service VM to be running. Use Get-VergeVM to find
        available NAS services in your environment.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidatePattern('^[a-zA-Z0-9_][a-zA-Z0-9_-]*$')]
        [ValidateLength(1, 128)]
        [string]$Name,

        [Parameter(Mandatory)]
        [Alias('Service')]
        [object]$NASService,

        [Parameter(Mandatory)]
        [Alias('Size', 'MaxSize')]
        [ValidateRange(1, 524288)]
        [int]$SizeGB,

        [Parameter()]
        [ValidateRange(1, 5)]
        [int]$Tier,

        [Parameter()]
        [ValidateLength(0, 2048)]
        [string]$Description,

        [Parameter()]
        [switch]$ReadOnly,

        [Parameter()]
        [bool]$Discard = $true,

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
            # Resolve NAS service to key
            $serviceKey = $null
            if ($NASService -is [int]) {
                $serviceKey = $NASService
            }
            elseif ($NASService -is [string]) {
                # Look up service by name - vm_services is the table for NAS services
                Write-Verbose "Looking up NAS service: $NASService"
                $serviceResponse = Invoke-VergeAPI -Method GET -Endpoint 'vm_services' -Query @{
                    filter = "name eq '$NASService'"
                    fields = '$key,name'
                } -Connection $Server

                if (-not $serviceResponse -or ($serviceResponse -is [array] -and $serviceResponse.Count -eq 0)) {
                    throw "NAS service '$NASService' not found"
                }

                $serviceData = if ($serviceResponse -is [array]) { $serviceResponse[0] } else { $serviceResponse }
                $serviceKey = $serviceData.'$key'
            }
            elseif ($NASService.Key) {
                $serviceKey = $NASService.Key
            }
            else {
                throw "Invalid NASService parameter. Provide a service name, key, or object."
            }

            if (-not $serviceKey) {
                throw "Could not resolve NAS service key"
            }

            # Build request body
            $body = @{
                name    = $Name
                service = $serviceKey
                maxsize = $SizeGB * 1073741824  # Convert GB to bytes
                enabled = $true
                discard = $Discard
            }

            if ($Tier) {
                $body['preferred_tier'] = $Tier.ToString()
            }

            if ($Description) {
                $body['description'] = $Description
            }

            if ($ReadOnly) {
                $body['read_only'] = $true
            }

            if ($OwnerUser) {
                $body['owner_user'] = $OwnerUser
            }

            if ($OwnerGroup) {
                $body['owner_group'] = $OwnerGroup
            }

            if ($SnapshotProfile) {
                if ($SnapshotProfile -is [int]) {
                    $body['snapshot_profile'] = $SnapshotProfile
                }
                elseif ($SnapshotProfile.Key) {
                    $body['snapshot_profile'] = $SnapshotProfile.Key
                }
            }

            if ($PSCmdlet.ShouldProcess("Volume '$Name'", 'Create')) {
                Write-Verbose "Creating volume '$Name' on service $serviceKey"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'volumes' -Body $body -Connection $Server

                # Return the created volume
                if ($response.'$key' -or $response.id) {
                    $volumeKey = $response.'$key' ?? $response.id
                    Get-VergeVolume -Key $volumeKey -Server $Server
                }
                else {
                    Write-Verbose "Volume created, fetching by name"
                    Get-VergeVolume -Name $Name -Server $Server
                }
            }
        }
        catch {
            Write-Error -Message "Failed to create volume '$Name': $($_.Exception.Message)" -ErrorId 'NewVolumeFailed'
        }
    }
}
