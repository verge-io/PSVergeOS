function New-VergeNetwork {
    <#
    .SYNOPSIS
        Creates a new virtual network in VergeOS.

    .DESCRIPTION
        New-VergeNetwork creates a new virtual network with the specified configuration.
        The network is created in a stopped state by default. Use -PowerOn to start
        the network immediately after creation.

    .PARAMETER Name
        The name of the new network. Must be unique and 1-128 characters.

    .PARAMETER Type
        The network type. Valid values: Internal, External, DMZ.
        Default is Internal.

    .PARAMETER NetworkAddress
        The network address in CIDR notation (e.g., "10.0.0.0/24").

    .PARAMETER IPAddress
        The IP address for the network router within the network.

    .PARAMETER Gateway
        The default gateway IP address (sent as DHCP option to clients).

    .PARAMETER Description
        An optional description for the network.

    .PARAMETER DHCPEnabled
        Enable DHCP server on this network.

    .PARAMETER DHCPStart
        The starting IP address for DHCP range.

    .PARAMETER DHCPStop
        The ending IP address for DHCP range.

    .PARAMETER DHCPDynamic
        Enable dynamic DHCP (create host entries for DHCP leases).

    .PARAMETER DNS
        DNS server mode. Valid values: Disabled, Simple, Bind, Network.
        Default is Simple.

    .PARAMETER DNSServers
        List of DNS server IP addresses to provide via DHCP.

    .PARAMETER Domain
        The domain name for this network.

    .PARAMETER MTU
        The MTU size (1000-65536). Leave unset for default.

    .PARAMETER InterfaceNetwork
        The name or key of another network to use as the interface (uplink) network.
        Required for External and DMZ type networks.

    .PARAMETER Layer2Type
        The Layer 2 encapsulation type. Valid values: vLan, vxLan, None.
        Default is vxLan.

    .PARAMETER Layer2ID
        The VLAN or VXLAN ID. If not specified, one will be auto-assigned.

    .PARAMETER OnPowerLoss
        Behavior when power is restored. Valid values: PowerOn, LastState, LeaveOff.
        Default is LastState.

    .PARAMETER Cluster
        The cluster to run the network on.

    .PARAMETER PowerOn
        Start the network immediately after creation.

    .PARAMETER PassThru
        Return the created network object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeNetwork -Name "Dev-Network" -NetworkAddress "10.10.10.0/24"

        Creates a basic internal network with the specified address range.

    .EXAMPLE
        New-VergeNetwork -Name "Dev-Network" -NetworkAddress "10.10.10.0/24" -DHCPEnabled -DHCPStart "10.10.10.100" -DHCPStop "10.10.10.200"

        Creates an internal network with DHCP enabled.

    .EXAMPLE
        New-VergeNetwork -Name "Web-DMZ" -Type DMZ -NetworkAddress "172.16.0.0/24" -IPAddress "172.16.0.1" -InterfaceNetwork "External" -PowerOn -PassThru

        Creates a DMZ network connected to the External network and starts it.

    .OUTPUTS
        None by default. Verge.Network when -PassThru is specified.

    .NOTES
        After creating a network, use New-VergeNetworkRule to add firewall rules
        and Invoke-VergeNetworkApply to apply them.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [ValidateLength(1, 128)]
        [string]$Name,

        [Parameter()]
        [ValidateSet('Internal', 'External', 'DMZ')]
        [string]$Type = 'Internal',

        [Parameter()]
        [ValidatePattern('^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)/(3[0-2]|[1-2][0-9]|[0-9])$')]
        [string]$NetworkAddress,

        [Parameter()]
        [ValidatePattern('^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$')]
        [string]$IPAddress,

        [Parameter()]
        [ValidatePattern('^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$')]
        [string]$Gateway,

        [Parameter()]
        [ValidateLength(0, 2048)]
        [string]$Description,

        [Parameter()]
        [switch]$DHCPEnabled,

        [Parameter()]
        [ValidatePattern('^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$')]
        [string]$DHCPStart,

        [Parameter()]
        [ValidatePattern('^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$')]
        [string]$DHCPStop,

        [Parameter()]
        [switch]$DHCPDynamic,

        [Parameter()]
        [ValidateSet('Disabled', 'Simple', 'Bind', 'Network')]
        [string]$DNS = 'Simple',

        [Parameter()]
        [string[]]$DNSServers,

        [Parameter()]
        [string]$Domain,

        [Parameter()]
        [ValidateRange(1000, 65536)]
        [int]$MTU,

        [Parameter()]
        [string]$InterfaceNetwork,

        [Parameter()]
        [ValidateSet('vLan', 'vxLan', 'None')]
        [string]$Layer2Type = 'vxLan',

        [Parameter()]
        [int]$Layer2ID,

        [Parameter()]
        [ValidateSet('PowerOn', 'LastState', 'LeaveOff')]
        [string]$OnPowerLoss = 'LastState',

        [Parameter()]
        [string]$Cluster,

        [Parameter()]
        [switch]$PowerOn,

        [Parameter()]
        [switch]$PassThru,

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

        # Map friendly names to API values
        $typeMap = @{
            'Internal' = 'internal'
            'External' = 'external'
            'DMZ'      = 'dmz'
        }

        $dnsMap = @{
            'Disabled' = 'disabled'
            'Simple'   = 'simple'
            'Bind'     = 'bind'
            'Network'  = 'network'
        }

        $layer2Map = @{
            'vLan'  = 'vlan'
            'vxLan' = 'vxlan'
            'None'  = 'none'
        }

        $powerLossMap = @{
            'PowerOn'   = 'power_on'
            'LastState' = 'last_state'
            'LeaveOff'  = 'leave_off'
        }
    }

    process {
        # Build request body
        $body = @{
            name         = $Name
            type         = $typeMap[$Type]
            layer2_type  = $layer2Map[$Layer2Type]
            dns          = $dnsMap[$DNS]
            on_power_loss = $powerLossMap[$OnPowerLoss]
        }

        # Add optional parameters
        if ($Description) {
            $body['description'] = $Description
        }

        if ($NetworkAddress) {
            $body['network'] = $NetworkAddress
        }

        if ($IPAddress) {
            $body['ipaddress'] = $IPAddress
        }

        if ($Gateway) {
            $body['gateway'] = $Gateway
        }

        if ($DHCPEnabled) {
            $body['dhcp_enabled'] = $true
        }

        if ($DHCPStart) {
            $body['dhcp_start'] = $DHCPStart
        }

        if ($DHCPStop) {
            $body['dhcp_stop'] = $DHCPStop
        }

        if ($DHCPDynamic) {
            $body['dhcp_dynamic'] = $true
        }

        if ($DNSServers -and $DNSServers.Count -gt 0) {
            $body['dnslist'] = $DNSServers -join ','
        }

        if ($Domain) {
            $body['domain'] = $Domain
        }

        if ($MTU) {
            $body['mtu'] = $MTU
        }

        if ($Layer2ID) {
            $body['layer2_id'] = $Layer2ID
        }

        # Resolve interface network if specified
        if ($InterfaceNetwork) {
            if ($InterfaceNetwork -match '^\d+$') {
                $body['interface_vnet'] = [int]$InterfaceNetwork
            }
            else {
                try {
                    $netResponse = Invoke-VergeAPI -Method GET -Endpoint 'vnets' -Query @{
                        filter = "name eq '$InterfaceNetwork'"
                        fields = '$key,name'
                    } -Connection $Server

                    if ($netResponse -and $netResponse.'$key') {
                        $body['interface_vnet'] = $netResponse.'$key'
                    }
                    elseif ($netResponse -is [array] -and $netResponse.Count -gt 0) {
                        $body['interface_vnet'] = $netResponse[0].'$key'
                    }
                    else {
                        throw "Interface network '$InterfaceNetwork' not found"
                    }
                }
                catch {
                    throw "Failed to resolve interface network '$InterfaceNetwork': $($_.Exception.Message)"
                }
            }
        }

        # Resolve cluster if specified
        if ($Cluster) {
            if ($Cluster -match '^\d+$') {
                $body['cluster'] = [int]$Cluster
            }
            else {
                try {
                    $clusterResponse = Invoke-VergeAPI -Method GET -Endpoint 'clusters' -Query @{
                        filter = "name eq '$Cluster'"
                        fields = '$key,name'
                    } -Connection $Server

                    if ($clusterResponse -and $clusterResponse.'$key') {
                        $body['cluster'] = $clusterResponse.'$key'
                    }
                    elseif ($clusterResponse -is [array] -and $clusterResponse.Count -gt 0) {
                        $body['cluster'] = $clusterResponse[0].'$key'
                    }
                    else {
                        throw "Cluster '$Cluster' not found"
                    }
                }
                catch {
                    throw "Failed to resolve cluster '$Cluster': $($_.Exception.Message)"
                }
            }
        }

        # Confirm action
        $actionDescription = "Create $Type network '$Name'"
        if ($NetworkAddress) {
            $actionDescription += " ($NetworkAddress)"
        }

        if ($PSCmdlet.ShouldProcess($Name, 'Create Network')) {
            try {
                Write-Verbose "Creating network '$Name'"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'vnets' -Body $body -Connection $Server

                # Get the created network key
                $networkKey = $response.'$key'
                if (-not $networkKey -and $response.key) {
                    $networkKey = $response.key
                }

                Write-Verbose "Network '$Name' created with Key: $networkKey"

                # Power on if requested
                if ($PowerOn -and $networkKey) {
                    Write-Verbose "Powering on network '$Name'"
                    $powerBody = @{
                        vnet   = $networkKey
                        action = 'poweron'
                        params = @{
                            apply = $true
                        }
                    }
                    Invoke-VergeAPI -Method POST -Endpoint 'vnet_actions' -Body $powerBody -Connection $Server | Out-Null
                }

                if ($PassThru -and $networkKey) {
                    # Return the created network
                    Start-Sleep -Milliseconds 500
                    Get-VergeNetwork -Key $networkKey -Server $Server
                }
            }
            catch {
                $errorMessage = $_.Exception.Message
                if ($errorMessage -match 'already in use') {
                    throw "A network with the name '$Name' already exists."
                }
                throw "Failed to create network '$Name': $errorMessage"
            }
        }
    }
}
