function Get-VergeTenant {
    <#
    .SYNOPSIS
        Retrieves tenants from VergeOS.

    .DESCRIPTION
        Get-VergeTenant retrieves one or more tenants from a VergeOS system.
        You can filter tenants by name, status, or other criteria. Supports
        wildcards for name filtering.

    .PARAMETER Name
        The name of the tenant to retrieve. Supports wildcards (* and ?).
        If not specified, all tenants are returned.

    .PARAMETER Key
        The unique key (ID) of the tenant to retrieve.

    .PARAMETER Status
        Filter tenants by status: Online, Offline, Starting, Stopping, Error, etc.

    .PARAMETER IncludeSnapshots
        Include tenant snapshots in the results. By default, snapshots are excluded.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeTenant

        Retrieves all tenants from the connected VergeOS system.

    .EXAMPLE
        Get-VergeTenant -Name "Customer01"

        Retrieves a specific tenant by name.

    .EXAMPLE
        Get-VergeTenant -Name "Prod*"

        Retrieves all tenants whose names start with "Prod".

    .EXAMPLE
        Get-VergeTenant -Status Online

        Retrieves all online tenants.

    .EXAMPLE
        Get-VergeTenant -Name "Customer01" | Get-VergeTenantStorage

        Gets storage allocations for a specific tenant.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.Tenant'

    .NOTES
        Use Start-VergeTenant, Stop-VergeTenant, etc. to manage tenant power state.
        Use Get-VergeTenantStorage for tenant storage tier allocations.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Filter')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ParameterSetName = 'Filter')]
        [SupportsWildcards()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey', ValueFromPipelineByPropertyName)]
        [Alias('Id', '$key')]
        [int]$Key,

        [Parameter(ParameterSetName = 'Filter')]
        [ValidateSet('Online', 'Offline', 'Starting', 'Stopping', 'Migrating',
                     'Error', 'Reduced', 'Provisioning', 'Restarting')]
        [string]$Status,

        [Parameter()]
        [switch]$IncludeSnapshots,

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
        # Build query parameters
        $queryParams = @{}

        # Build filter string
        $filters = [System.Collections.Generic.List[string]]::new()

        # Exclude snapshots by default
        if (-not $IncludeSnapshots) {
            $filters.Add('is_snapshot eq false')
        }

        # Filter by key
        if ($PSCmdlet.ParameterSetName -eq 'ByKey') {
            $filters.Add("`$key eq $Key")
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
        }

        # Apply filters
        if ($filters.Count -gt 0) {
            $queryParams['filter'] = $filters -join ' and '
        }

        # Use list view with status and node/storage info
        $queryParams['fields'] = @(
            '$key'
            'name'
            'description'
            'url'
            'uuid'
            'created'
            'creator'
            'is_snapshot'
            'isolate'
            'note'
            'status#status as status'
            'status#running as running'
            'status#starting as starting'
            'status#stopping as stopping'
            'status#migrating as migrating'
            'status#started as started_ts'
            'status#stopped as stopped_ts'
            'status#state as state'
            'vnet'
            'vnet#name as network_name'
            'ui_address'
            'ui_address#ip as ui_address_ip'
        ) -join ','

        try {
            Write-Verbose "Querying tenants from $($Server.Server)"
            $response = Invoke-VergeAPI -Method GET -Endpoint 'tenants' -Query $queryParams -Connection $Server

            # Handle both single object and array responses
            $tenants = if ($response -is [array]) { $response } else { @($response) }

            # Filter by Status if specified (post-query)
            if ($Status) {
                $statusMap = @{
                    'Online'       = 'online'
                    'Offline'      = 'offline'
                    'Starting'     = 'starting'
                    'Stopping'     = 'stopping'
                    'Migrating'    = 'migrating'
                    'Error'        = 'error'
                    'Reduced'      = 'reduced'
                    'Provisioning' = 'provisioning'
                    'Restarting'   = 'restarting'
                }
                $targetStatus = $statusMap[$Status]
                $tenants = $tenants | Where-Object { $_.status -eq $targetStatus }
            }

            foreach ($tenant in $tenants) {
                # Skip null entries
                if (-not $tenant -or -not $tenant.name) {
                    continue
                }

                # Map status to user-friendly display
                $statusDisplay = switch ($tenant.status) {
                    'online'         { 'Online' }
                    'offline'        { 'Offline' }
                    'starting'       { 'Starting' }
                    'stopping'       { 'Stopping' }
                    'migrating'      { 'Migrating' }
                    'errormigrating' { 'Error (Migrating)' }
                    'reduced'        { 'Reduced' }
                    'error'          { 'Error' }
                    'nodesoffline'   { 'Error (Nodes Offline)' }
                    'provisioning'   { 'Provisioning' }
                    'restarting'     { 'Restarting' }
                    default          { $tenant.status }
                }

                # Map state to display
                $stateDisplay = switch ($tenant.state) {
                    'online'  { 'Online' }
                    'offline' { 'Offline' }
                    'warning' { 'Warning' }
                    'error'   { 'Error' }
                    default   { $tenant.state }
                }

                # Create output object
                $output = [PSCustomObject]@{
                    PSTypeName    = 'Verge.Tenant'
                    Key           = [int]$tenant.'$key'
                    Name          = $tenant.name
                    Description   = $tenant.description
                    Status        = $statusDisplay
                    State         = $stateDisplay
                    IsRunning     = [bool]$tenant.running
                    IsStarting    = [bool]$tenant.starting
                    IsStopping    = [bool]$tenant.stopping
                    IsMigrating   = [bool]$tenant.migrating
                    Isolated      = [bool]$tenant.isolate
                    IsSnapshot    = [bool]$tenant.is_snapshot
                    URL           = $tenant.url
                    UIAddress     = $tenant.ui_address_ip
                    UUID          = $tenant.uuid
                    NetworkKey    = $tenant.vnet
                    NetworkName   = $tenant.network_name
                    Note          = $tenant.note
                    Creator       = $tenant.creator
                    Created       = if ($tenant.created) { [DateTimeOffset]::FromUnixTimeSeconds($tenant.created).LocalDateTime } else { $null }
                    Started       = if ($tenant.started_ts) { [DateTimeOffset]::FromUnixTimeSeconds($tenant.started_ts).LocalDateTime } else { $null }
                    Stopped       = if ($tenant.stopped_ts) { [DateTimeOffset]::FromUnixTimeSeconds($tenant.stopped_ts).LocalDateTime } else { $null }
                }

                # Add hidden properties for pipeline support
                $output | Add-Member -MemberType NoteProperty -Name '_Connection' -Value $Server -Force

                Write-Output $output
            }
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}
