function Set-VergeNetwork {
    <#
    .SYNOPSIS
        Modifies the configuration of a VergeOS virtual network.

    .DESCRIPTION
        Set-VergeNetwork modifies settings on an existing virtual network.
        You can change DHCP settings, DNS configuration, description, and other properties.
        Note: Network type cannot be changed after creation.

    .PARAMETER Name
        The name of the network to modify.

    .PARAMETER Key
        The unique key (ID) of the network to modify.

    .PARAMETER Network
        A network object from Get-VergeNetwork. Accepts pipeline input.

    .PARAMETER NewName
        A new name for the network.

    .PARAMETER Description
        An updated description for the network.

    .PARAMETER NetworkAddress
        The network address in CIDR notation (e.g., "10.0.0.0/24").

    .PARAMETER IPAddress
        The IP address for the network router.

    .PARAMETER Gateway
        The default gateway IP address (sent as DHCP option to clients).

    .PARAMETER DHCPEnabled
        Enable or disable DHCP server on this network.

    .PARAMETER DHCPStart
        The starting IP address for DHCP range.

    .PARAMETER DHCPStop
        The ending IP address for DHCP range.

    .PARAMETER DHCPDynamic
        Enable or disable dynamic DHCP.

    .PARAMETER DNS
        DNS server mode. Valid values: Disabled, Simple, Bind, Network.

    .PARAMETER DNSServers
        List of DNS server IP addresses to provide via DHCP.

    .PARAMETER Domain
        The domain name for this network.

    .PARAMETER MTU
        The MTU size (1000-65536).

    .PARAMETER OnPowerLoss
        Behavior when power is restored. Valid values: PowerOn, LastState, LeaveOff.

    .PARAMETER RateLimit
        The rate limit value. Use with -RateLimitType to specify units.
        Set to 0 to disable rate limiting.

    .PARAMETER RateLimitType
        The rate limit unit type. Valid values include:
        BytesPerSecond, KBytesPerSecond, MBytesPerSecond,
        BytesPerMinute, KBytesPerMinute, MBytesPerMinute,
        BytesPerHour, KBytesPerHour, MBytesPerHour,
        BytesPerDay, KBytesPerDay, MBytesPerDay,
        PacketsPerSecond, PacketsPerMinute, PacketsPerHour, PacketsPerDay.

    .PARAMETER RateLimitBurst
        The burst limit value for rate limiting.

    .PARAMETER Enabled
        Enable or disable the network.

    .PARAMETER PassThru
        Return the modified network object. By default, no output is returned.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Set-VergeNetwork -Name "Dev-Network" -Description "Development environment network"

        Updates the description of a network.

    .EXAMPLE
        Set-VergeNetwork -Name "Dev-Network" -DHCPEnabled $true -DHCPStart "10.0.0.100" -DHCPStop "10.0.0.200"

        Enables DHCP on a network with a specified range.

    .EXAMPLE
        Get-VergeNetwork -Name "Dev-Network" | Set-VergeNetwork -NewName "Development-Network" -PassThru

        Renames a network using pipeline input.

    .EXAMPLE
        Set-VergeNetwork -Name "Guest-Network" -RateLimit 100 -RateLimitType MBytesPerSecond -RateLimitBurst 150

        Sets a 100 MB/s rate limit with 150 MB burst on the Guest network.

    .OUTPUTS
        None by default. Verge.Network when -PassThru is specified.

    .NOTES
        Network type cannot be changed after creation.
        Some changes may require a network restart to take effect.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByNetwork')]
        [PSTypeName('Verge.Network')]
        [PSCustomObject]$Network,

        [Parameter()]
        [ValidateLength(1, 128)]
        [string]$NewName,

        [Parameter()]
        [ValidateLength(0, 2048)]
        [string]$Description,

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
        [bool]$DHCPEnabled,

        [Parameter()]
        [ValidatePattern('^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$')]
        [string]$DHCPStart,

        [Parameter()]
        [ValidatePattern('^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$')]
        [string]$DHCPStop,

        [Parameter()]
        [bool]$DHCPDynamic,

        [Parameter()]
        [ValidateSet('Disabled', 'Simple', 'Bind', 'Network')]
        [string]$DNS,

        [Parameter()]
        [string[]]$DNSServers,

        [Parameter()]
        [string]$Domain,

        [Parameter()]
        [ValidateRange(1000, 65536)]
        [int]$MTU,

        [Parameter()]
        [ValidateSet('PowerOn', 'LastState', 'LeaveOff')]
        [string]$OnPowerLoss,

        [Parameter()]
        [ValidateRange(0, [UInt64]::MaxValue)]
        [UInt64]$RateLimit,

        [Parameter()]
        [ValidateSet(
            'BytesPerSecond', 'KBytesPerSecond', 'MBytesPerSecond',
            'BytesPerMinute', 'KBytesPerMinute', 'MBytesPerMinute',
            'BytesPerHour', 'KBytesPerHour', 'MBytesPerHour',
            'BytesPerDay', 'KBytesPerDay', 'MBytesPerDay',
            'PacketsPerSecond', 'PacketsPerMinute', 'PacketsPerHour', 'PacketsPerDay'
        )]
        [string]$RateLimitType,

        [Parameter()]
        [ValidateRange(0, [UInt64]::MaxValue)]
        [UInt64]$RateLimitBurst,

        [Parameter()]
        [bool]$Enabled,

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
        $dnsMap = @{
            'Disabled' = 'disabled'
            'Simple'   = 'simple'
            'Bind'     = 'bind'
            'Network'  = 'network'
        }

        $powerLossMap = @{
            'PowerOn'   = 'power_on'
            'LastState' = 'last_state'
            'LeaveOff'  = 'leave_off'
        }

        $rateLimitTypeMap = @{
            'BytesPerSecond'    = 'bytes/second'
            'KBytesPerSecond'   = 'kbytes/second'
            'MBytesPerSecond'   = 'mbytes/second'
            'BytesPerMinute'    = 'bytes/minute'
            'KBytesPerMinute'   = 'kbytes/minute'
            'MBytesPerMinute'   = 'mbytes/minute'
            'BytesPerHour'      = 'bytes/hour'
            'KBytesPerHour'     = 'kbytes/hour'
            'MBytesPerHour'     = 'mbytes/hour'
            'BytesPerDay'       = 'bytes/day'
            'KBytesPerDay'      = 'kbytes/day'
            'MBytesPerDay'      = 'mbytes/day'
            'PacketsPerSecond'  = 'second'
            'PacketsPerMinute'  = 'minute'
            'PacketsPerHour'    = 'hour'
            'PacketsPerDay'     = 'day'
        }
    }

    process {
        # Get the network to modify based on parameter set
        $targetNetwork = switch ($PSCmdlet.ParameterSetName) {
            'ByName' {
                Get-VergeNetwork -Name $Name -Server $Server
            }
            'ByKey' {
                Get-VergeNetwork -Key $Key -Server $Server
            }
            'ByNetwork' {
                $Network
            }
        }

        if (-not $targetNetwork) {
            Write-Error -Message "Network not found" -ErrorId 'NetworkNotFound'
            return
        }

        # Handle multiple matches from wildcard
        if ($targetNetwork -is [array]) {
            Write-Error -Message "Multiple networks matched. Please specify a unique name or use -Key." -ErrorId 'MultipleNetworksMatched'
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

        if ($PSBoundParameters.ContainsKey('NetworkAddress')) {
            $body['network'] = $NetworkAddress
        }

        if ($PSBoundParameters.ContainsKey('IPAddress')) {
            $body['ipaddress'] = $IPAddress
        }

        if ($PSBoundParameters.ContainsKey('Gateway')) {
            $body['gateway'] = $Gateway
        }

        if ($PSBoundParameters.ContainsKey('DHCPEnabled')) {
            $body['dhcp_enabled'] = $DHCPEnabled
        }

        if ($PSBoundParameters.ContainsKey('DHCPStart')) {
            $body['dhcp_start'] = $DHCPStart
        }

        if ($PSBoundParameters.ContainsKey('DHCPStop')) {
            $body['dhcp_stop'] = $DHCPStop
        }

        if ($PSBoundParameters.ContainsKey('DHCPDynamic')) {
            $body['dhcp_dynamic'] = $DHCPDynamic
        }

        if ($PSBoundParameters.ContainsKey('DNS')) {
            $body['dns'] = $dnsMap[$DNS]
        }

        if ($PSBoundParameters.ContainsKey('DNSServers')) {
            $body['dnslist'] = $DNSServers -join ','
        }

        if ($PSBoundParameters.ContainsKey('Domain')) {
            $body['domain'] = $Domain
        }

        if ($PSBoundParameters.ContainsKey('MTU')) {
            $body['mtu'] = $MTU
        }

        if ($PSBoundParameters.ContainsKey('OnPowerLoss')) {
            $body['on_power_loss'] = $powerLossMap[$OnPowerLoss]
        }

        if ($PSBoundParameters.ContainsKey('RateLimit')) {
            $body['rate_limit'] = $RateLimit
        }

        if ($PSBoundParameters.ContainsKey('RateLimitType')) {
            $body['rate_limit_type'] = $rateLimitTypeMap[$RateLimitType]
        }

        if ($PSBoundParameters.ContainsKey('RateLimitBurst')) {
            $body['rate_limit_burst'] = $RateLimitBurst
        }

        if ($PSBoundParameters.ContainsKey('Enabled')) {
            $body['enabled'] = $Enabled
        }

        # Validate we have something to update
        if ($body.Count -eq 0) {
            Write-Warning "No properties specified to update for network '$($targetNetwork.Name)'."
            return
        }

        # Build description of changes for WhatIf
        $changesDescription = ($body.Keys | ForEach-Object { "$_ = $($body[$_])" }) -join ', '

        if ($PSCmdlet.ShouldProcess($targetNetwork.Name, "Set Network ($changesDescription)")) {
            try {
                Write-Verbose "Updating network '$($targetNetwork.Name)' (Key: $($targetNetwork.Key))"
                $response = Invoke-VergeAPI -Method PUT -Endpoint "vnets/$($targetNetwork.Key)" -Body $body -Connection $Server

                Write-Verbose "Network '$($targetNetwork.Name)' updated successfully"

                if ($PassThru) {
                    # Return refreshed network object
                    Start-Sleep -Milliseconds 500
                    Get-VergeNetwork -Key $targetNetwork.Key -Server $Server
                }
            }
            catch {
                Write-Error -Message "Failed to update network '$($targetNetwork.Name)': $($_.Exception.Message)" -ErrorId 'NetworkUpdateFailed'
            }
        }
    }
}
