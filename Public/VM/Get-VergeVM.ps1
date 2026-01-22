function Get-VergeVM {
    <#
    .SYNOPSIS
        Retrieves virtual machines from VergeOS.

    .DESCRIPTION
        Get-VergeVM retrieves one or more virtual machines from a VergeOS system.
        You can filter VMs by name, power state, or other criteria. Supports
        wildcards for name filtering.

    .PARAMETER Name
        The name of the VM to retrieve. Supports wildcards (* and ?).
        If not specified, all VMs are returned.

    .PARAMETER Key
        The unique key (ID) of the VM to retrieve.

    .PARAMETER PowerState
        Filter VMs by power state: Running, Stopped, or any valid status.

    .PARAMETER Cluster
        Filter VMs by cluster name.

    .PARAMETER IncludeSnapshots
        Include VM snapshots in the results. By default, snapshots are excluded.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeVM

        Retrieves all VMs from the connected VergeOS system.

    .EXAMPLE
        Get-VergeVM -Name "WebServer01"

        Retrieves a specific VM by name.

    .EXAMPLE
        Get-VergeVM -Name "Web*"

        Retrieves all VMs whose names start with "Web".

    .EXAMPLE
        Get-VergeVM -PowerState Running

        Retrieves all running VMs.

    .EXAMPLE
        Get-VergeVM -Name "Prod-*" -PowerState Stopped

        Retrieves stopped VMs with names starting with "Prod-".

    .EXAMPLE
        Get-VergeVM | Where-Object { $_.RAM -gt 8192 }

        Retrieves all VMs with more than 8GB RAM.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.VM'

    .NOTES
        Use Start-VergeVM, Stop-VergeVM, etc. to manage VM power state.
        Use Get-VergeDrive and Get-VergeNIC for VM hardware details.
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
        [ValidateSet('Running', 'Stopped', 'Hibernated', 'Stopping', 'Starting',
                     'Migrating', 'Unresponsive', 'Error', 'Maintenance')]
        [string]$PowerState,

        [Parameter(ParameterSetName = 'Filter')]
        [string]$Cluster,

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
                    # Wildcard - use 'ct' (contains) since API doesn't support LIKE
                    # Strip wildcards and use contains for partial match
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

            # Filter by cluster
            if ($Cluster) {
                $filters.Add("machine#cluster#name eq '$Cluster'")
            }
        }

        # Apply filters
        if ($filters.Count -gt 0) {
            $queryParams['filter'] = $filters -join ' and '
        }

        # Use dashboard view for rich data
        $queryParams['fields'] = @(
            '$key'
            'name'
            'description'
            'enabled'
            'cpu_cores'
            'ram'
            'os_family'
            'guest_agent'
            'uefi'
            'secure_boot'
            'created'
            'modified'
            'is_snapshot'
            'machine'
            'machine#status#status as status'
            'machine#status#running as running'
            'machine#status#node as node_key'
            'machine#status#node#name as node_name'
            'machine#cluster as cluster_key'
            'machine#cluster#name as cluster_name'
            'machine#ha_group as ha_group'
            'machine#snapshot_profile as snapshot_profile'
            'machine#snapshot_profile#name as snapshot_profile_name'
        ) -join ','

        try {
            Write-Verbose "Querying VMs from $($Server.Server)"
            $response = Invoke-VergeAPI -Method GET -Endpoint 'vms' -Query $queryParams -Connection $Server

            # Handle both single object and array responses
            $vms = if ($response -is [array]) { $response } else { @($response) }

            # Filter by PowerState if specified (needs to be done post-query)
            if ($PowerState) {
                $statusMap = @{
                    'Running'      = 'running'
                    'Stopped'      = 'stopped'
                    'Hibernated'   = 'hibernated'
                    'Stopping'     = 'stopping'
                    'Starting'     = 'starting'
                    'Migrating'    = 'migrating'
                    'Unresponsive' = 'unresponsive'
                    'Error'        = 'error'
                    'Maintenance'  = 'maintenance'
                }
                $targetStatus = $statusMap[$PowerState]
                $vms = $vms | Where-Object { $_.status -eq $targetStatus }
            }

            foreach ($vm in $vms) {
                # Skip null entries
                if (-not $vm -or -not $vm.name) {
                    continue
                }

                # Map status to user-friendly PowerState
                $powerStateDisplay = switch ($vm.status) {
                    'running'      { 'Running' }
                    'stopped'      { 'Stopped' }
                    'hibernated'   { 'Hibernated' }
                    'stopping'     { 'Stopping' }
                    'starting'     { 'Starting' }
                    'initializing' { 'Starting' }
                    'migrating'    { 'Migrating' }
                    'initmigrate'  { 'Migrating' }
                    'startmigrate' { 'Migrating' }
                    'migratecomplete' { 'Migrating' }
                    'unresponsive' { 'Unresponsive' }
                    'error'        { 'Error' }
                    'maintenance'  { 'Maintenance' }
                    'hibernating'  { 'Hibernating' }
                    default        { $vm.status }
                }

                # Create output object
                $output = [PSCustomObject]@{
                    PSTypeName       = 'Verge.VM'
                    Key              = [int]$vm.'$key'
                    Name             = $vm.name
                    Description      = $vm.description
                    PowerState       = $powerStateDisplay
                    Status           = $vm.status
                    IsRunning        = [bool]$vm.running
                    CPUCores         = [int]$vm.cpu_cores
                    RAM              = [int]$vm.ram
                    OSFamily         = $vm.os_family
                    GuestAgent       = [bool]$vm.guest_agent
                    UEFI             = [bool]$vm.uefi
                    SecureBoot       = [bool]$vm.secure_boot
                    Enabled          = [bool]$vm.enabled
                    IsSnapshot       = [bool]$vm.is_snapshot
                    Cluster          = $vm.cluster_name
                    ClusterKey       = $vm.cluster_key
                    Node             = $vm.node_name
                    NodeKey          = $vm.node_key
                    HAGroup          = $vm.ha_group
                    SnapshotProfile  = $vm.snapshot_profile_name
                    MachineKey       = $vm.machine
                    Created          = if ($vm.created) { [DateTimeOffset]::FromUnixTimeSeconds($vm.created).LocalDateTime } else { $null }
                    Modified         = if ($vm.modified) { [DateTimeOffset]::FromUnixTimeSeconds($vm.modified).LocalDateTime } else { $null }
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
