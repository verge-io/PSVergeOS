function New-VergeNetworkRule {
    <#
    .SYNOPSIS
        Creates a new firewall rule on a VergeOS virtual network.

    .DESCRIPTION
        New-VergeNetworkRule creates a new firewall rule with the specified configuration.
        After creating rules, use Invoke-VergeNetworkApply to apply the changes.

    .PARAMETER Network
        The name or key of the network to create the rule on.

    .PARAMETER NetworkObject
        A network object from Get-VergeNetwork. Accepts pipeline input.

    .PARAMETER Name
        The name of the new rule. Must be unique within the network.

    .PARAMETER Description
        An optional description for the rule.

    .PARAMETER Direction
        The direction of traffic: Incoming or Outgoing. Default is Incoming.

    .PARAMETER Action
        The action to take: Accept, Drop, Reject, Translate, or Route.
        Default is Accept.

    .PARAMETER Protocol
        The protocol to match: TCP, UDP, TCPUDP, ICMP, Any. Default is Any.

    .PARAMETER SourceIP
        Source IP filter (e.g., "192.168.0.1", "192.168.1.0/24", or comma-separated list).
        Special values: vnetself, router, vnet:name, vmnic:vmname.nicname

    .PARAMETER SourcePorts
        Source ports or ranges (e.g., "80", "1024-65535", or comma-separated list).

    .PARAMETER DestinationIP
        Destination IP filter. Same format as SourceIP.

    .PARAMETER DestinationPorts
        Destination ports or ranges (e.g., "443", "80,443", "1000-2000").

    .PARAMETER TargetIP
        Target IP for Translate/Route actions (e.g., "192.168.0.10", "router", "vmnic:vmname.nicname").

    .PARAMETER TargetPorts
        Target ports for port translation. Leave blank if same as destination.

    .PARAMETER Interface
        The interface for the rule: Auto, Router, DMZ, WireGuard, Any. Default is Auto.

    .PARAMETER Enabled
        Whether the rule is enabled. Default is $true.

    .PARAMETER Log
        Enable logging for this rule.

    .PARAMETER Statistics
        Enable statistics tracking for this rule.

    .PARAMETER OrderPosition
        Position in the rule order. Use "Top", "Bottom", or a number.
        Default adds to the bottom.

    .PARAMETER Apply
        Automatically apply rules after creation.

    .PARAMETER PassThru
        Return the created rule object.

    .PARAMETER Server
        The VergeOS connection to use.

    .EXAMPLE
        New-VergeNetworkRule -Network "External" -Name "Allow HTTPS" -Direction Incoming -Action Accept -Protocol TCP -DestinationPorts "443"

        Creates a rule to allow incoming HTTPS traffic.

    .EXAMPLE
        New-VergeNetworkRule -Network "External" -Name "NAT to Web" -Direction Incoming -Action Translate -Protocol TCP -DestinationPorts "80,443" -TargetIP "192.168.0.10"

        Creates a NAT rule to translate HTTP/HTTPS to an internal server.

    .EXAMPLE
        New-VergeNetworkRule -Network "DMZ" -Name "Block All" -Direction Incoming -Action Drop -Protocol Any -OrderPosition Top

        Creates a drop-all rule at the top of the rule list.

    .OUTPUTS
        None by default. Verge.NetworkRule when -PassThru is specified.

    .NOTES
        Rules are not active until Invoke-VergeNetworkApply is called, or use -Apply.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByNetworkName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByNetworkName')]
        [string]$Network,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByNetworkObject')]
        [PSTypeName('Verge.Network')]
        [PSCustomObject]$NetworkObject,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [ValidateLength(1, 128)]
        [string]$Name,

        [Parameter()]
        [ValidateLength(0, 2048)]
        [string]$Description,

        [Parameter()]
        [ValidateSet('Incoming', 'Outgoing')]
        [string]$Direction = 'Incoming',

        [Parameter()]
        [ValidateSet('Accept', 'Drop', 'Reject', 'Translate', 'Route')]
        [string]$Action = 'Accept',

        [Parameter()]
        [ValidateSet('TCP', 'UDP', 'TCPUDP', 'ICMP', 'Any')]
        [string]$Protocol = 'Any',

        [Parameter()]
        [string]$SourceIP,

        [Parameter()]
        [string]$SourcePorts,

        [Parameter()]
        [string]$DestinationIP,

        [Parameter()]
        [string]$DestinationPorts,

        [Parameter()]
        [string]$TargetIP,

        [Parameter()]
        [string]$TargetPorts,

        [Parameter()]
        [ValidateSet('Auto', 'Router', 'DMZ', 'WireGuard', 'Any')]
        [string]$Interface = 'Auto',

        [Parameter()]
        [bool]$Enabled = $true,

        [Parameter()]
        [switch]$Log,

        [Parameter()]
        [switch]$Statistics,

        [Parameter()]
        [string]$OrderPosition,

        [Parameter()]
        [switch]$Apply,

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
        $directionMap = @{
            'Incoming' = 'incoming'
            'Outgoing' = 'outgoing'
        }

        $actionMap = @{
            'Accept'    = 'accept'
            'Drop'      = 'drop'
            'Reject'    = 'reject'
            'Translate' = 'translate'
            'Route'     = 'route'
        }

        $protocolMap = @{
            'TCP'    = 'tcp'
            'UDP'    = 'udp'
            'TCPUDP' = 'tcpudp'
            'ICMP'   = 'icmp'
            'Any'    = 'any'
        }

        $interfaceMap = @{
            'Auto'      = 'auto'
            'Router'    = 'router'
            'DMZ'       = 'dmz'
            'WireGuard' = 'wireguard'
            'Any'       = 'any'
        }
    }

    process {
        # Resolve network
        $targetNetwork = $null
        if ($PSCmdlet.ParameterSetName -eq 'ByNetworkObject') {
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
            throw "Network '$Network' not found"
        }

        # Build request body
        $body = @{
            vnet      = $targetNetwork.Key
            name      = $Name
            direction = $directionMap[$Direction]
            action    = $actionMap[$Action]
            protocol  = $protocolMap[$Protocol]
            interface = $interfaceMap[$Interface]
            enabled   = $Enabled
        }

        # Add optional parameters
        if ($Description) {
            $body['description'] = $Description
        }

        if ($SourceIP) {
            $body['source_ip'] = $SourceIP
        }

        if ($SourcePorts) {
            $body['source_ports'] = $SourcePorts
        }

        if ($DestinationIP) {
            $body['destination_ip'] = $DestinationIP
        }

        if ($DestinationPorts) {
            $body['destination_ports'] = $DestinationPorts
        }

        if ($TargetIP) {
            $body['target_ip'] = $TargetIP
        }

        if ($TargetPorts) {
            $body['target_ports'] = $TargetPorts
        }

        if ($Log) {
            $body['log'] = $true
        }

        if ($Statistics) {
            $body['statistics'] = $true
        }

        # Handle order position
        if ($OrderPosition) {
            switch ($OrderPosition.ToLower()) {
                'top' { $body['pin'] = 'top' }
                'bottom' { $body['pin'] = 'bottom' }
                default {
                    if ($OrderPosition -match '^\d+$') {
                        $body['orderid'] = [int]$OrderPosition
                    }
                }
            }
        }

        # Build action description
        $actionDescription = "Create $Action rule '$Name' for $Protocol $Direction traffic"
        if ($DestinationPorts) {
            $actionDescription += " on port(s) $DestinationPorts"
        }

        if ($PSCmdlet.ShouldProcess($targetNetwork.Name, $actionDescription)) {
            try {
                Write-Verbose "Creating rule '$Name' on network '$($targetNetwork.Name)'"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'vnet_rules' -Body $body -Connection $Server

                # Get the created rule key
                $ruleKey = $response.'$key'
                if (-not $ruleKey -and $response.key) {
                    $ruleKey = $response.key
                }

                Write-Verbose "Rule '$Name' created with Key: $ruleKey"

                # Apply rules if requested
                if ($Apply) {
                    Write-Verbose "Applying rules on network '$($targetNetwork.Name)'"
                    Invoke-VergeNetworkApply -Network $targetNetwork.Key -Server $Server
                }

                if ($PassThru -and $ruleKey) {
                    # Return the created rule
                    Start-Sleep -Milliseconds 500
                    Get-VergeNetworkRule -Network $targetNetwork.Key -Key $ruleKey -Server $Server
                }
            }
            catch {
                $errorMessage = $_.Exception.Message
                if ($errorMessage -match 'already in use') {
                    throw "A rule with the name '$Name' already exists on network '$($targetNetwork.Name)'."
                }
                throw "Failed to create rule '$Name': $errorMessage"
            }
        }
    }
}
