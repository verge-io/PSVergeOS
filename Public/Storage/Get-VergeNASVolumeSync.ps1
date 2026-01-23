function Get-VergeNASVolumeSync {
    <#
    .SYNOPSIS
        Retrieves volume sync jobs from VergeOS.

    .DESCRIPTION
        Get-VergeNASVolumeSync retrieves volume synchronization jobs from a VergeOS system.
        Volume syncs copy data between NAS volumes on a schedule or on-demand.

    .PARAMETER NASService
        The NAS service name or object to get sync jobs for.

    .PARAMETER Name
        Filter sync jobs by name. Supports wildcards.

    .PARAMETER Key
        Get a specific sync job by its key.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeNASVolumeSync

        Lists all volume sync jobs.

    .EXAMPLE
        Get-VergeNASVolumeSync -NASService "MyNAS"

        Lists sync jobs for a specific NAS service.

    .EXAMPLE
        Get-VergeNASVolumeSync -Name "Daily*"

        Gets sync jobs with names starting with "Daily".

    .OUTPUTS
        Verge.NASVolumeSync objects containing:
        - Key: The sync job unique identifier
        - Name: Sync job name
        - SourceVolume: Source volume name
        - DestinationVolume: Destination volume name
        - Status: Current sync status
        - Enabled: Whether the sync is enabled

    .NOTES
        Use Start-VergeNASVolumeSync to manually trigger a sync.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByNAS')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ParameterSetName = 'ByNAS', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('NASServiceName', 'Service')]
        [object]$NASService,

        [Parameter(ParameterSetName = 'ByNAS')]
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
                # Resolve NAS service if provided
                if ($NASService) {
                    $serviceKey = $null
                    if ($NASService -is [string]) {
                        $serviceData = Get-VergeNASService -Name $NASService -Server $Server
                        if (-not $serviceData) {
                            throw "NAS service '$NASService' not found"
                        }
                        $serviceKey = $serviceData.Key
                    }
                    elseif ($NASService.Key) {
                        $serviceKey = $NASService.Key
                    }
                    elseif ($NASService -is [int]) {
                        $serviceKey = $NASService
                    }

                    if ($serviceKey) {
                        $filters.Add("service eq $serviceKey")
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

            # Select fields including progress data
            $queryParams['fields'] = @(
                '$key'
                'id'
                'name'
                'description'
                'enabled'
                'created'
                'modified'
                'service'
                'service#name as service_name'
                'service#vm#$display as service_vm'
                'source_volume'
                'source_volume#name as source_volume_name'
                'source_path'
                'destination_volume'
                'destination_volume#name as destination_volume_name'
                'destination_path'
                'include'
                'exclude'
                'sync_method'
                'destination_delete'
                'workers'
                'preserve_ACLs'
                'preserve_permissions'
                'preserve_owner'
                'preserve_groups'
                'preserve_mod_time'
                'preserve_xattrs'
                'copy_symlinks'
                'fsfreeze'
                'progress#status as status'
                'progress#syncing as syncing'
                'progress#files_transferred as files_transferred'
                'progress#bytes_transferred as bytes_transferred'
                'progress#transfer_rate as transfer_rate'
                'progress#sync_errors as sync_errors'
                'progress#start_time as start_time'
                'progress#stop_time as stop_time'
            ) -join ','

            Write-Verbose "Querying volume sync jobs"
            $response = Invoke-VergeAPI -Method GET -Endpoint 'volume_syncs' -Query $queryParams -Connection $Server

            $syncs = if ($response -is [array]) { $response } else { @($response) }

            foreach ($sync in $syncs) {
                if (-not $sync -or -not $sync.name) {
                    continue
                }

                # Convert timestamps
                $created = $null
                if ($sync.created) {
                    $created = [DateTimeOffset]::FromUnixTimeSeconds($sync.created).LocalDateTime
                }
                $modified = $null
                if ($sync.modified) {
                    $modified = [DateTimeOffset]::FromUnixTimeSeconds($sync.modified).LocalDateTime
                }
                $startTime = $null
                if ($sync.start_time) {
                    $startTime = [DateTimeOffset]::FromUnixTimeSeconds($sync.start_time).LocalDateTime
                }
                $stopTime = $null
                if ($sync.stop_time) {
                    $stopTime = [DateTimeOffset]::FromUnixTimeSeconds($sync.stop_time).LocalDateTime
                }

                # Map status to display
                $statusDisplay = switch ($sync.status) {
                    'complete' { 'Complete' }
                    'offline' { 'Offline' }
                    'syncing' { 'Syncing' }
                    'aborted' { 'Aborted' }
                    'error' { 'Error' }
                    'warning' { 'Warning' }
                    default { $sync.status }
                }

                # Map sync method
                $methodDisplay = switch ($sync.sync_method) {
                    'rsync' { 'rsync' }
                    'ysync' { 'Verge.io sync' }
                    default { $sync.sync_method }
                }

                # Map destination delete
                $deleteDisplay = switch ($sync.destination_delete) {
                    'never' { 'Never delete' }
                    'delete' { 'Delete files from destination' }
                    'delete-before' { 'Delete before transfer' }
                    'delete-during' { 'Delete during transfer' }
                    'delete-delay' { 'Delete after transfer (find during)' }
                    'delete-after' { 'Delete after transfer' }
                    default { $sync.destination_delete }
                }

                [PSCustomObject]@{
                    PSTypeName              = 'Verge.NASVolumeSync'
                    Key                     = $sync.'$key' ?? $sync.id
                    Id                      = $sync.id
                    Name                    = $sync.name
                    Description             = $sync.description
                    NASServiceKey           = $sync.service
                    NASServiceName          = $sync.service_name ?? $sync.service_vm
                    SourceVolumeKey         = $sync.source_volume
                    SourceVolumeName        = $sync.source_volume_name
                    SourcePath              = $sync.source_path
                    DestinationVolumeKey    = $sync.destination_volume
                    DestinationVolumeName   = $sync.destination_volume_name
                    DestinationPath         = $sync.destination_path
                    Include                 = $sync.include
                    Exclude                 = $sync.exclude
                    SyncMethod              = $sync.sync_method
                    SyncMethodDisplay       = $methodDisplay
                    DestinationDelete       = $sync.destination_delete
                    DestinationDeleteDisplay = $deleteDisplay
                    Workers                 = $sync.workers
                    PreserveACLs            = [bool]$sync.preserve_ACLs
                    PreservePermissions     = [bool]$sync.preserve_permissions
                    PreserveOwner           = [bool]$sync.preserve_owner
                    PreserveGroups          = [bool]$sync.preserve_groups
                    PreserveModTime         = [bool]$sync.preserve_mod_time
                    PreserveXattrs          = [bool]$sync.preserve_xattrs
                    CopySymlinks            = [bool]$sync.copy_symlinks
                    FreezeFilesystem        = [bool]$sync.fsfreeze
                    Enabled                 = [bool]$sync.enabled
                    Status                  = $sync.status
                    StatusDisplay           = $statusDisplay
                    Syncing                 = [bool]$sync.syncing
                    FilesTransferred        = $sync.files_transferred
                    BytesTransferred        = $sync.bytes_transferred
                    TransferRate            = $sync.transfer_rate
                    SyncErrors              = $sync.sync_errors
                    StartTime               = $startTime
                    StopTime                = $stopTime
                    Created                 = $created
                    Modified                = $modified
                    _Connection             = $Server
                }
            }
        }
        catch {
            Write-Error -Message "Failed to get volume sync jobs: $($_.Exception.Message)" -ErrorId 'GetVolumeSyncFailed'
        }
    }
}
