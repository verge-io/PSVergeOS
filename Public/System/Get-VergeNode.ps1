function Get-VergeNode {
    <#
    .SYNOPSIS
        Retrieves nodes from VergeOS.

    .DESCRIPTION
        Get-VergeNode retrieves one or more nodes from a VergeOS system.
        Returns node details including RAM, cores, drives, NICs, GPU information,
        and resource utilization statistics.

    .PARAMETER Name
        The name (hostname) of the node to retrieve. Supports wildcards (* and ?).
        If not specified, all nodes are returned.

    .PARAMETER Key
        The unique key (ID) of the node to retrieve.

    .PARAMETER Cluster
        Filter nodes by cluster name.

    .PARAMETER MaintenanceMode
        Filter nodes by maintenance mode status.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeNode

        Retrieves all nodes from the connected VergeOS system.

    .EXAMPLE
        Get-VergeNode -Name "node1"

        Retrieves a specific node by hostname.

    .EXAMPLE
        Get-VergeNode -Cluster "Cluster1"

        Retrieves all nodes in a specific cluster.

    .EXAMPLE
        Get-VergeNode -MaintenanceMode $true

        Retrieves all nodes currently in maintenance mode.

    .EXAMPLE
        Get-VergeNode | Select-Object Name, Cluster, RAM, Cores, Status

        Lists all nodes with key resource information.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.Node'

    .NOTES
        Use Enable-VergeNodeMaintenance and Disable-VergeNodeMaintenance to manage maintenance mode.
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
        [string]$Cluster,

        [Parameter(ParameterSetName = 'Filter')]
        [bool]$MaintenanceMode,

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
            Write-Verbose "Querying nodes from $($Server.Server)"

            # Build query parameters
            $queryParams = @{}
            $filters = [System.Collections.Generic.List[string]]::new()

            # Filter by key
            if ($PSCmdlet.ParameterSetName -eq 'ByKey') {
                $filters.Add("`$key eq $Key")
            }
            else {
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

                # Filter by cluster
                if ($Cluster) {
                    $filters.Add("cluster#name eq '$Cluster'")
                }

                # Filter by maintenance mode
                if ($PSBoundParameters.ContainsKey('MaintenanceMode')) {
                    $filters.Add("maintenance eq $($MaintenanceMode.ToString().ToLower())")
                }
            }

            # Apply filters
            if ($filters.Count -gt 0) {
                $queryParams['filter'] = $filters -join ' and '
            }

            # Request comprehensive data
            $queryParams['fields'] = @(
                '$key'
                'name'
                'description'
                'model'
                'cpu'
                'cpu_speed'
                'ram'
                'vm_ram'
                'overcommit'
                'failover_ram'
                'cores'
                'physical'
                'maintenance'
                'iommu'
                'need_restart'
                'restart_reason'
                'asset_tag'
                'ipmi_address'
                'ipmi_status'
                'vsan_nodeid'
                'vsan_connected'
                'yb_version'
                'os_version'
                'kernel_version'
                'appserver_version'
                'vsan_version'
                'qemu_version'
                'cluster'
                'cluster#name as cluster_name'
                'machine'
                'machine#status#status as status'
                'machine#status#running as running'
                'machine#status#started as started'
                'machine#stats#total_cpu as cpu_usage'
                'machine#stats#ram_used as ram_used'
                'machine#stats#vram_used as vram_used'
                'machine#stats#core_temp as core_temp'
            ) -join ','

            $response = Invoke-VergeAPI -Method GET -Endpoint 'nodes' -Query $queryParams -Connection $Server

            # Handle both single object and array responses
            $nodes = if ($response -is [array]) { $response } else { @($response) }

            foreach ($node in $nodes) {
                # Skip null entries
                if (-not $node -or -not $node.name) {
                    continue
                }

                # Map status to user-friendly state
                $statusDisplay = switch ($node.status) {
                    'running'      { 'Running' }
                    'stopped'      { 'Stopped' }
                    'online'       { 'Online' }
                    'offline'      { 'Offline' }
                    'maintenance'  { 'Maintenance' }
                    'error'        { 'Error' }
                    'warning'      { 'Warning' }
                    default        { $node.status }
                }

                # Create output object
                $output = [PSCustomObject]@{
                    PSTypeName       = 'Verge.Node'
                    Key              = [int]$node.'$key'
                    Name             = $node.name
                    Description      = $node.description
                    Status           = $statusDisplay
                    IsRunning        = [bool]$node.running
                    Model            = $node.model
                    CPU              = $node.cpu
                    CPUSpeed         = $node.cpu_speed
                    RAM              = [int]$node.ram
                    VMRam            = [int]$node.vm_ram
                    OvercommitRAM    = [int]$node.overcommit
                    FailoverRAM      = [int]$node.failover_ram
                    Cores            = [int]$node.cores
                    IsPhysical       = [bool]$node.physical
                    MaintenanceMode  = [bool]$node.maintenance
                    IOMMU            = [bool]$node.iommu
                    NeedsRestart     = [bool]$node.need_restart
                    RestartReason    = $node.restart_reason
                    CPUUsage         = $node.cpu_usage
                    RAMUsed          = [int]$node.ram_used
                    VRAMUsed         = [int]$node.vram_used
                    CoreTemp         = $node.core_temp
                    AssetTag         = $node.asset_tag
                    IPMIAddress      = $node.ipmi_address
                    IPMIStatus       = $node.ipmi_status
                    vSANNodeId       = [int]$node.vsan_nodeid
                    vSANConnected    = [bool]$node.vsan_connected
                    Cluster          = $node.cluster_name
                    ClusterKey       = $node.cluster
                    MachineKey       = $node.machine
                    VergeOSVersion   = $node.yb_version
                    OSVersion        = $node.os_version
                    KernelVersion    = $node.kernel_version
                    AppServerVersion = $node.appserver_version
                    vSANVersion      = $node.vsan_version
                    QEMUVersion      = $node.qemu_version
                    Started          = if ($node.started) { [DateTimeOffset]::FromUnixTimeSeconds($node.started).LocalDateTime } else { $null }
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
