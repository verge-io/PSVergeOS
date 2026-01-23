function Get-VergeTenantExternalIP {
    <#
    .SYNOPSIS
        Retrieves external IP addresses assigned to a VergeOS tenant.

    .DESCRIPTION
        Get-VergeTenantExternalIP retrieves the external (virtual) IP addresses
        that have been assigned to a tenant. These IPs allow tenants to have
        public or routable addresses from the parent network.

    .PARAMETER Tenant
        A tenant object from Get-VergeTenant. Accepts pipeline input.

    .PARAMETER TenantName
        The name of the tenant to get external IPs for.

    .PARAMETER TenantKey
        The unique key (ID) of the tenant to get external IPs for.

    .PARAMETER IPAddress
        Filter by specific IP address.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeTenantExternalIP -TenantName "Customer01"

        Gets all external IPs assigned to the tenant.

    .EXAMPLE
        Get-VergeTenant -Name "Customer01" | Get-VergeTenantExternalIP

        Gets external IPs using pipeline input.

    .EXAMPLE
        Get-VergeTenantExternalIP -TenantName "Customer01" -IPAddress "10.0.0.100"

        Gets a specific external IP assignment.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.TenantExternalIP'

    .NOTES
        External IPs are Virtual IP type addresses from the parent network
        that are assigned to tenants for external connectivity.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByTenantName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByTenant')]
        [PSTypeName('Verge.Tenant')]
        [PSCustomObject]$Tenant,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByTenantName')]
        [string]$TenantName,

        [Parameter(Mandatory, ParameterSetName = 'ByTenantKey')]
        [int]$TenantKey,

        [Parameter()]
        [string]$IPAddress,

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
        # Resolve tenant based on parameter set
        $targetTenant = switch ($PSCmdlet.ParameterSetName) {
            'ByTenantName' {
                Get-VergeTenant -Name $TenantName -Server $Server
            }
            'ByTenantKey' {
                Get-VergeTenant -Key $TenantKey -Server $Server
            }
            'ByTenant' {
                $Tenant
            }
        }

        foreach ($t in $targetTenant) {
            if (-not $t) {
                continue
            }

            # Build query parameters
            $queryParams = @{}

            # Filter by owner (tenant)
            $ownerFilter = "owner eq 'tenants/$($t.Key)'"

            # Add IP filter if specified
            if ($IPAddress) {
                $queryParams['filter'] = "$ownerFilter and ip eq '$IPAddress'"
            }
            else {
                $queryParams['filter'] = $ownerFilter
            }

            # Request fields
            $queryParams['fields'] = @(
                '$key'
                'vnet'
                'vnet#name as network_name'
                'ip'
                'type'
                'hostname'
                'mac'
                'description'
                'owner'
            ) -join ','

            try {
                Write-Verbose "Querying external IPs for tenant '$($t.Name)' from $($Server.Server)"
                $response = Invoke-VergeAPI -Method GET -Endpoint 'vnet_addresses' -Query $queryParams -Connection $Server

                # Handle both single object and array responses
                $addresses = if ($response -is [array]) { $response } else { @($response) }

                foreach ($addr in $addresses) {
                    # Skip null entries
                    if (-not $addr -or -not $addr.ip) {
                        continue
                    }

                    # Create output object
                    $output = [PSCustomObject]@{
                        PSTypeName   = 'Verge.TenantExternalIP'
                        Key          = [int]$addr.'$key'
                        TenantKey    = $t.Key
                        TenantName   = $t.Name
                        NetworkKey   = [int]$addr.vnet
                        NetworkName  = $addr.network_name
                        IPAddress    = $addr.ip
                        Type         = $addr.type
                        Hostname     = $addr.hostname
                        MAC          = $addr.mac
                        Description  = $addr.description
                    }

                    # Add hidden properties for pipeline support
                    $output | Add-Member -MemberType NoteProperty -Name '_Connection' -Value $Server -Force

                    Write-Output $output
                }
            }
            catch {
                Write-Error -Message "Failed to get external IPs for tenant '$($t.Name)': $($_.Exception.Message)" -ErrorId 'TenantExternalIPQueryFailed'
            }
        }
    }
}
