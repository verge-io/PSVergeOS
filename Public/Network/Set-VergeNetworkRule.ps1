function Set-VergeNetworkRule {
    <#
    .SYNOPSIS
        Modifies an existing firewall rule on a VergeOS virtual network.

    .DESCRIPTION
        Set-VergeNetworkRule modifies properties of an existing firewall rule.
        After modifying rules, use Invoke-VergeNetworkApply to apply the changes.

    .PARAMETER Network
        The name or key of the network containing the rule.

    .PARAMETER Name
        The name of the rule to modify.

    .PARAMETER Key
        The unique key (ID) of the rule to modify.

    .PARAMETER Rule
        A rule object from Get-VergeNetworkRule. Accepts pipeline input.

    .PARAMETER NewName
        A new name for the rule.

    .PARAMETER Description
        An updated description for the rule.

    .PARAMETER Direction
        The direction of traffic: Incoming or Outgoing.

    .PARAMETER Action
        The action to take: Accept, Drop, Reject, Translate, or Route.

    .PARAMETER Protocol
        The protocol to match: TCP, UDP, TCPUDP, ICMP, Any.

    .PARAMETER SourceIP
        Source IP filter.

    .PARAMETER SourcePorts
        Source ports or ranges.

    .PARAMETER DestinationIP
        Destination IP filter.

    .PARAMETER DestinationPorts
        Destination ports or ranges.

    .PARAMETER TargetIP
        Target IP for Translate/Route actions.

    .PARAMETER TargetPorts
        Target ports for port translation.

    .PARAMETER Interface
        The interface for the rule: Auto, Router, DMZ, WireGuard, Any.

    .PARAMETER Enabled
        Enable or disable the rule.

    .PARAMETER Log
        Enable or disable logging for this rule.

    .PARAMETER Statistics
        Enable or disable statistics tracking.

    .PARAMETER Apply
        Automatically apply rules after modification.

    .PARAMETER PassThru
        Return the modified rule object.

    .PARAMETER Server
        The VergeOS connection to use.

    .EXAMPLE
        Set-VergeNetworkRule -Network "External" -Name "Allow HTTPS" -Enabled $false

        Disables the "Allow HTTPS" rule.

    .EXAMPLE
        Set-VergeNetworkRule -Network "External" -Name "NAT to Web" -TargetIP "192.168.0.20" -Apply

        Updates the target IP and applies the changes immediately.

    .EXAMPLE
        Get-VergeNetworkRule -Network "External" -Name "Web*" | Set-VergeNetworkRule -Enabled $false

        Disables all rules starting with "Web" using pipeline.

    .OUTPUTS
        None by default. Verge.NetworkRule when -PassThru is specified.

    .NOTES
        Rule changes are not active until Invoke-VergeNetworkApply is called, or use -Apply.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByKey')]
        [string]$Network,

        [Parameter(Mandatory, Position = 1, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByRule')]
        [PSTypeName('Verge.NetworkRule')]
        [PSCustomObject]$Rule,

        [Parameter()]
        [ValidateLength(1, 128)]
        [string]$NewName,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [ValidateSet('Incoming', 'Outgoing')]
        [string]$Direction,

        [Parameter()]
        [ValidateSet('Accept', 'Drop', 'Reject', 'Translate', 'Route')]
        [string]$Action,

        [Parameter()]
        [ValidateSet('TCP', 'UDP', 'TCPUDP', 'ICMP', 'Any')]
        [string]$Protocol,

        [Parameter()]
        [AllowEmptyString()]
        [string]$SourceIP,

        [Parameter()]
        [AllowEmptyString()]
        [string]$SourcePorts,

        [Parameter()]
        [AllowEmptyString()]
        [string]$DestinationIP,

        [Parameter()]
        [AllowEmptyString()]
        [string]$DestinationPorts,

        [Parameter()]
        [AllowEmptyString()]
        [string]$TargetIP,

        [Parameter()]
        [AllowEmptyString()]
        [string]$TargetPorts,

        [Parameter()]
        [ValidateSet('Auto', 'Router', 'DMZ', 'WireGuard', 'Any')]
        [string]$Interface,

        [Parameter()]
        [bool]$Enabled,

        [Parameter()]
        [bool]$Log,

        [Parameter()]
        [bool]$Statistics,

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
        # Get the rule to modify
        $targetRule = switch ($PSCmdlet.ParameterSetName) {
            'ByName' {
                Get-VergeNetworkRule -Network $Network -Name $Name -Server $Server
            }
            'ByKey' {
                Get-VergeNetworkRule -Network $Network -Key $Key -Server $Server
            }
            'ByRule' {
                $Rule
            }
        }

        if (-not $targetRule) {
            Write-Error -Message "Rule not found" -ErrorId 'RuleNotFound'
            return
        }

        # Handle multiple matches
        if ($targetRule -is [array]) {
            Write-Error -Message "Multiple rules matched. Please specify a unique name or use -Key." -ErrorId 'MultipleRulesMatched'
            return
        }

        # Check for system rule
        if ($targetRule.SystemRule) {
            Write-Error -Message "Cannot modify system rule '$($targetRule.Name)'" -ErrorId 'CannotModifySystemRule'
            return
        }

        # Build the update body with only specified parameters
        $body = @{}

        if ($PSBoundParameters.ContainsKey('NewName')) {
            $body['name'] = $NewName
        }

        if ($PSBoundParameters.ContainsKey('Description')) {
            $body['description'] = $Description
        }

        if ($PSBoundParameters.ContainsKey('Direction')) {
            $body['direction'] = $directionMap[$Direction]
        }

        if ($PSBoundParameters.ContainsKey('Action')) {
            $body['action'] = $actionMap[$Action]
        }

        if ($PSBoundParameters.ContainsKey('Protocol')) {
            $body['protocol'] = $protocolMap[$Protocol]
        }

        if ($PSBoundParameters.ContainsKey('SourceIP')) {
            $body['source_ip'] = $SourceIP
        }

        if ($PSBoundParameters.ContainsKey('SourcePorts')) {
            $body['source_ports'] = $SourcePorts
        }

        if ($PSBoundParameters.ContainsKey('DestinationIP')) {
            $body['destination_ip'] = $DestinationIP
        }

        if ($PSBoundParameters.ContainsKey('DestinationPorts')) {
            $body['destination_ports'] = $DestinationPorts
        }

        if ($PSBoundParameters.ContainsKey('TargetIP')) {
            $body['target_ip'] = $TargetIP
        }

        if ($PSBoundParameters.ContainsKey('TargetPorts')) {
            $body['target_ports'] = $TargetPorts
        }

        if ($PSBoundParameters.ContainsKey('Interface')) {
            $body['interface'] = $interfaceMap[$Interface]
        }

        if ($PSBoundParameters.ContainsKey('Enabled')) {
            $body['enabled'] = $Enabled
        }

        if ($PSBoundParameters.ContainsKey('Log')) {
            $body['log'] = $Log
        }

        if ($PSBoundParameters.ContainsKey('Statistics')) {
            $body['statistics'] = $Statistics
        }

        # Validate we have something to update
        if ($body.Count -eq 0) {
            Write-Warning "No properties specified to update for rule '$($targetRule.Name)'."
            return
        }

        # Build description of changes for WhatIf
        $changesDescription = ($body.Keys | ForEach-Object { "$_ = $($body[$_])" }) -join ', '

        if ($PSCmdlet.ShouldProcess($targetRule.Name, "Set Rule ($changesDescription)")) {
            try {
                Write-Verbose "Updating rule '$($targetRule.Name)' (Key: $($targetRule.Key))"
                $response = Invoke-VergeAPI -Method PUT -Endpoint "vnet_rules/$($targetRule.Key)" -Body $body -Connection $Server

                Write-Verbose "Rule '$($targetRule.Name)' updated successfully"

                # Apply rules if requested
                if ($Apply) {
                    Write-Verbose "Applying rules on network '$($targetRule.NetworkName)'"
                    Invoke-VergeNetworkApply -Network $targetRule.NetworkKey -Server $Server
                }

                if ($PassThru) {
                    # Return refreshed rule object
                    Start-Sleep -Milliseconds 500
                    Get-VergeNetworkRule -Network $targetRule.NetworkKey -Key $targetRule.Key -Server $Server
                }
            }
            catch {
                Write-Error -Message "Failed to update rule '$($targetRule.Name)': $($_.Exception.Message)" -ErrorId 'RuleUpdateFailed'
            }
        }
    }
}
