function Get-VergeCluster {
    <#
    .SYNOPSIS
        Retrieves clusters from VergeOS.

    .DESCRIPTION
        Get-VergeCluster retrieves one or more clusters from a VergeOS system.
        Returns cluster details including CPU type, RAM allocation, storage tiers,
        and resource utilization statistics.

    .PARAMETER Name
        The name of the cluster to retrieve. Supports wildcards (* and ?).
        If not specified, all clusters are returned.

    .PARAMETER Key
        The unique key (ID) of the cluster to retrieve.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeCluster

        Retrieves all clusters from the connected VergeOS system.

    .EXAMPLE
        Get-VergeCluster -Name "Cluster1"

        Retrieves a specific cluster by name.

    .EXAMPLE
        Get-VergeCluster | Select-Object Name, OnlineNodes, OnlineCores, OnlineRAM

        Lists cluster resources across all clusters.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.Cluster'

    .NOTES
        Use Get-VergeNode to get details about individual nodes in a cluster.
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
            Write-Verbose "Querying clusters from $($Server.Server)"

            # Build query parameters
            $queryParams = @{}
            $filters = [System.Collections.Generic.List[string]]::new()

            # Filter by key
            if ($PSCmdlet.ParameterSetName -eq 'ByKey') {
                $filters.Add("`$key eq $Key")
            }
            elseif ($Name) {
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

            # Apply filters
            if ($filters.Count -gt 0) {
                $queryParams['filter'] = $filters -join ' and '
            }

            # Request rich data with status
            $queryParams['fields'] = @(
                '$key'
                'name'
                'description'
                'enabled'
                'storage'
                'compute'
                'default_cpu'
                'recommended_cpu_type'
                'kvm_nested'
                'ram_per_unit'
                'cores_per_unit'
                'max_ram_per_vm'
                'max_cores_per_vm'
                'target_ram_pct'
                'ram_overcommit_pct'
                'created'
                'status'
                'status#status as status_state'
                'status#total_nodes as total_nodes'
                'status#online_nodes as online_nodes'
                'status#total_ram as total_ram'
                'status#online_ram as online_ram'
                'status#used_ram as used_ram'
                'status#total_cores as total_cores'
                'status#online_cores as online_cores'
                'status#used_cores as used_cores'
                'status#running_machines as running_machines'
            ) -join ','

            $response = Invoke-VergeAPI -Method GET -Endpoint 'clusters' -Query $queryParams -Connection $Server

            # Handle both single object and array responses
            $clusters = if ($response -is [array]) { $response } else { @($response) }

            foreach ($cluster in $clusters) {
                # Skip null entries
                if (-not $cluster -or -not $cluster.name) {
                    continue
                }

                # Map status to user-friendly state
                $statusDisplay = switch ($cluster.status_state) {
                    'online'  { 'Online' }
                    'warning' { 'Warning' }
                    'error'   { 'Error' }
                    'offline' { 'Offline' }
                    default   { $cluster.status_state }
                }

                # Create output object
                $output = [PSCustomObject]@{
                    PSTypeName          = 'Verge.Cluster'
                    Key                 = [int]$cluster.'$key'
                    Name                = $cluster.name
                    Description         = $cluster.description
                    Status              = $statusDisplay
                    Enabled             = [bool]$cluster.enabled
                    IsStorage           = [bool]$cluster.storage
                    IsCompute           = [bool]$cluster.compute
                    DefaultCPUType      = $cluster.default_cpu
                    RecommendedCPUType  = $cluster.recommended_cpu_type
                    NestedVirtualization = [bool]$cluster.kvm_nested
                    TotalNodes          = [int]$cluster.total_nodes
                    OnlineNodes         = [int]$cluster.online_nodes
                    TotalRAM            = [int]$cluster.total_ram
                    OnlineRAM           = [int]$cluster.online_ram
                    UsedRAM             = [int]$cluster.used_ram
                    TotalCores          = [int]$cluster.total_cores
                    OnlineCores         = [int]$cluster.online_cores
                    UsedCores           = [int]$cluster.used_cores
                    RunningMachines     = [int]$cluster.running_machines
                    RAMPerUnit          = [int]$cluster.ram_per_unit
                    CoresPerUnit        = [int]$cluster.cores_per_unit
                    MaxRAMPerVM         = [int]$cluster.max_ram_per_vm
                    MaxCoresPerVM       = [int]$cluster.max_cores_per_vm
                    TargetRAMPercent    = $cluster.target_ram_pct
                    RAMOvercommitPercent = $cluster.ram_overcommit_pct
                    Created             = if ($cluster.created) { [DateTimeOffset]::FromUnixTimeSeconds($cluster.created).LocalDateTime } else { $null }
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
