function Get-VergeWireGuard {
    <#
    .SYNOPSIS
        Retrieves WireGuard VPN interfaces from a VergeOS network.

    .DESCRIPTION
        Get-VergeWireGuard returns WireGuard VPN interface configurations
        from a virtual network. These define the WireGuard tunnel endpoint
        including IP address, listen port, and keys.

    .PARAMETER Network
        The name or key of the network to get WireGuard interfaces from.

    .PARAMETER NetworkObject
        A network object from Get-VergeNetwork. Accepts pipeline input.

    .PARAMETER Name
        Filter by interface name. Supports wildcards.

    .PARAMETER Key
        Get a specific interface by its unique key.

    .PARAMETER IncludePeers
        Include peer configurations in the output.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeWireGuard -Network "Internal"

        Gets all WireGuard interfaces on the Internal network.

    .EXAMPLE
        Get-VergeNetwork -Name "Internal" | Get-VergeWireGuard -Name "wg*"

        Gets WireGuard interfaces matching the wildcard pattern.

    .EXAMPLE
        Get-VergeWireGuard -Network "Internal" -IncludePeers

        Gets interfaces with their peer configurations.

    .OUTPUTS
        Verge.WireGuard

    .NOTES
        WireGuard provides a modern, fast VPN tunnel.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByNetworkName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByNetworkName')]
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByNetworkNameAndKey')]
        [string]$Network,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByNetworkObject')]
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByNetworkObjectAndKey')]
        [PSTypeName('Verge.Network')]
        [PSCustomObject]$NetworkObject,

        [Parameter(ParameterSetName = 'ByNetworkName')]
        [Parameter(ParameterSetName = 'ByNetworkObject')]
        [SupportsWildcards()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByNetworkNameAndKey')]
        [Parameter(Mandatory, ParameterSetName = 'ByNetworkObjectAndKey')]
        [int]$Key,

        [Parameter()]
        [switch]$IncludePeers,

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
        if ($PSCmdlet.ParameterSetName -like 'ByNetworkObject*') {
            $targetNetwork = $NetworkObject
        }
        else {
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

        Write-Verbose "Querying WireGuard interfaces for network '$($targetNetwork.Name)'"

        try {
            # Build query
            $query = @{
                fields = @(
                    '$key', 'vnet', 'name', 'description', 'enabled',
                    'ip', 'listenport', 'mtu', 'public_key', 'endpoint_ip', 'modified'
                ) -join ','
                sort = 'name'
            }

            # Add filters
            $filters = @("vnet eq $($targetNetwork.Key)")

            if ($PSCmdlet.ParameterSetName -like '*AndKey') {
                $filters += "`$key eq $Key"
            }
            elseif ($Name -and -not [WildcardPattern]::ContainsWildcardCharacters($Name)) {
                $filters += "name eq '$Name'"
            }

            $query['filter'] = $filters -join ' and '

            $response = Invoke-VergeAPI -Method GET -Endpoint 'vnet_wireguards' -Query $query -Connection $Server

            # Handle response
            $interfaces = if ($null -eq $response) {
                @()
            }
            elseif ($response -is [array]) {
                $response
            }
            elseif ($response.'$key') {
                @($response)
            }
            else {
                @()
            }

            # Apply wildcard filter if needed
            if ($Name -and [WildcardPattern]::ContainsWildcardCharacters($Name)) {
                $interfaces = $interfaces | Where-Object { $_.name -like $Name }
            }

            foreach ($iface in $interfaces) {
                # Parse IP and subnet
                $ipParts = $iface.ip -split '/'
                $ipAddress = $ipParts[0]
                $subnetMask = if ($ipParts.Count -gt 1) { $ipParts[1] } else { '32' }

                $output = [PSCustomObject]@{
                    PSTypeName    = 'Verge.WireGuard'
                    Key           = $iface.'$key'
                    NetworkKey    = $targetNetwork.Key
                    NetworkName   = $targetNetwork.Name
                    Name          = $iface.name
                    Description   = $iface.description
                    Enabled       = $iface.enabled
                    IPAddress     = $ipAddress
                    SubnetMask    = $subnetMask
                    CIDR          = $iface.ip
                    ListenPort    = $iface.listenport
                    MTU           = if ($iface.mtu -eq 0) { 'Auto' } else { $iface.mtu }
                    MTURaw        = $iface.mtu
                    PublicKey     = $iface.public_key
                    EndpointIP    = $iface.endpoint_ip
                    Modified      = if ($iface.modified) {
                        [DateTimeOffset]::FromUnixTimeSeconds($iface.modified).LocalDateTime
                    } else { $null }
                }

                # Include peers if requested
                if ($IncludePeers) {
                    $peerQuery = @{
                        filter = "wireguard eq $($iface.'$key')"
                        fields = '$key,name,description,enabled,endpoint,port,peer_ip,public_key,allowed_ips,keepalive,configure_firewall'
                        sort   = 'name'
                    }

                    $peerResponse = Invoke-VergeAPI -Method GET -Endpoint 'vnet_wireguard_peers' -Query $peerQuery -Connection $Server

                    $peers = if ($null -eq $peerResponse) {
                        @()
                    }
                    elseif ($peerResponse -is [array]) {
                        $peerResponse
                    }
                    elseif ($peerResponse.'$key') {
                        @($peerResponse)
                    }
                    else {
                        @()
                    }

                    $peerObjects = foreach ($peer in $peers) {
                        [PSCustomObject]@{
                            PSTypeName         = 'Verge.WireGuardPeer'
                            Key                = $peer.'$key'
                            WireGuardKey       = $iface.'$key'
                            Name               = $peer.name
                            Description        = $peer.description
                            Enabled            = $peer.enabled
                            Endpoint           = $peer.endpoint
                            Port               = $peer.port
                            PeerIP             = $peer.peer_ip
                            PublicKey          = $peer.public_key
                            AllowedIPs         = $peer.allowed_ips
                            Keepalive          = $peer.keepalive
                            ConfigureFirewall  = $peer.configure_firewall
                        }
                    }

                    $output | Add-Member -MemberType NoteProperty -Name 'Peers' -Value $peerObjects
                    $output | Add-Member -MemberType NoteProperty -Name 'PeerCount' -Value $peerObjects.Count
                }

                Write-Output $output
            }
        }
        catch {
            Write-Error -Message "Failed to query WireGuard interfaces: $($_.Exception.Message)" -ErrorId 'WireGuardQueryFailed'
        }
    }
}
