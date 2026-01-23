function Get-VergeVolumeSnapshot {
    <#
    .SYNOPSIS
        Retrieves volume snapshots from VergeOS.

    .DESCRIPTION
        Get-VergeVolumeSnapshot retrieves snapshots of NAS volumes from VergeOS.
        You can filter by volume name, snapshot name, or retrieve all snapshots.

    .PARAMETER Volume
        The name or object of the volume to get snapshots for.

    .PARAMETER Name
        Filter snapshots by name. Supports wildcards.

    .PARAMETER Key
        Get a specific snapshot by its key.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeVolumeSnapshot -Volume "FileShare"

        Lists all snapshots for the FileShare volume.

    .EXAMPLE
        Get-VergeVolumeSnapshot -Volume "FileShare" -Name "Daily-*"

        Lists daily snapshots for the FileShare volume.

    .EXAMPLE
        Get-VergeVolume | Get-VergeVolumeSnapshot

        Lists all snapshots for all volumes.

    .OUTPUTS
        Verge.VolumeSnapshot objects containing:
        - Key: The snapshot unique identifier
        - Name: Snapshot name
        - VolumeName: Parent volume name
        - Description: Snapshot description
        - Created: Creation timestamp
        - Expires: Expiration timestamp
        - CreatedManually: Whether snapshot was created manually

    .NOTES
        Volume snapshots can be mounted as separate volumes using the
        automount_snapshots option on the parent volume.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByVolume')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ParameterSetName = 'ByVolume', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('VolumeName')]
        [object]$Volume,

        [Parameter(ParameterSetName = 'ByVolume')]
        [SupportsWildcards()]
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
        try {
            $queryParams = @{}
            $filters = [System.Collections.Generic.List[string]]::new()

            if ($PSCmdlet.ParameterSetName -eq 'ByKey') {
                $queryParams['filter'] = "`$key eq $Key"
            }
            else {
                # Resolve volume if provided
                if ($Volume) {
                    $volumeKey = $null
                    if ($Volume -is [string]) {
                        # Look up volume by name
                        $volumeData = Get-VergeVolume -Name $Volume -Server $Server
                        if (-not $volumeData) {
                            throw "Volume '$Volume' not found"
                        }
                        $volumeKey = $volumeData.Key
                    }
                    elseif ($Volume.Key) {
                        $volumeKey = $Volume.Key
                    }
                    elseif ($Volume -is [int]) {
                        $volumeKey = $Volume
                    }

                    if ($volumeKey) {
                        $filters.Add("volume eq $volumeKey")
                    }
                }

                # Filter by name
                if ($Name) {
                    if ($Name -match '[\*\?]') {
                        $searchTerm = $Name -replace '[\*\?]', ''
                        if ($searchTerm) {
                            $filters.Add("name ct '$searchTerm'")
                        }
                    }
                    else {
                        $filters.Add("name eq '$Name'")
                    }
                }

                if ($filters.Count -gt 0) {
                    $queryParams['filter'] = $filters -join ' and '
                }
            }

            # Select fields
            $queryParams['fields'] = @(
                '$key'
                'name'
                'description'
                'created'
                'expires'
                'expires_type'
                'enabled'
                'created_manually'
                'quiesce'
                'volume'
                'volume#$display as volume_display'
                'volume#name as volume_name'
                'snap_volume'
            ) -join ','

            Write-Verbose "Querying volume snapshots"
            $response = Invoke-VergeAPI -Method GET -Endpoint 'volume_snapshots' -Query $queryParams -Connection $Server

            $snapshots = if ($response -is [array]) { $response } else { @($response) }

            foreach ($snapshot in $snapshots) {
                if (-not $snapshot -or -not $snapshot.name) {
                    continue
                }

                # Convert timestamps
                $created = $null
                if ($snapshot.created) {
                    $created = [DateTimeOffset]::FromUnixTimeSeconds($snapshot.created).LocalDateTime
                }
                $expires = $null
                if ($snapshot.expires -and $snapshot.expires -gt 0) {
                    $expires = [DateTimeOffset]::FromUnixTimeSeconds($snapshot.expires).LocalDateTime
                }

                [PSCustomObject]@{
                    PSTypeName       = 'Verge.VolumeSnapshot'
                    Key              = $snapshot.'$key'
                    Name             = $snapshot.name
                    Description      = $snapshot.description
                    VolumeName       = $snapshot.volume_name ?? $snapshot.volume_display
                    VolumeKey        = $snapshot.volume
                    SnapVolumeKey    = $snapshot.snap_volume
                    Created          = $created
                    Expires          = $expires
                    ExpiresType      = $snapshot.expires_type
                    NeverExpires     = ($snapshot.expires_type -eq 'never' -or $snapshot.expires -eq 0)
                    Enabled          = [bool]$snapshot.enabled
                    CreatedManually  = [bool]$snapshot.created_manually
                    Quiesced         = [bool]$snapshot.quiesce
                }
            }
        }
        catch {
            Write-Error -Message "Failed to get volume snapshots: $($_.Exception.Message)" -ErrorId 'GetVolumeSnapshotsFailed'
        }
    }
}
