function Get-VergeNetwork {
    <#
    .SYNOPSIS
        Retrieves virtual networks from VergeOS.

    .DESCRIPTION
        Get-VergeNetwork retrieves one or more virtual networks from a VergeOS system.
        You can filter networks by name, type, or power state. Supports wildcards for
        name filtering.

    .PARAMETER Name
        The name of the network to retrieve. Supports wildcards (* and ?).
        If not specified, all networks are returned.

    .PARAMETER Key
        The unique key (ID) of the network to retrieve.

    .PARAMETER Type
        Filter networks by type: Internal, External, DMZ, Core, Physical, VPN, or BGP.

    .PARAMETER PowerState
        Filter networks by power state: Running or Stopped.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeNetwork

        Retrieves all networks from the connected VergeOS system.

    .EXAMPLE
        Get-VergeNetwork -Name "Internal"

        Retrieves a specific network by name.

    .EXAMPLE
        Get-VergeNetwork -Name "Dev-*"

        Retrieves all networks whose names start with "Dev-".

    .EXAMPLE
        Get-VergeNetwork -Type External

        Retrieves all external networks.

    .EXAMPLE
        Get-VergeNetwork -PowerState Running

        Retrieves all running networks.

    .EXAMPLE
        Get-VergeNetwork | Where-Object { $_.DHCPEnabled }

        Retrieves all networks with DHCP enabled.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.Network'

    .NOTES
        Use Start-VergeNetwork, Stop-VergeNetwork to manage network power state.
        Use Get-VergeNetworkRule for firewall rules.
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
        [ValidateSet('Internal', 'External', 'DMZ', 'Core', 'Physical', 'VPN', 'BGP')]
        [string]$Type,

        [Parameter(ParameterSetName = 'Filter')]
        [ValidateSet('Running', 'Stopped')]
        [string]$PowerState,

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

            # Filter by type
            if ($Type) {
                $typeMap = @{
                    'Internal' = 'internal'
                    'External' = 'external'
                    'DMZ'      = 'dmz'
                    'Core'     = 'core'
                    'Physical' = 'physical'
                    'VPN'      = 'vpn'
                    'BGP'      = 'bgp'
                }
                $apiType = $typeMap[$Type]
                $filters.Add("type eq '$apiType'")
            }
        }

        # Apply filters
        if ($filters.Count -gt 0) {
            $queryParams['filter'] = $filters -join ' and '
        }

        # Select fields for comprehensive network data
        $queryParams['fields'] = @(
            '$key'
            'name'
            'description'
            'enabled'
            'type'
            'layer2_type'
            'layer2_id'
            'network'
            'ipaddress'
            'ipaddress_type'
            'dmz_ipaddress'
            'gateway'
            'mtu'
            'dhcp_enabled'
            'dhcp_dynamic'
            'dhcp_start'
            'dhcp_stop'
            'dhcp_sequential'
            'dns'
            'dnslist'
            'domain'
            'hostname'
            'need_fw_apply'
            'need_dns_apply'
            'need_restart'
            'statistics'
            'rate_limit'
            'rate_limit_type'
            'machine'
            'machine#status#status as status'
            'machine#status#running as running'
            'machine#status#node#name as node_name'
            'machine#cluster#name as cluster_name'
            'on_power_loss'
            'interface_vnet'
            'interface_vnet#name as interface_vnet_name'
            'proxy_enabled'
            'monitor_gateway'
        ) -join ','

        try {
            Write-Verbose "Querying networks from $($Server.Server)"
            $response = Invoke-VergeAPI -Method GET -Endpoint 'vnets' -Query $queryParams -Connection $Server

            # Handle both single object and array responses
            $networks = if ($response -is [array]) { $response } else { @($response) }

            # Filter by PowerState if specified (needs to be done post-query)
            if ($PowerState) {
                $statusMap = @{
                    'Running' = 'running'
                    'Stopped' = 'stopped'
                }
                $targetStatus = $statusMap[$PowerState]
                $networks = $networks | Where-Object { $_.status -eq $targetStatus }
            }

            foreach ($network in $networks) {
                # Skip null entries
                if (-not $network -or -not $network.name) {
                    continue
                }

                # Map status to user-friendly PowerState
                $powerStateDisplay = switch ($network.status) {
                    'running' { 'Running' }
                    'stopped' { 'Stopped' }
                    'stopping' { 'Stopping' }
                    'starting' { 'Starting' }
                    default { $network.status }
                }

                # Map type to user-friendly display
                $typeDisplay = switch ($network.type) {
                    'internal' { 'Internal' }
                    'external' { 'External' }
                    'dmz' { 'DMZ' }
                    'core' { 'Core' }
                    'physical' { 'Physical' }
                    'vpn' { 'VPN' }
                    'bgp' { 'BGP' }
                    'port_mirror' { 'Port Mirror' }
                    default { $network.type }
                }

                # Parse DNS servers list
                $dnsServers = if ($network.dnslist) {
                    $network.dnslist -split '[,\s\n]+' | Where-Object { $_ }
                } else {
                    @()
                }

                # Create output object
                $output = [PSCustomObject]@{
                    PSTypeName        = 'Verge.Network'
                    Key               = [int]$network.'$key'
                    Name              = $network.name
                    Description       = $network.description
                    Enabled           = [bool]$network.enabled
                    Type              = $typeDisplay
                    TypeRaw           = $network.type
                    PowerState        = $powerStateDisplay
                    Status            = $network.status
                    IsRunning         = [bool]$network.running
                    NetworkAddress    = $network.network
                    IPAddress         = $network.ipaddress
                    IPAddressType     = $network.ipaddress_type
                    DMZIPAddress      = $network.dmz_ipaddress
                    Gateway           = $network.gateway
                    MTU               = $network.mtu
                    DHCPEnabled       = [bool]$network.dhcp_enabled
                    DHCPDynamic       = [bool]$network.dhcp_dynamic
                    DHCPStart         = $network.dhcp_start
                    DHCPStop          = $network.dhcp_stop
                    DHCPSequential    = [bool]$network.dhcp_sequential
                    DNS               = $network.dns
                    DNSServers        = $dnsServers
                    Domain            = $network.domain
                    Hostname          = $network.hostname
                    Layer2Type        = $network.layer2_type
                    Layer2ID          = $network.layer2_id
                    Node              = $network.node_name
                    Cluster           = $network.cluster_name
                    MachineKey        = $network.machine
                    OnPowerLoss       = $network.on_power_loss
                    InterfaceNetwork  = $network.interface_vnet_name
                    InterfaceNetworkKey = $network.interface_vnet
                    ProxyEnabled      = [bool]$network.proxy_enabled
                    MonitorGateway    = [bool]$network.monitor_gateway
                    Statistics        = [bool]$network.statistics
                    RateLimit         = $network.rate_limit
                    RateLimitType     = $network.rate_limit_type
                    NeedFWApply       = [bool]$network.need_fw_apply
                    NeedDNSApply      = [bool]$network.need_dns_apply
                    NeedRestart       = [bool]$network.need_restart
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
