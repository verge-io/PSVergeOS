function Get-VergeNASService {
    <#
    .SYNOPSIS
        Retrieves NAS services from VergeOS.

    .DESCRIPTION
        Get-VergeNASService retrieves one or more NAS services from a VergeOS system.
        NAS services are specialized VMs that manage NAS volumes and file shares.
        You can filter services by name or status.

    .PARAMETER Name
        The name of the NAS service to retrieve. Supports wildcards (* and ?).
        If not specified, all NAS services are returned.

    .PARAMETER Key
        The unique key (ID) of the NAS service to retrieve.

    .PARAMETER Status
        Filter NAS services by VM status: Running, Stopped, Starting, Stopping, etc.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeNASService

        Lists all NAS services.

    .EXAMPLE
        Get-VergeNASService -Name "NAS01"

        Gets a specific NAS service by name.

    .EXAMPLE
        Get-VergeNASService -Name "NAS*"

        Gets all NAS services whose names start with "NAS".

    .EXAMPLE
        Get-VergeNASService -Status Running

        Gets all running NAS services.

    .EXAMPLE
        Get-VergeNASService | Select-Object Name, Status, VolumeCount, MaxImports

        Lists NAS services with specific properties.

    .OUTPUTS
        Verge.NASService objects containing:
        - Key: The NAS service unique identifier
        - Name: NAS service name (same as VM name)
        - Status: VM power status (Running, Stopped, etc.)
        - VMKey: The underlying VM key
        - MaxImports: Maximum simultaneous import jobs
        - MaxSyncs: Maximum simultaneous sync jobs
        - DisableSwap: Whether swap is disabled
        - ReadAheadKB: Read-ahead buffer size
        - VolumeCount: Number of volumes managed
        - CIFSSettings: CIFS/SMB configuration reference
        - NFSSettings: NFS configuration reference

    .NOTES
        NAS services are deployed using New-VergeNASService and removed using Remove-VergeNASService.
        Volumes are associated with NAS services and can be viewed using Get-VergeVolume.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Filter')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ParameterSetName = 'Filter')]
        [SupportsWildcards()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey', ValueFromPipelineByPropertyName)]
        [Alias('Id', 'NASServiceKey')]
        [int]$Key,

        [Parameter(ParameterSetName = 'Filter')]
        [ValidateSet('Running', 'Stopped', 'Starting', 'Stopping', 'Paused', 'Error')]
        [string]$Status,

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
                $queryParams['filter'] = "`$key eq $Key"
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

                # Apply filters
                if ($filters.Count -gt 0) {
                    $queryParams['filter'] = $filters -join ' and '
                }
            }

            # Select fields with related VM and settings information
            $queryParams['fields'] = @(
                '$key'
                'name'
                'vm'
                'vm#name as vm_name'
                'vm#$display as vm_display'
                'vm#description as vm_description'
                'vm#machine#status#status as vm_status'
                'vm#machine#status#running as vm_running'
                'vm#machine#cores as vm_cores'
                'vm#machine#ram as vm_ram'
                'vm#created as created'
                'vm#modified as modified'
                'max_imports'
                'max_syncs'
                'disable_swap'
                'read_ahead_kb_default'
                'cifs'
                'nfs'
                'count(volumes) as volume_count'
            ) -join ','

            Write-Verbose "Querying NAS services from $($Server.Server)"
            $response = Invoke-VergeAPI -Method GET -Endpoint 'vm_services' -Query $queryParams -Connection $Server

            # Handle both single object and array responses
            $services = if ($response -is [array]) { $response } else { @($response) }

            # Filter by Status if specified (post-query)
            if ($Status) {
                $statusMap = @{
                    'Running'  = 'running'
                    'Stopped'  = 'stopped'
                    'Starting' = 'starting'
                    'Stopping' = 'stopping'
                    'Paused'   = 'paused'
                    'Error'    = 'error'
                }
                $targetStatus = $statusMap[$Status]
                $services = $services | Where-Object { $_.vm_status -eq $targetStatus }
            }

            foreach ($service in $services) {
                # Skip null entries
                if (-not $service -or (-not $service.name -and -not $service.vm_name)) {
                    continue
                }

                # Map status to user-friendly display
                $statusDisplay = switch ($service.vm_status) {
                    'running'  { 'Running' }
                    'stopped'  { 'Stopped' }
                    'starting' { 'Starting' }
                    'stopping' { 'Stopping' }
                    'paused'   { 'Paused' }
                    'error'    { 'Error' }
                    default    { $service.vm_status ?? 'Unknown' }
                }

                # Map read-ahead to display
                $readAheadDisplay = switch ($service.read_ahead_kb_default) {
                    '0'    { 'Automatic' }
                    '64'   { '64 KB' }
                    '128'  { '128 KB' }
                    '256'  { '256 KB' }
                    '512'  { '512 KB' }
                    '1024' { '1 MB' }
                    '2048' { '2 MB' }
                    '4096' { '4 MB' }
                    default { "$($service.read_ahead_kb_default) KB" }
                }

                # Convert timestamps
                $created = $null
                if ($service.created) {
                    $created = [DateTimeOffset]::FromUnixTimeSeconds($service.created).LocalDateTime
                }
                $modified = $null
                if ($service.modified) {
                    $modified = [DateTimeOffset]::FromUnixTimeSeconds($service.modified).LocalDateTime
                }

                # Convert RAM to GB for display
                $ramGB = if ($service.vm_ram) { [math]::Round($service.vm_ram / 1073741824, 2) } else { 0 }

                [PSCustomObject]@{
                    PSTypeName        = 'Verge.NASService'
                    Key               = $service.'$key'
                    Name              = $service.name ?? $service.vm_name
                    Description       = $service.vm_description
                    Status            = $statusDisplay
                    IsRunning         = [bool]$service.vm_running
                    VMKey             = $service.vm
                    VMName            = $service.vm_name ?? $service.vm_display
                    VMCores           = $service.vm_cores
                    VMRAMGB           = $ramGB
                    MaxImports        = $service.max_imports
                    MaxSyncs          = $service.max_syncs
                    DisableSwap       = [bool]$service.disable_swap
                    ReadAheadKB       = $service.read_ahead_kb_default
                    ReadAheadDisplay  = $readAheadDisplay
                    VolumeCount       = $service.volume_count ?? 0
                    CIFSSettingsKey   = $service.cifs
                    NFSSettingsKey    = $service.nfs
                    Created           = $created
                    Modified          = $modified
                }
            }
        }
        catch {
            Write-Error -Message "Failed to get NAS services: $($_.Exception.Message)" -ErrorId 'GetNASServicesFailed'
        }
    }
}
