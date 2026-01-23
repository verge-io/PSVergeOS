function Get-VergeNetworkAlias {
    <#
    .SYNOPSIS
        Retrieves IP aliases from a VergeOS virtual network.

    .DESCRIPTION
        Get-VergeNetworkAlias queries IP aliases (address groups) for a network.
        IP aliases are used in firewall rules to reference groups of IP addresses.

    .PARAMETER Network
        The name or key of the network to query aliases from.

    .PARAMETER NetworkObject
        A network object from Get-VergeNetwork. Accepts pipeline input.

    .PARAMETER IP
        Filter by IP address.

    .PARAMETER Hostname
        Filter by hostname/description. Supports wildcards (* and ?).

    .PARAMETER Key
        Get a specific alias by its unique key.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeNetworkAlias -Network "External"

        Lists all IP aliases on the External network.

    .EXAMPLE
        Get-VergeNetworkAlias -Network "External" -IP "10.0.0.*"

        Gets all aliases in the 10.0.0.x range.

    .EXAMPLE
        Get-VergeNetwork -Name "External" | Get-VergeNetworkAlias

        Gets aliases using pipeline input.

    .OUTPUTS
        Verge.NetworkAlias

    .NOTES
        IP aliases can be referenced in firewall rules using alias:name syntax.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByNetworkName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByNetworkName')]
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByKey')]
        [string]$Network,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByNetworkObject')]
        [PSTypeName('Verge.Network')]
        [PSCustomObject]$NetworkObject,

        [Parameter()]
        [SupportsWildcards()]
        [string]$IP,

        [Parameter()]
        [SupportsWildcards()]
        [string]$Hostname,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
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
            Write-Error -Message "Network '$Network' not found" -ErrorId 'NetworkNotFound'
            return
        }

        Write-Verbose "Querying IP aliases for network '$($targetNetwork.Name)'"

        # Build filter - only get IP aliases (type = ipalias)
        $filterParts = @("vnet eq $($targetNetwork.Key)", "type eq 'ipalias'")

        if ($PSBoundParameters.ContainsKey('Key')) {
            $filterParts += "`$key eq $Key"
        }

        if ($IP -and -not [WildcardPattern]::ContainsWildcardCharacters($IP)) {
            $filterParts += "ip eq '$IP'"
        }

        if ($Hostname -and -not [WildcardPattern]::ContainsWildcardCharacters($Hostname)) {
            $filterParts += "hostname eq '$Hostname'"
        }

        $filter = $filterParts -join ' and '

        # Build query
        $query = @{
            filter = $filter
            fields = '$key,vnet,vnet#name as vnet_name,ip,hostname,description,mac'
            sort   = 'ip'
        }

        try {
            $response = Invoke-VergeAPI -Method GET -Endpoint 'vnet_addresses' -Query $query -Connection $Server

            # Handle response - API returns array or single object directly
            $aliases = if ($null -eq $response) {
                @()
            }
            elseif ($response -is [array]) {
                $response
            }
            elseif ($response.'$key') {
                # Single object returned
                @($response)
            }
            else {
                @()
            }

            # Apply wildcard filtering if needed
            if ($IP -and [WildcardPattern]::ContainsWildcardCharacters($IP)) {
                $aliases = $aliases | Where-Object { $_.ip -like $IP }
            }
            if ($Hostname -and [WildcardPattern]::ContainsWildcardCharacters($Hostname)) {
                $aliases = $aliases | Where-Object { $_.hostname -like $Hostname }
            }

            foreach ($alias in $aliases) {
                # Create typed output object
                $output = [PSCustomObject]@{
                    PSTypeName  = 'Verge.NetworkAlias'
                    Key         = $alias.'$key'
                    NetworkKey  = $alias.vnet
                    NetworkName = $alias.vnet_name
                    IP          = $alias.ip
                    Name        = $alias.hostname
                    Description = $alias.description
                    MAC         = $alias.mac
                }

                Write-Output $output
            }
        }
        catch {
            Write-Error -Message "Failed to query IP aliases: $($_.Exception.Message)" -ErrorId 'AliasQueryFailed'
        }
    }
}
