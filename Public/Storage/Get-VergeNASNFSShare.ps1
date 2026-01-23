function Get-VergeNASNFSShare {
    <#
    .SYNOPSIS
        Retrieves NFS shares from VergeOS.

    .DESCRIPTION
        Get-VergeNASNFSShare retrieves NFS file shares from a VergeOS system.
        You can filter by volume, share name, or retrieve all NFS shares.

    .PARAMETER Volume
        The name or object of the volume to get shares for.

    .PARAMETER Name
        Filter shares by name. Supports wildcards.

    .PARAMETER Key
        Get a specific share by its key.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeNASNFSShare

        Lists all NFS shares.

    .EXAMPLE
        Get-VergeNASNFSShare -Volume "FileShare"

        Lists NFS shares on the FileShare volume.

    .EXAMPLE
        Get-VergeNASVolume | Get-VergeNASNFSShare

        Lists all NFS shares for all volumes.

    .EXAMPLE
        Get-VergeNASNFSShare -Name "exports*"

        Gets all NFS shares with names starting with "exports".

    .OUTPUTS
        Verge.NASNFSShare objects containing:
        - Key: The share unique identifier
        - Name: Share name
        - VolumeName: Parent volume name
        - SharePath: Path within the volume being shared
        - AllowedHosts: Hosts allowed to connect
        - DataAccess: Read-only or read-write
        - Squash: User/group squashing mode
        - Enabled: Whether the share is enabled

    .NOTES
        NFS shares provide Unix/Linux-compatible file sharing.
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
                'allowed_hosts'
                'fsid'
                'anonuid'
                'anongid'
                'no_acl'
                'insecure'
                'async'
                'squash'
                'data_access'
                'allow_all'
                'volume'
                'volume#$display as volume_display'
                'volume#name as volume_name'
                'status#status as status'
                'status#state as state'
            ) -join ','

            Write-Verbose "Querying NFS shares"
            $response = Invoke-VergeAPI -Method GET -Endpoint 'volume_nfs_shares' -Query $queryParams -Connection $Server

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

                # Map squash to display
                $squashDisplay = switch ($share.squash) {
                    'root_squash'    { 'Squash Root' }
                    'all_squash'     { 'Squash All' }
                    'no_root_squash' { 'No Squashing' }
                    default          { $share.squash }
                }

                # Map data access to display
                $dataAccessDisplay = switch ($share.data_access) {
                    'ro' { 'Read Only' }
                    'rw' { 'Read and Write' }
                    default { $share.data_access }
                }

                [PSCustomObject]@{
                    PSTypeName        = 'Verge.NASNFSShare'
                    Key               = $share.'$key' ?? $share.id
                    Id                = $share.id
                    Name              = $share.name
                    Description       = $share.description
                    VolumeName        = $share.volume_name ?? $share.volume_display
                    VolumeKey         = $share.volume
                    SharePath         = $share.share_path
                    AllowedHosts      = $share.allowed_hosts
                    AllowAll          = [bool]$share.allow_all
                    DataAccess        = $share.data_access
                    DataAccessDisplay = $dataAccessDisplay
                    Squash            = $share.squash
                    SquashDisplay     = $squashDisplay
                    FilesystemID      = $share.fsid
                    AnonymousUID      = $share.anonuid
                    AnonymousGID      = $share.anongid
                    NoACL             = [bool]$share.no_acl
                    Insecure          = [bool]$share.insecure
                    Async             = [bool]$share.async
                    Enabled           = [bool]$share.enabled
                    Status            = $share.status
                    State             = $share.state
                    Created           = $created
                    Modified          = $modified
                    _Connection       = $Server
                }
            }
        }
        catch {
            Write-Error -Message "Failed to get NFS shares: $($_.Exception.Message)" -ErrorId 'GetNFSSharesFailed'
        }
    }
}
