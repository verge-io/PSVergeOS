function Get-VergeWireGuardPeer {
    <#
    .SYNOPSIS
        Retrieves WireGuard VPN peers from a VergeOS WireGuard interface.

    .DESCRIPTION
        Get-VergeWireGuardPeer returns peer configurations for a WireGuard
        interface. Peers define remote endpoints that can connect to the tunnel.

    .PARAMETER WireGuard
        A WireGuard interface object from Get-VergeWireGuard. Accepts pipeline input.

    .PARAMETER WireGuardKey
        The key of the WireGuard interface.

    .PARAMETER Name
        Filter by peer name. Supports wildcards.

    .PARAMETER Key
        Get a specific peer by its unique key.

    .PARAMETER Server
        The VergeOS connection to use.

    .EXAMPLE
        Get-VergeWireGuard -Network "Internal" -Name "wg0" | Get-VergeWireGuardPeer

        Gets all peers for the wg0 interface.

    .EXAMPLE
        Get-VergeWireGuardPeer -WireGuardKey 123 -Name "remote*"

        Gets peers matching the wildcard pattern.

    .OUTPUTS
        Verge.WireGuardPeer

    .NOTES
        Peers define which remote endpoints can connect to the tunnel.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByWireGuard')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByWireGuard')]
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByWireGuardAndKey')]
        [PSTypeName('Verge.WireGuard')]
        [PSCustomObject]$WireGuard,

        [Parameter(Mandatory, ParameterSetName = 'ByWireGuardKey')]
        [Parameter(Mandatory, ParameterSetName = 'ByWireGuardKeyAndKey')]
        [int]$WireGuardKey,

        [Parameter(ParameterSetName = 'ByWireGuard')]
        [Parameter(ParameterSetName = 'ByWireGuardKey')]
        [SupportsWildcards()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByWireGuardAndKey')]
        [Parameter(Mandatory, ParameterSetName = 'ByWireGuardKeyAndKey')]
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

        # Firewall config mapping
        $firewallMap = @{
            'site-to-site' = 'Site-to-Site'
            'remote-user'  = 'Remote User'
            'none'         = 'None'
        }
    }

    process {
        # Get WireGuard key - match only sets that use $WireGuard object
        $useWireGuardObject = $PSCmdlet.ParameterSetName -in @('ByWireGuard', 'ByWireGuardAndKey')

        $wgKey = if ($useWireGuardObject) {
            $WireGuard.Key
        }
        else {
            $WireGuardKey
        }

        $wgName = if ($useWireGuardObject) {
            $WireGuard.Name
        }
        else {
            "WireGuard $WireGuardKey"
        }

        Write-Verbose "Querying WireGuard peers for '$wgName'"

        try {
            # Build query
            $query = @{
                fields = @(
                    '$key', 'wireguard', 'name', 'description', 'enabled',
                    'endpoint', 'port', 'peer_ip', 'public_key', 'preshared_key',
                    'allowed_ips', 'keepalive', 'configure_firewall', 'modified'
                ) -join ','
                sort = 'name'
            }

            # Add filters
            $filters = @("wireguard eq $wgKey")

            if ($PSCmdlet.ParameterSetName -like '*AndKey') {
                $filters += "`$key eq $Key"
            }
            elseif ($Name -and -not [WildcardPattern]::ContainsWildcardCharacters($Name)) {
                $filters += "name eq '$Name'"
            }

            $query['filter'] = $filters -join ' and '

            $response = Invoke-VergeAPI -Method GET -Endpoint 'vnet_wireguard_peers' -Query $query -Connection $Server

            # Handle response
            $peers = if ($null -eq $response) {
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
                $peers = $peers | Where-Object { $_.name -like $Name }
            }

            foreach ($peer in $peers) {
                [PSCustomObject]@{
                    PSTypeName         = 'Verge.WireGuardPeer'
                    Key                = $peer.'$key'
                    WireGuardKey       = $peer.wireguard
                    WireGuardName      = $wgName
                    Name               = $peer.name
                    Description        = $peer.description
                    Enabled            = $peer.enabled
                    Endpoint           = $peer.endpoint
                    Port               = $peer.port
                    PeerIP             = $peer.peer_ip
                    PublicKey          = $peer.public_key
                    HasPresharedKey    = [bool]$peer.preshared_key
                    AllowedIPs         = $peer.allowed_ips
                    Keepalive          = $peer.keepalive
                    ConfigureFirewall  = if ($firewallMap[$peer.configure_firewall]) { $firewallMap[$peer.configure_firewall] } else { $peer.configure_firewall }
                    ConfigureFirewallRaw = $peer.configure_firewall
                    Modified           = if ($peer.modified) {
                        [DateTimeOffset]::FromUnixTimeSeconds($peer.modified).LocalDateTime
                    } else { $null }
                }
            }
        }
        catch {
            Write-Error -Message "Failed to query WireGuard peers: $($_.Exception.Message)" -ErrorId 'WireGuardPeerQueryFailed'
        }
    }
}
