function Get-VergeNetworkRule {
    <#
    .SYNOPSIS
        Retrieves firewall rules from a VergeOS virtual network.

    .DESCRIPTION
        Get-VergeNetworkRule retrieves one or more firewall rules from a VergeOS network.
        You can filter rules by network, name, direction, action, or protocol.

    .PARAMETER Network
        The name or key of the network to retrieve rules from. This parameter is required.

    .PARAMETER NetworkObject
        A network object from Get-VergeNetwork. Accepts pipeline input.

    .PARAMETER Name
        The name of the rule to retrieve. Supports wildcards (* and ?).

    .PARAMETER Key
        The unique key (ID) of the rule to retrieve.

    .PARAMETER Direction
        Filter rules by direction: Incoming or Outgoing.

    .PARAMETER Action
        Filter rules by action: Accept, Drop, Reject, Translate, or Route.

    .PARAMETER Protocol
        Filter rules by protocol: TCP, UDP, TCPUDP, ICMP, or Any.

    .PARAMETER Enabled
        Filter by enabled status: $true for enabled rules, $false for disabled.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeNetworkRule -Network "External"

        Retrieves all firewall rules from the External network.

    .EXAMPLE
        Get-VergeNetworkRule -Network "External" -Direction Incoming

        Retrieves all incoming rules from the External network.

    .EXAMPLE
        Get-VergeNetworkRule -Network "DMZ" -Action Accept -Protocol TCP

        Retrieves all TCP accept rules from the DMZ network.

    .EXAMPLE
        Get-VergeNetwork -Name "External" | Get-VergeNetworkRule

        Retrieves rules from a network using pipeline input.

    .EXAMPLE
        Get-VergeNetworkRule -Network "External" -Name "Web*"

        Retrieves rules with names starting with "Web" from the External network.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.NetworkRule'

    .NOTES
        Use New-VergeNetworkRule to create new rules.
        Use Invoke-VergeNetworkApply to apply rule changes.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByNetworkName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByNetworkName')]
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByRuleKey')]
        [string]$Network,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByNetworkObject')]
        [PSTypeName('Verge.Network')]
        [PSCustomObject]$NetworkObject,

        [Parameter(ParameterSetName = 'ByNetworkName')]
        [Parameter(ParameterSetName = 'ByNetworkObject')]
        [SupportsWildcards()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByRuleKey')]
        [int]$Key,

        [Parameter(ParameterSetName = 'ByNetworkName')]
        [Parameter(ParameterSetName = 'ByNetworkObject')]
        [ValidateSet('Incoming', 'Outgoing')]
        [string]$Direction,

        [Parameter(ParameterSetName = 'ByNetworkName')]
        [Parameter(ParameterSetName = 'ByNetworkObject')]
        [ValidateSet('Accept', 'Drop', 'Reject', 'Translate', 'Route')]
        [string]$Action,

        [Parameter(ParameterSetName = 'ByNetworkName')]
        [Parameter(ParameterSetName = 'ByNetworkObject')]
        [ValidateSet('TCP', 'UDP', 'TCPUDP', 'ICMP', 'Any')]
        [string]$Protocol,

        [Parameter(ParameterSetName = 'ByNetworkName')]
        [Parameter(ParameterSetName = 'ByNetworkObject')]
        [bool]$Enabled,

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
        # Resolve network
        $targetNetwork = $null
        if ($PSCmdlet.ParameterSetName -eq 'ByNetworkObject') {
            $targetNetwork = $NetworkObject
        }
        else {
            # Get network by name or key
            if ($Network -match '^\d+$') {
                $targetNetwork = Get-VergeNetwork -Key ([int]$Network) -Server $Server
            }
            else {
                $targetNetwork = Get-VergeNetwork -Name $Network -Server $Server
            }
        }

        if (-not $targetNetwork) {
            Write-Error -Message "Network '$Network' not found" -ErrorId 'NetworkNotFound'
            return
        }

        # Build query parameters
        $queryParams = @{}

        # Build filter string
        $filters = [System.Collections.Generic.List[string]]::new()

        # Always filter by network
        $filters.Add("vnet eq $($targetNetwork.Key)")

        # Filter by key
        if ($PSCmdlet.ParameterSetName -eq 'ByRuleKey') {
            $filters.Add("`$key eq $Key")
        }
        else {
            # Filter by name (with wildcard support)
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

            # Filter by direction
            if ($Direction) {
                $directionMap = @{
                    'Incoming' = 'incoming'
                    'Outgoing' = 'outgoing'
                }
                $filters.Add("direction eq '$($directionMap[$Direction])'")
            }

            # Filter by action
            if ($Action) {
                $actionMap = @{
                    'Accept'    = 'accept'
                    'Drop'      = 'drop'
                    'Reject'    = 'reject'
                    'Translate' = 'translate'
                    'Route'     = 'route'
                }
                $filters.Add("action eq '$($actionMap[$Action])'")
            }

            # Filter by protocol
            if ($Protocol) {
                $protocolMap = @{
                    'TCP'    = 'tcp'
                    'UDP'    = 'udp'
                    'TCPUDP' = 'tcpudp'
                    'ICMP'   = 'icmp'
                    'Any'    = 'any'
                }
                $filters.Add("protocol eq '$($protocolMap[$Protocol])'")
            }

            # Filter by enabled status
            if ($PSBoundParameters.ContainsKey('Enabled')) {
                $filters.Add("enabled eq $($Enabled.ToString().ToLower())")
            }
        }

        # Apply filters
        if ($filters.Count -gt 0) {
            $queryParams['filter'] = $filters -join ' and '
        }

        # Select fields for comprehensive rule data
        $queryParams['fields'] = @(
            '$key'
            'vnet'
            'vnet#name as vnet_name'
            'name'
            'description'
            'enabled'
            'orderid'
            'pin'
            'direction'
            'action'
            'protocol'
            'interface'
            'source_ip'
            'source_ports'
            'destination_ip'
            'destination_ports'
            'target_ip'
            'target_ports'
            'ct_state'
            'statistics'
            'log'
            'trace'
            'throttle'
            'drop_throttle'
            'packets'
            'bytes'
            'system_rule'
            'modified'
        ) -join ','

        # Sort by orderid
        $queryParams['sort'] = 'orderid'

        try {
            Write-Verbose "Querying rules for network '$($targetNetwork.Name)'"
            $response = Invoke-VergeAPI -Method GET -Endpoint 'vnet_rules' -Query $queryParams -Connection $Server

            # Handle both single object and array responses
            $rules = if ($response -is [array]) { $response } else { @($response) }

            foreach ($rule in $rules) {
                # Skip null entries
                if (-not $rule -or -not $rule.name) {
                    continue
                }

                # Map to user-friendly values
                $directionDisplay = switch ($rule.direction) {
                    'incoming' { 'Incoming' }
                    'outgoing' { 'Outgoing' }
                    default { $rule.direction }
                }

                $actionDisplay = switch ($rule.action) {
                    'accept' { 'Accept' }
                    'drop' { 'Drop' }
                    'reject' { 'Reject' }
                    'translate' { 'Translate' }
                    'route' { 'Route' }
                    default { $rule.action }
                }

                $protocolDisplay = switch ($rule.protocol) {
                    'tcp' { 'TCP' }
                    'udp' { 'UDP' }
                    'tcpudp' { 'TCP/UDP' }
                    'icmp' { 'ICMP' }
                    'any' { 'Any' }
                    '89' { 'OSPF' }
                    '2' { 'IGMP' }
                    '47' { 'GRE' }
                    '50' { 'ESP' }
                    '51' { 'AH' }
                    default { $rule.protocol }
                }

                # Create output object
                $output = [PSCustomObject]@{
                    PSTypeName        = 'Verge.NetworkRule'
                    Key               = [int]$rule.'$key'
                    NetworkKey        = [int]$rule.vnet
                    NetworkName       = $rule.vnet_name
                    Name              = $rule.name
                    Description       = $rule.description
                    Enabled           = [bool]$rule.enabled
                    Order             = [int]$rule.orderid
                    Pin               = $rule.pin
                    Direction         = $directionDisplay
                    DirectionRaw      = $rule.direction
                    Action            = $actionDisplay
                    ActionRaw         = $rule.action
                    Protocol          = $protocolDisplay
                    ProtocolRaw       = $rule.protocol
                    Interface         = $rule.interface
                    SourceIP          = $rule.source_ip
                    SourcePorts       = $rule.source_ports
                    DestinationIP     = $rule.destination_ip
                    DestinationPorts  = $rule.destination_ports
                    TargetIP          = $rule.target_ip
                    TargetPorts       = $rule.target_ports
                    ConnectionState   = $rule.ct_state
                    Statistics        = [bool]$rule.statistics
                    Log               = [bool]$rule.log
                    Trace             = [bool]$rule.trace
                    Throttle          = $rule.throttle
                    DropThrottle      = [bool]$rule.drop_throttle
                    Packets           = $rule.packets
                    Bytes             = $rule.bytes
                    SystemRule        = [bool]$rule.system_rule
                    Modified          = if ($rule.modified) { [DateTimeOffset]::FromUnixTimeSeconds($rule.modified).LocalDateTime } else { $null }
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
