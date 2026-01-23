function Get-VergeNASCIFSShare {
    <#
    .SYNOPSIS
        Retrieves CIFS/SMB shares from VergeOS.

    .DESCRIPTION
        Get-VergeNASCIFSShare retrieves CIFS (SMB) file shares from a VergeOS system.
        You can filter by volume, share name, or retrieve all shares.

    .PARAMETER Volume
        The name or object of the volume to get shares for.

    .PARAMETER Name
        Filter shares by name. Supports wildcards.

    .PARAMETER Key
        Get a specific share by its key.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeNASCIFSShare

        Lists all CIFS shares.

    .EXAMPLE
        Get-VergeNASCIFSShare -Volume "FileShare"

        Lists CIFS shares on the FileShare volume.

    .EXAMPLE
        Get-VergeNASVolume | Get-VergeNASCIFSShare

        Lists all CIFS shares for all volumes.

    .OUTPUTS
        Verge.CIFSShare objects containing:
        - Key: The share unique identifier
        - Name: Share name
        - VolumeName: Parent volume name
        - SharePath: Path within the volume being shared
        - Enabled: Whether the share is enabled
        - ReadOnly: Whether the share is read-only
        - GuestOK: Whether guest access is allowed

    .NOTES
        CIFS shares provide Windows-compatible file sharing.
        Also known as SMB (Server Message Block) shares.
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
        [string]$Key,

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
                $queryParams['filter'] = "id eq '$Key'"
            }
            else {
                # Resolve volume if provided
                if ($Volume) {
                    $volumeKey = $null
                    if ($Volume -is [string]) {
                        $volumeData = Get-VergeNASVolume -Name $Volume -Server $Server
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
                'id'
                'name'
                'description'
                'enabled'
                'created'
                'modified'
                'share_path'
                'comment'
                'browseable'
                'read_only'
                'guest_ok'
                'guest_only'
                'force_user'
                'force_group'
                'valid_users'
                'valid_groups'
                'admin_users'
                'admin_groups'
                'host_allow'
                'host_deny'
                'vfs_shadow_copy2'
                'volume'
                'volume#$display as volume_display'
                'volume#name as volume_name'
                'status#status as status'
                'status#state as state'
            ) -join ','

            Write-Verbose "Querying CIFS shares"
            $response = Invoke-VergeAPI -Method GET -Endpoint 'volume_cifs_shares' -Query $queryParams -Connection $Server

            $shares = if ($response -is [array]) { $response } else { @($response) }

            foreach ($share in $shares) {
                if (-not $share -or -not $share.name) {
                    continue
                }

                # Convert timestamps
                $created = $null
                if ($share.created) {
                    $created = [DateTimeOffset]::FromUnixTimeSeconds($share.created).LocalDateTime
                }
                $modified = $null
                if ($share.modified) {
                    $modified = [DateTimeOffset]::FromUnixTimeSeconds($share.modified).LocalDateTime
                }

                # Parse user/group lists
                $validUsers = if ($share.valid_users) { $share.valid_users -split '\n' | Where-Object { $_ } } else { @() }
                $validGroups = if ($share.valid_groups) { $share.valid_groups -split '\n' | Where-Object { $_ } } else { @() }
                $adminUsers = if ($share.admin_users) { $share.admin_users -split '\n' | Where-Object { $_ } } else { @() }
                $adminGroups = if ($share.admin_groups) { $share.admin_groups -split '\n' | Where-Object { $_ } } else { @() }
                $allowedHosts = if ($share.host_allow) { $share.host_allow -split '\n' | Where-Object { $_ } } else { @() }
                $deniedHosts = if ($share.host_deny) { $share.host_deny -split '\n' | Where-Object { $_ } } else { @() }

                [PSCustomObject]@{
                    PSTypeName = 'Verge.NASCIFSShare'
                    Key               = $share.'$key' ?? $share.id
                    Id                = $share.id
                    Name              = $share.name
                    Description       = $share.description
                    VolumeName        = $share.volume_name ?? $share.volume_display
                    VolumeKey         = $share.volume
                    SharePath         = $share.share_path
                    Comment           = $share.comment
                    Enabled           = [bool]$share.enabled
                    Browseable        = [bool]$share.browseable
                    ReadOnly          = [bool]$share.read_only
                    GuestOK           = [bool]$share.guest_ok
                    GuestOnly         = [bool]$share.guest_only
                    ForceUser         = $share.force_user
                    ForceGroup        = $share.force_group
                    ValidUsers        = $validUsers
                    ValidGroups       = $validGroups
                    AdminUsers        = $adminUsers
                    AdminGroups       = $adminGroups
                    AllowedHosts      = $allowedHosts
                    DeniedHosts       = $deniedHosts
                    ShadowCopyEnabled = [bool]$share.vfs_shadow_copy2
                    Status            = $share.status
                    State             = $share.state
                    Created           = $created
                    Modified          = $modified
                }
            }
        }
        catch {
            Write-Error -Message "Failed to get CIFS shares: $($_.Exception.Message)" -ErrorId 'GetCIFSSharesFailed'
        }
    }
}
