function Get-VergeNASVolume {
    <#
    .SYNOPSIS
        Retrieves NAS volumes from VergeOS.

    .DESCRIPTION
        Get-VergeNASVolume retrieves one or more NAS volumes from a VergeOS system.
        Volumes are virtual filesystems that can be shared via CIFS/SMB or NFS.
        You can filter volumes by name, filesystem type, or enabled state.

    .PARAMETER Name
        The name of the volume to retrieve. Supports wildcards (* and ?).
        If not specified, all volumes are returned.

    .PARAMETER Key
        The unique key (ID) of the volume to retrieve.

    .PARAMETER Enabled
        Filter volumes by enabled state. If specified, only volumes matching
        the enabled state are returned.

    .PARAMETER FileSystemType
        Filter volumes by filesystem type: ext4, cifs, nfs, ybfs, or verge_vm_export.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeNASVolume

        Lists all NAS volumes.

    .EXAMPLE
        Get-VergeNASVolume -Name "FileShare"

        Gets a specific volume by name.

    .EXAMPLE
        Get-VergeNASVolume -Name "NAS-*"

        Gets all volumes whose names start with "NAS-".

    .EXAMPLE
        Get-VergeNASVolume -Enabled $true

        Gets all enabled volumes.

    .EXAMPLE
        Get-VergeNASVolume | Select-Object Name, MaxSizeGB, Tier, Enabled

        Lists volumes with specific properties.

    .OUTPUTS
        Verge.Volume objects containing:
        - Key: The volume unique identifier
        - Name: Volume name
        - Description: Volume description
        - Enabled: Whether the volume is enabled
        - MaxSizeGB: Maximum size in GB
        - PreferredTier: The preferred storage tier
        - FileSystemType: The filesystem type (ext4, cifs, nfs, etc.)
        - ReadOnly: Whether the volume is read-only
        - SnapshotProfile: Associated snapshot profile
        - NASService: The NAS service managing this volume
        - Created: Creation timestamp
        - Modified: Last modified timestamp

    .NOTES
        Volumes are associated with NAS services in VergeOS.
        Use New-VergeVolume to create volumes, and Get-VergeCIFSShare/Get-VergeNFSShare
        to view shares on a volume.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Filter')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ParameterSetName = 'Filter')]
        [SupportsWildcards()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey', ValueFromPipelineByPropertyName)]
        [Alias('Id', 'VolumeKey')]
        [string]$Key,

        [Parameter(ParameterSetName = 'Filter')]
        [bool]$Enabled,

        [Parameter(ParameterSetName = 'Filter')]
        [ValidateSet('ext4', 'cifs', 'nfs', 'ybfs', 'verge_vm_export', 'fc_nimble')]
        [string]$FileSystemType,

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
            # Build query parameters
            $queryParams = @{}

            # Build filter string
            $filters = [System.Collections.Generic.List[string]]::new()

            # Filter by key
            if ($PSCmdlet.ParameterSetName -eq 'ByKey') {
                $queryParams['filter'] = "id eq '$Key'"
            }
            else {
                # Filter by name (with wildcard support)
                if ($Name) {
                    if ($Name -match '[\*\?]') {
                        # Wildcard - use 'ct' (contains) for partial match
                        $searchTerm = $Name -replace '[\*\?]', ''
                        if ($searchTerm) {
                            $filters.Add("name ct '$searchTerm'")
                        }
                    }
                    else {
                        # Exact match
                        $filters.Add("name eq '$Name'")
                    }
                }

                # Filter by enabled state
                if ($PSBoundParameters.ContainsKey('Enabled')) {
                    $enabledValue = if ($Enabled) { 1 } else { 0 }
                    $filters.Add("enabled eq $enabledValue")
                }

                # Filter by filesystem type
                if ($FileSystemType) {
                    $filters.Add("fs_type eq '$FileSystemType'")
                }

                # Apply filters
                if ($filters.Count -gt 0) {
                    $queryParams['filter'] = $filters -join ' and '
                }
            }

            # Select fields using the list view
            $queryParams['fields'] = @(
                '$key'
                'id'
                'name'
                'description'
                'enabled'
                'created'
                'modified'
                'maxsize'
                'preferred_tier'
                'fs_type'
                'read_only'
                'discard'
                'owner_user'
                'owner_group'
                'encrypt'
                'automount_snapshots'
                'is_snapshot'
                'note'
                'creator'
                'service'
                'service#$display as service_display'
                'service#vm#$display as nas_vm_display'
                'service#vm#status#status as nas_status'
                'snapshot_profile'
                'snapshot_profile#$display as snapshot_profile_display'
                'status#status as mount_status'
                'status#mounted as mounted'
                'drive'
                'drive#media_source#used_bytes as used_bytes'
                'drive#media_source#filesize as allocated_bytes'
            ) -join ','

            Write-Verbose "Querying volumes from $($Server.Server)"
            $response = Invoke-VergeAPI -Method GET -Endpoint 'volumes' -Query $queryParams -Connection $Server

            # Handle both single object and array responses
            $volumes = if ($response -is [array]) { $response } else { @($response) }

            foreach ($volume in $volumes) {
                # Skip null entries or snapshots (unless specifically requested)
                if (-not $volume -or -not $volume.name) {
                    continue
                }

                # Convert bytes to GB
                $maxSizeGB = if ($volume.maxsize) { [math]::Round($volume.maxsize / 1073741824, 2) } else { 0 }
                $usedGB = if ($volume.used_bytes) { [math]::Round($volume.used_bytes / 1073741824, 2) } else { 0 }
                $allocatedGB = if ($volume.allocated_bytes) { [math]::Round($volume.allocated_bytes / 1073741824, 2) } else { 0 }

                # Convert timestamps
                $created = $null
                if ($volume.created) {
                    $created = [DateTimeOffset]::FromUnixTimeSeconds($volume.created).LocalDateTime
                }
                $modified = $null
                if ($volume.modified) {
                    $modified = [DateTimeOffset]::FromUnixTimeSeconds($volume.modified).LocalDateTime
                }

                # Map filesystem type to display name
                $fsTypeDisplay = switch ($volume.fs_type) {
                    'ext4' { 'Local Volume (EXT4)' }
                    'cifs' { 'Remote CIFS' }
                    'nfs' { 'Remote NFS' }
                    'ybfs' { 'YBFSv2' }
                    'verge_vm_export' { 'Verge.io VM Export' }
                    'fc_nimble' { 'Fiber Channel (Nimble)' }
                    default { $volume.fs_type }
                }

                # Map mount status
                $statusDisplay = switch ($volume.mount_status) {
                    'mounted' { 'Mounted' }
                    'unmounted' { 'Unmounted' }
                    'error' { 'Error' }
                    default { $volume.mount_status }
                }

                [PSCustomObject]@{
                    PSTypeName = 'Verge.NASVolume'
                    Key                  = $volume.'$key'
                    Id                   = $volume.id
                    Name                 = $volume.name
                    Description          = $volume.description
                    Enabled              = [bool]$volume.enabled
                    IsSnapshot           = [bool]$volume.is_snapshot
                    MaxSizeGB            = $maxSizeGB
                    UsedGB               = $usedGB
                    AllocatedGB          = $allocatedGB
                    MaxSizeBytes         = $volume.maxsize
                    UsedBytes            = $volume.used_bytes
                    AllocatedBytes       = $volume.allocated_bytes
                    PreferredTier        = $volume.preferred_tier
                    FileSystemType       = $volume.fs_type
                    FileSystemTypeDisplay = $fsTypeDisplay
                    ReadOnly             = [bool]$volume.read_only
                    Discard              = [bool]$volume.discard
                    Encrypted            = [bool]$volume.encrypt
                    AutomountSnapshots   = [bool]$volume.automount_snapshots
                    OwnerUser            = $volume.owner_user
                    OwnerGroup           = $volume.owner_group
                    MountStatus          = $statusDisplay
                    IsMounted            = [bool]$volume.mounted
                    SnapshotProfile      = $volume.snapshot_profile_display
                    SnapshotProfileKey   = $volume.snapshot_profile
                    NASService           = $volume.service_display
                    NASServiceKey        = $volume.service
                    NASVMName            = $volume.nas_vm_display
                    NASStatus            = $volume.nas_status
                    DriveKey             = $volume.drive
                    Note                 = $volume.note
                    Creator              = $volume.creator
                    Created              = $created
                    Modified             = $modified
                }
            }
        }
        catch {
            Write-Error -Message "Failed to get volumes: $($_.Exception.Message)" -ErrorId 'GetVolumesFailed'
        }
    }
}
