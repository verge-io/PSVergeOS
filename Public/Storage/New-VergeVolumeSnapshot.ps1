function New-VergeVolumeSnapshot {
    <#
    .SYNOPSIS
        Creates a snapshot of a NAS volume in VergeOS.

    .DESCRIPTION
        New-VergeVolumeSnapshot creates a point-in-time snapshot of a NAS volume.
        Snapshots can be used for backup purposes or to restore the volume to
        a previous state.

    .PARAMETER Volume
        The name or object of the volume to snapshot.

    .PARAMETER Name
        The name for the new snapshot.

    .PARAMETER Description
        Optional description for the snapshot.

    .PARAMETER ExpiresInDays
        Number of days until the snapshot expires. Defaults to 3 days.
        Use -NeverExpires to create a permanent snapshot.

    .PARAMETER NeverExpires
        If specified, the snapshot will never automatically expire.

    .PARAMETER Quiesce
        If specified, temporarily freezes I/O to the volume while the
        snapshot is taken for consistency.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeVolumeSnapshot -Volume "FileShare" -Name "Pre-Update"

        Creates a snapshot named "Pre-Update" for the FileShare volume.

    .EXAMPLE
        New-VergeVolumeSnapshot -Volume "FileShare" -Name "Daily-$(Get-Date -Format 'yyyyMMdd')"

        Creates a daily snapshot with today's date in the name.

    .EXAMPLE
        New-VergeVolumeSnapshot -Volume "Database" -Name "Before-Migration" -Quiesce -NeverExpires

        Creates a quiesced, permanent snapshot.

    .EXAMPLE
        Get-VergeVolume -Name "Prod-*" | ForEach-Object {
            New-VergeVolumeSnapshot -Volume $_ -Name "Backup-$(Get-Date -Format 'yyyyMMdd')"
        }

        Creates snapshots for all production volumes.

    .OUTPUTS
        Verge.VolumeSnapshot object representing the created snapshot.

    .NOTES
        Snapshots are stored on the same tier as the parent volume.
        Consider storage capacity when creating many snapshots.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [Alias('VolumeName')]
        [object]$Volume,

        [Parameter(Mandatory, Position = 1)]
        [ValidateLength(1, 128)]
        [string]$Name,

        [Parameter()]
        [ValidateLength(0, 2048)]
        [string]$Description,

        [Parameter()]
        [ValidateRange(1, 3650)]
        [int]$ExpiresInDays = 3,

        [Parameter()]
        [switch]$NeverExpires,

        [Parameter()]
        [switch]$Quiesce,

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

            if ($Volume -is [string]) {
                $volumeName = $Volume
                $volumeData = Get-VergeVolume -Name $Volume -Server $Server
                if (-not $volumeData) {
                    throw "Volume '$Volume' not found"
                }
                $volumeKey = $volumeData.Key
                $volumeName = $volumeData.Name
            }
            elseif ($Volume.Key) {
                $volumeKey = $Volume.Key
                $volumeName = $Volume.Name
            }
            elseif ($Volume -is [int]) {
                $volumeKey = $Volume
            }

            if (-not $volumeKey) {
                throw "Could not resolve volume key"
            }

            # Build request body
            $body = @{
                volume = $volumeKey
                name   = $Name
            }

            if ($Description) {
                $body['description'] = $Description
            }

            if ($NeverExpires) {
                $body['expires_type'] = 'never'
                $body['expires'] = 0
            }
            else {
                $body['expires_type'] = 'date'
                # Calculate expiration as Unix timestamp
                $expiresAt = [DateTimeOffset]::Now.AddDays($ExpiresInDays)
                $body['expires'] = $expiresAt.ToUnixTimeSeconds()
            }

            if ($Quiesce) {
                $body['quiesce'] = $true
            }

            $body['created_manually'] = $true

            $displayName = $volumeName ?? $volumeKey
            if ($PSCmdlet.ShouldProcess("Volume '$displayName'", "Create snapshot '$Name'")) {
                Write-Verbose "Creating snapshot '$Name' for volume '$displayName'"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'volume_snapshots' -Body $body -Connection $Server

                # Return the created snapshot
                if ($response.'$key') {
                    Get-VergeVolumeSnapshot -Key $response.'$key' -Server $Server
                }
                else {
                    # Try to find by name
                    Get-VergeVolumeSnapshot -Volume $volumeKey -Name $Name -Server $Server
                }
            }
        }
        catch {
            $displayName = $volumeName ?? $volumeKey ?? 'unknown'
            Write-Error -Message "Failed to create snapshot for volume '$displayName': $($_.Exception.Message)" -ErrorId 'NewVolumeSnapshotFailed'
        }
    }
}
