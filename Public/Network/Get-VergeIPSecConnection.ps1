function Get-VergeIPSecConnection {
    <#
    .SYNOPSIS
        Retrieves IPSec VPN connections from a VergeOS network.

    .DESCRIPTION
        Get-VergeIPSecConnection returns IPSec Phase 1 (IKE) VPN connections
        configured on a virtual network. These define the IKE security association
        including remote gateway, authentication, and encryption settings.

    .PARAMETER Network
        The name or key of the network to get IPSec connections from.

    .PARAMETER NetworkObject
        A network object from Get-VergeNetwork. Accepts pipeline input.

    .PARAMETER Name
        Filter by connection name. Supports wildcards.

    .PARAMETER Key
        Get a specific connection by its unique key.

    .PARAMETER IncludePolicies
        Include Phase 2 policies (traffic selectors) in the output.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeIPSecConnection -Network "External"

        Gets all IPSec connections on the External network.

    .EXAMPLE
        Get-VergeNetwork -Name "External" | Get-VergeIPSecConnection -Name "Site-to-Site*"

        Gets IPSec connections matching the wildcard pattern.

    .EXAMPLE
        Get-VergeIPSecConnection -Network "External" -IncludePolicies

        Gets connections with their Phase 2 traffic selector policies.

    .OUTPUTS
        Verge.IPSecConnection

    .NOTES
        IPSec connections require an IPSec configuration to exist on the network.
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
        [switch]$IncludePolicies,

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

        # Key exchange mapping
        $keyExchangeMap = @{
            'ike'   = 'Auto'
            'ikev1' = 'IKEv1'
            'ikev2' = 'IKEv2'
        }

        # Auth method mapping
        $authMap = @{
            'psk'    = 'Pre-Shared Key'
            'pubkey' = 'RSA Certificate'
        }

        # Connection behavior mapping
        $autoMap = @{
            'add'   = 'Responder Only'
            'route' = 'On-Demand'
            'start' = 'Always Start'
        }

        # DPD action mapping
        $dpdMap = @{
            'none'    = 'Disabled'
            'clear'   = 'Clear'
            'hold'    = 'Hold'
            'restart' = 'Restart'
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

        Write-Verbose "Querying IPSec connections for network '$($targetNetwork.Name)'"

        try {
            # First get the IPSec config for this network
            $ipsecQuery = @{
                filter = "vnet eq $($targetNetwork.Key)"
                fields = '$key,enabled,mode,uniqueids,compress'
            }

            $ipsecConfig = Invoke-VergeAPI -Method GET -Endpoint 'vnet_ipsecs' -Query $ipsecQuery -Connection $Server

            if (-not $ipsecConfig -or (-not $ipsecConfig.'$key' -and $ipsecConfig.Count -eq 0)) {
                Write-Verbose "No IPSec configuration found for network '$($targetNetwork.Name)'"
                return
            }

            # Get the IPSec config key
            $ipsecKey = if ($ipsecConfig -is [array]) {
                $ipsecConfig[0].'$key'
            }
            else {
                $ipsecConfig.'$key'
            }

            if (-not $ipsecKey) {
                Write-Verbose "No IPSec configuration key found"
                return
            }

            # Build Phase 1 query
            $phase1Query = @{
                fields = @(
                    '$key', 'ipsec', 'enabled', 'name', 'description',
                    'keyexchange', 'remote_gateway', 'auth', 'negotiation',
                    'identifier', 'peer_identifier', 'ike', 'ikelifetime',
                    'auto', 'mobike', 'split_connections', 'forceencaps',
                    'keyingtries', 'rekey', 'reauth', 'margintime',
                    'dpdaction', 'dpddelay', 'dpdfailures', 'modified'
                ) -join ','
                sort = 'name'
            }

            # Add filters
            $filters = @("ipsec eq $ipsecKey")

            if ($PSCmdlet.ParameterSetName -like '*AndKey') {
                $filters += "`$key eq $Key"
            }
            elseif ($Name -and -not [WildcardPattern]::ContainsWildcardCharacters($Name)) {
                $filters += "name eq '$Name'"
            }

            $phase1Query['filter'] = $filters -join ' and '

            $response = Invoke-VergeAPI -Method GET -Endpoint 'vnet_ipsec_phase1s' -Query $phase1Query -Connection $Server

            # Handle response
            $connections = if ($null -eq $response) {
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
                $connections = $connections | Where-Object { $_.name -like $Name }
            }

            foreach ($conn in $connections) {
                $output = [PSCustomObject]@{
                    PSTypeName       = 'Verge.IPSecConnection'
                    Key              = $conn.'$key'
                    IPSecKey         = $conn.ipsec
                    NetworkKey       = $targetNetwork.Key
                    NetworkName      = $targetNetwork.Name
                    Name             = $conn.name
                    Description      = $conn.description
                    Enabled          = $conn.enabled
                    RemoteGateway    = $conn.remote_gateway
                    KeyExchange      = if ($keyExchangeMap[$conn.keyexchange]) { $keyExchangeMap[$conn.keyexchange] } else { $conn.keyexchange }
                    KeyExchangeRaw   = $conn.keyexchange
                    AuthMethod       = if ($authMap[$conn.auth]) { $authMap[$conn.auth] } else { $conn.auth }
                    AuthMethodRaw    = $conn.auth
                    Negotiation      = $conn.negotiation
                    Identifier       = $conn.identifier
                    PeerIdentifier   = $conn.peer_identifier
                    Encryption       = $conn.ike
                    IKELifetime      = $conn.ikelifetime
                    ConnectionMode   = if ($autoMap[$conn.auto]) { $autoMap[$conn.auto] } else { $conn.auto }
                    ConnectionModeRaw = $conn.auto
                    MOBIKE           = $conn.mobike
                    SplitConnections = $conn.split_connections
                    ForceUDPEncap    = $conn.forceencaps
                    KeyingTries      = $conn.keyingtries
                    Rekey            = $conn.rekey
                    Reauthenticate   = $conn.reauth
                    MarginTime       = $conn.margintime
                    DPDAction        = if ($dpdMap[$conn.dpdaction]) { $dpdMap[$conn.dpdaction] } else { $conn.dpdaction }
                    DPDActionRaw     = $conn.dpdaction
                    DPDDelay         = $conn.dpddelay
                    DPDFailures      = $conn.dpdfailures
                    Modified         = if ($conn.modified) {
                        [DateTimeOffset]::FromUnixTimeSeconds($conn.modified).LocalDateTime
                    } else { $null }
                }

                # Include Phase 2 policies if requested
                if ($IncludePolicies) {
                    $phase2Query = @{
                        filter = "phase1 eq $($conn.'$key')"
                        fields = '$key,enabled,name,description,mode,local,remote,lifetime,protocol,ciphers'
                        sort   = 'name'
                    }

                    $phase2Response = Invoke-VergeAPI -Method GET -Endpoint 'vnet_ipsec_phase2s' -Query $phase2Query -Connection $Server

                    $policies = if ($null -eq $phase2Response) {
                        @()
                    }
                    elseif ($phase2Response -is [array]) {
                        $phase2Response
                    }
                    elseif ($phase2Response.'$key') {
                        @($phase2Response)
                    }
                    else {
                        @()
                    }

                    $policyObjects = foreach ($policy in $policies) {
                        [PSCustomObject]@{
                            PSTypeName   = 'Verge.IPSecPolicy'
                            Key          = $policy.'$key'
                            Phase1Key    = $conn.'$key'
                            Name         = $policy.name
                            Description  = $policy.description
                            Enabled      = $policy.enabled
                            Mode         = $policy.mode
                            LocalNetwork = $policy.local
                            RemoteNetwork = $policy.remote
                            Lifetime     = $policy.lifetime
                            Protocol     = $policy.protocol
                            Ciphers      = $policy.ciphers
                        }
                    }

                    $output | Add-Member -MemberType NoteProperty -Name 'Policies' -Value $policyObjects
                    $output | Add-Member -MemberType NoteProperty -Name 'PolicyCount' -Value $policyObjects.Count
                }

                Write-Output $output
            }
        }
        catch {
            Write-Error -Message "Failed to query IPSec connections: $($_.Exception.Message)" -ErrorId 'IPSecQueryFailed'
        }
    }
}
