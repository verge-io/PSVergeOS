function Get-VergeDNSZone {
    <#
    .SYNOPSIS
        Retrieves DNS zones from a VergeOS virtual network.

    .DESCRIPTION
        Get-VergeDNSZone queries DNS zones configured on a network's DNS views.
        Use -IncludeRecords to also retrieve the DNS records within each zone.

    .PARAMETER Network
        The name or key of the network to query DNS zones from.

    .PARAMETER NetworkObject
        A network object from Get-VergeNetwork. Accepts pipeline input.

    .PARAMETER Domain
        Filter by domain name. Supports wildcards (* and ?).

    .PARAMETER Key
        Get a specific zone by its unique key.

    .PARAMETER IncludeRecords
        Include DNS records in the output.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeDNSZone -Network "Internal"

        Lists all DNS zones on the Internal network.

    .EXAMPLE
        Get-VergeDNSZone -Network "Internal" -Domain "*.local"

        Gets all zones ending with .local.

    .EXAMPLE
        Get-VergeDNSZone -Network "Internal" -IncludeRecords

        Gets all zones with their DNS records.

    .OUTPUTS
        Verge.DNSZone

    .NOTES
        DNS zones are organized under DNS views. Each network can have multiple views.
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
        [string]$Domain,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter()]
        [switch]$IncludeRecords,

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

        # Type mapping
        $typeMap = @{
            'master'      = 'Primary'
            'slave'       = 'Secondary'
            'redirect'    = 'Redirect'
            'forward'     = 'Forward'
            'static-stub' = 'Static Stub'
            'stub'        = 'Stub'
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

        Write-Verbose "Querying DNS zones for network '$($targetNetwork.Name)'"

        # First get DNS views for this network
        $viewQuery = @{
            filter = "vnet eq $($targetNetwork.Key)"
            fields = '$key,name'
        }

        try {
            $viewResponse = Invoke-VergeAPI -Method GET -Endpoint 'vnet_dns_views' -Query $viewQuery -Connection $Server

            # Handle view response
            $views = if ($null -eq $viewResponse) {
                @()
            }
            elseif ($viewResponse -is [array]) {
                $viewResponse
            }
            elseif ($viewResponse.'$key') {
                @($viewResponse)
            }
            else {
                @()
            }

            if ($views.Count -eq 0) {
                Write-Verbose "No DNS views found on network '$($targetNetwork.Name)'"
                return
            }

            # Get zones for each view
            foreach ($view in $views) {
                $viewKey = $view.'$key'
                $viewName = $view.name

                # Build filter for zones
                $filterParts = @("view eq $viewKey")

                if ($PSBoundParameters.ContainsKey('Key')) {
                    $filterParts += "`$key eq $Key"
                }

                if ($Domain -and -not [WildcardPattern]::ContainsWildcardCharacters($Domain)) {
                    $filterParts += "domain eq '$Domain'"
                }

                $filter = $filterParts -join ' and '

                $zoneQuery = @{
                    filter = $filter
                    fields = '$key,view,domain,type,nameserver,email,default_ttl,serial_number'
                    sort   = 'domain'
                }

                $zoneResponse = Invoke-VergeAPI -Method GET -Endpoint 'vnet_dns_zones' -Query $zoneQuery -Connection $Server

                # Handle zone response
                $zones = if ($null -eq $zoneResponse) {
                    @()
                }
                elseif ($zoneResponse -is [array]) {
                    $zoneResponse
                }
                elseif ($zoneResponse.'$key') {
                    @($zoneResponse)
                }
                else {
                    @()
                }

                # Apply wildcard filtering if needed
                if ($Domain -and [WildcardPattern]::ContainsWildcardCharacters($Domain)) {
                    $zones = $zones | Where-Object { $_.domain -like $Domain }
                }

                foreach ($zone in $zones) {
                    # Get records if requested
                    $records = @()
                    if ($IncludeRecords) {
                        $recordQuery = @{
                            filter = "zone eq $($zone.'$key')"
                            fields = '$key,host,type,value,ttl,mx_preference'
                            sort   = 'orderid'
                        }

                        $recordResponse = Invoke-VergeAPI -Method GET -Endpoint 'vnet_dns_zone_records' -Query $recordQuery -Connection $Server

                        $records = if ($null -eq $recordResponse) {
                            @()
                        }
                        elseif ($recordResponse -is [array]) {
                            $recordResponse
                        }
                        elseif ($recordResponse.'$key') {
                            @($recordResponse)
                        }
                        else {
                            @()
                        }
                    }

                    # Create typed output object
                    $output = [PSCustomObject]@{
                        PSTypeName   = 'Verge.DNSZone'
                        Key          = $zone.'$key'
                        NetworkKey   = $targetNetwork.Key
                        NetworkName  = $targetNetwork.Name
                        ViewKey      = $viewKey
                        ViewName     = $viewName
                        Domain       = $zone.domain
                        Type         = if ($typeMap[$zone.type]) { $typeMap[$zone.type] } else { $zone.type }
                        NameServer   = $zone.nameserver
                        Email        = $zone.email
                        DefaultTTL   = $zone.default_ttl
                        SerialNumber = $zone.serial_number
                    }

                    if ($IncludeRecords) {
                        $recordObjects = foreach ($rec in $records) {
                            [PSCustomObject]@{
                                Key          = $rec.'$key'
                                Host         = $rec.host
                                Type         = $rec.type
                                Value        = $rec.value
                                TTL          = $rec.ttl
                                MXPreference = $rec.mx_preference
                            }
                        }
                        $output | Add-Member -MemberType NoteProperty -Name 'Records' -Value $recordObjects
                    }

                    Write-Output $output
                }
            }
        }
        catch {
            Write-Error -Message "Failed to query DNS zones: $($_.Exception.Message)" -ErrorId 'DNSZoneQueryFailed'
        }
    }
}
