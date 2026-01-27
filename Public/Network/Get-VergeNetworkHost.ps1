function Get-VergeNetworkHost {
    <#
    .SYNOPSIS
        Retrieves DNS/DHCP host overrides from a VergeOS virtual network.

    .DESCRIPTION
        Get-VergeNetworkHost queries host overrides (DNS/DHCP reservations) for a network.
        These are used to map hostnames to IP addresses for DHCP and DNS resolution.

    .PARAMETER Network
        The name or key of the network to query hosts from.

    .PARAMETER NetworkObject
        A network object from Get-VergeNetwork. Accepts pipeline input.

    .PARAMETER Hostname
        Filter by hostname. Supports wildcards (* and ?).

    .PARAMETER IP
        Filter by IP address.

    .PARAMETER Key
        Get a specific host override by its unique key.

    .PARAMETER Type
        Filter by type: Host or Domain.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeNetworkHost -Network "Internal"

        Lists all host overrides on the Internal network.

    .EXAMPLE
        Get-VergeNetworkHost -Network "Internal" -Hostname "server*"

        Gets all hosts starting with "server".

    .EXAMPLE
        Get-VergeNetwork -Name "Internal" | Get-VergeNetworkHost

        Gets host overrides using pipeline input.

    .OUTPUTS
        Verge.NetworkHost

    .NOTES
        Host overrides provide static DNS entries and DHCP hostname assignment.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByNetworkName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByNetworkName')]
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByHostname')]
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByKey')]
        [string]$Network,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByNetworkObject')]
        [PSTypeName('Verge.Network')]
        [PSCustomObject]$NetworkObject,

        [Parameter(Position = 1, ParameterSetName = 'ByNetworkName')]
        [Parameter(Position = 1, ParameterSetName = 'ByNetworkObject')]
        [Parameter(Mandatory, ParameterSetName = 'ByHostname')]
        [SupportsWildcards()]
        [string]$Hostname,

        [Parameter()]
        [string]$IP,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter()]
        [ValidateSet('Host', 'Domain')]
        [string]$Type,

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

        # Map friendly type names to API values
        $typeMap = @{
            'Host'   = 'host'
            'Domain' = 'domain'
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

        Write-Verbose "Querying host overrides for network '$($targetNetwork.Name)'"

        # Build filter
        $filterParts = @("vnet eq $($targetNetwork.Key)")

        if ($PSBoundParameters.ContainsKey('Key')) {
            $filterParts += "`$key eq $Key"
        }

        if ($Hostname -and -not [WildcardPattern]::ContainsWildcardCharacters($Hostname)) {
            $filterParts += "host eq '$Hostname'"
        }

        if ($IP) {
            $filterParts += "ip eq '$IP'"
        }

        if ($Type) {
            $filterParts += "type eq '$($typeMap[$Type])'"
        }

        $filter = $filterParts -join ' and '

        # Build query
        $query = @{
            filter = $filter
            fields = '$key,vnet,vnet#name as vnet_name,type,host,ip'
            sort   = 'host'
        }

        try {
            $response = Invoke-VergeAPI -Method GET -Endpoint 'vnet_hosts' -Query $query -Connection $Server

            # Handle response - API returns array or single object directly
            $hosts = if ($null -eq $response) {
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

            # Apply wildcard filtering for Hostname if needed
            if ($Hostname -and [WildcardPattern]::ContainsWildcardCharacters($Hostname)) {
                $hosts = $hosts | Where-Object { $_.host -like $Hostname }
            }

            foreach ($hostEntry in $hosts) {
                # Create typed output object
                $output = [PSCustomObject]@{
                    PSTypeName  = 'Verge.NetworkHost'
                    Key         = $hostEntry.'$key'
                    NetworkKey  = $hostEntry.vnet
                    NetworkName = $hostEntry.vnet_name
                    Type        = switch ($hostEntry.type) {
                        'host'   { 'Host' }
                        'domain' { 'Domain' }
                        default  { $hostEntry.type }
                    }
                    Hostname    = $hostEntry.host
                    IP          = $hostEntry.ip
                }

                Write-Output $output
            }
        }
        catch {
            Write-Error -Message "Failed to query host overrides: $($_.Exception.Message)" -ErrorId 'HostQueryFailed'
        }
    }
}
