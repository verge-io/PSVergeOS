function Get-VergevSANStatus {
    <#
    .SYNOPSIS
        Retrieves vSAN health status and statistics from VergeOS.

    .DESCRIPTION
        Get-VergevSANStatus retrieves the health status, capacity information,
        and operational statistics of the VergeOS vSAN storage system.

    .PARAMETER Cluster
        Filter by cluster name. If not specified, returns status for all clusters.

    .PARAMETER IncludeTierStatus
        Include detailed per-tier status information.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergevSANStatus

        Returns vSAN status for all clusters.

    .EXAMPLE
        Get-VergevSANStatus -IncludeTierStatus

        Returns vSAN status with detailed tier information.

    .EXAMPLE
        Get-VergevSANStatus | Where-Object { $_.State -ne 'Online' }

        Lists any clusters not in online state.

    .OUTPUTS
        Verge.vSANStatus objects containing:
        - ClusterName: The cluster name
        - Status: Overall status (Online, Offline, Error, etc.)
        - State: Simplified state (Online, Warning, Error)
        - TotalNodes: Total number of nodes
        - OnlineNodes: Number of online nodes
        - TotalRAMGB: Total cluster RAM in GB
        - OnlineRAMGB: Online RAM in GB
        - UsedRAMGB: Used RAM in GB
        - TotalCores: Total CPU cores
        - OnlineCores: Online CPU cores
        - UsedCores: Used CPU cores
        - Tiers: Array of tier status (if -IncludeTierStatus)

    .NOTES
        The vSAN is the distributed storage system in VergeOS that provides
        redundancy and high availability for VM storage.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [string]$Cluster,

        [Parameter()]
        [switch]$IncludeTierStatus,

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
            # Build query parameters for clusters with status
            $queryParams = @{}

            if ($IncludeTierStatus) {
                $queryParams['fields'] = @(
                    '$key'
                    'name'
                    'description'
                    'enabled'
                    'storage'
                    'compute'
                    'status#status as status'
                    'status#state as state'
                    'status#status_info as status_info'
                    'status#total_nodes as total_nodes'
                    'status#online_nodes as online_nodes'
                    'status#running_machines as running_machines'
                    'status#total_ram as total_ram'
                    'status#online_ram as online_ram'
                    'status#used_ram as used_ram'
                    'status#total_cores as total_cores'
                    'status#online_cores as online_cores'
                    'status#used_cores as used_cores'
                    'status#last_update as last_update'
                    'tiers[$key,tier,status#status as status,status#used as used,status#capacity as capacity,stats#rops as read_ops,stats#wops as write_ops,stats#rbps as read_bps,stats#wbps as write_bps]'
                ) -join ','
            }
            else {
                $queryParams['fields'] = @(
                    '$key'
                    'name'
                    'description'
                    'enabled'
                    'storage'
                    'compute'
                    'status#status as status'
                    'status#state as state'
                    'status#status_info as status_info'
                    'status#total_nodes as total_nodes'
                    'status#online_nodes as online_nodes'
                    'status#running_machines as running_machines'
                    'status#total_ram as total_ram'
                    'status#online_ram as online_ram'
                    'status#used_ram as used_ram'
                    'status#total_cores as total_cores'
                    'status#online_cores as online_cores'
                    'status#used_cores as used_cores'
                    'status#last_update as last_update'
                ) -join ','
            }

            # Filter by cluster name if specified
            if ($Cluster) {
                $queryParams['filter'] = "name eq '$Cluster'"
            }

            Write-Verbose "Querying cluster vSAN status"
            $response = Invoke-VergeAPI -Method GET -Endpoint 'clusters' -Query $queryParams -Connection $Server

            $clusters = if ($response -is [array]) { $response } else { @($response) }

            foreach ($clusterData in $clusters) {
                if (-not $clusterData -or -not $clusterData.name) {
                    continue
                }

                # Map status to display
                $statusDisplay = switch ($clusterData.status) {
                    'online' { 'Online' }
                    'offline' { 'Offline' }
                    'maintenance' { 'Maintenance' }
                    'reduced' { 'Reduced Capacity' }
                    'noredundant' { 'No Redundancy' }
                    'error' { 'Error' }
                    'updating' { 'Updating' }
                    'shutdown' { 'Shutting Down' }
                    'insufficient' { 'Insufficient Nodes' }
                    default { $clusterData.status }
                }

                $stateDisplay = switch ($clusterData.state) {
                    'online' { 'Online' }
                    'offline' { 'Offline' }
                    'warning' { 'Warning' }
                    'error' { 'Error' }
                    default { $clusterData.state }
                }

                # Convert RAM from MB to GB
                $totalRAMGB = if ($clusterData.total_ram) { [math]::Round($clusterData.total_ram / 1024, 2) } else { 0 }
                $onlineRAMGB = if ($clusterData.online_ram) { [math]::Round($clusterData.online_ram / 1024, 2) } else { 0 }
                $usedRAMGB = if ($clusterData.used_ram) { [math]::Round($clusterData.used_ram / 1024, 2) } else { 0 }

                # Calculate RAM usage percentage
                $ramUsedPercent = if ($onlineRAMGB -gt 0) {
                    [math]::Round(($usedRAMGB / $onlineRAMGB) * 100, 1)
                } else { 0 }

                # Calculate core usage percentage
                $coreUsedPercent = if ($clusterData.online_cores -gt 0) {
                    [math]::Round(($clusterData.used_cores / $clusterData.online_cores) * 100, 1)
                } else { 0 }

                # Convert last update timestamp
                $lastUpdate = $null
                if ($clusterData.last_update) {
                    $lastUpdate = [DateTimeOffset]::FromUnixTimeSeconds($clusterData.last_update).LocalDateTime
                }

                # Process tier data if included
                $tierData = $null
                if ($IncludeTierStatus -and $clusterData.tiers) {
                    $tierData = foreach ($tier in $clusterData.tiers) {
                        $usedGB = if ($tier.used) { [math]::Round($tier.used / 1073741824, 2) } else { 0 }
                        $capacityGB = if ($tier.capacity) { [math]::Round($tier.capacity / 1073741824, 2) } else { 0 }
                        $usedPct = if ($capacityGB -gt 0) { [math]::Round(($usedGB / $capacityGB) * 100, 1) } else { 0 }

                        [PSCustomObject]@{
                            Tier           = $tier.tier
                            Status         = $tier.status
                            UsedGB         = $usedGB
                            CapacityGB     = $capacityGB
                            UsedPercent    = $usedPct
                            ReadOps        = $tier.read_ops
                            WriteOps       = $tier.write_ops
                            ReadBytesPerSec  = $tier.read_bps
                            WriteBytesPerSec = $tier.write_bps
                        }
                    }
                }

                # Determine health status
                $healthStatus = switch ($clusterData.state) {
                    'online' { 'Healthy' }
                    'warning' { 'Degraded' }
                    'error' { 'Critical' }
                    'offline' { 'Offline' }
                    default { 'Unknown' }
                }

                $output = [PSCustomObject]@{
                    PSTypeName        = 'Verge.vSANStatus'
                    Key               = $clusterData.'$key'
                    ClusterName       = $clusterData.name
                    Description       = $clusterData.description
                    Enabled           = [bool]$clusterData.enabled
                    IsStorage         = [bool]$clusterData.storage
                    IsCompute         = [bool]$clusterData.compute
                    Status            = $statusDisplay
                    StatusRaw         = $clusterData.status
                    State             = $stateDisplay
                    StateRaw          = $clusterData.state
                    HealthStatus      = $healthStatus
                    StatusInfo        = $clusterData.status_info
                    TotalNodes        = $clusterData.total_nodes
                    OnlineNodes       = $clusterData.online_nodes
                    RunningMachines   = $clusterData.running_machines
                    TotalRAMGB        = $totalRAMGB
                    OnlineRAMGB       = $onlineRAMGB
                    UsedRAMGB         = $usedRAMGB
                    RAMUsedPercent    = $ramUsedPercent
                    TotalCores        = $clusterData.total_cores
                    OnlineCores       = $clusterData.online_cores
                    UsedCores         = $clusterData.used_cores
                    CoreUsedPercent   = $coreUsedPercent
                    LastUpdate        = $lastUpdate
                }

                if ($IncludeTierStatus) {
                    $output | Add-Member -MemberType NoteProperty -Name 'Tiers' -Value $tierData
                }

                Write-Output $output
            }
        }
        catch {
            Write-Error -Message "Failed to get vSAN status: $($_.Exception.Message)" -ErrorId 'GetvSANStatusFailed'
        }
    }
}
