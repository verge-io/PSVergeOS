function Get-VergeTenantNetworkBlock {
    <#
    .SYNOPSIS
        Retrieves network blocks (CIDR ranges) assigned to a VergeOS tenant.

    .DESCRIPTION
        Get-VergeTenantNetworkBlock retrieves the network blocks (CIDR ranges)
        that have been assigned to a tenant. These blocks allow tenants to have
        entire subnets routed to them from the parent network.

    .PARAMETER Tenant
        A tenant object from Get-VergeTenant. Accepts pipeline input.

    .PARAMETER TenantName
        The name of the tenant to get network blocks for.

    .PARAMETER TenantKey
        The unique key (ID) of the tenant to get network blocks for.

    .PARAMETER CIDR
        Filter by specific CIDR block (e.g., "192.168.1.0/24").

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeTenantNetworkBlock -TenantName "Customer01"

        Gets all network blocks assigned to the tenant.

    .EXAMPLE
        Get-VergeTenant -Name "Customer01" | Get-VergeTenantNetworkBlock

        Gets network blocks using pipeline input.

    .EXAMPLE
        Get-VergeTenantNetworkBlock -TenantName "Customer01" -CIDR "192.168.100.0/24"

        Gets a specific network block assignment.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.TenantNetworkBlock'

    .NOTES
        Network blocks are CIDR ranges from the parent network that are
        routed to tenants for their internal use.
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
        [string]$CIDR,

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

            # Add CIDR filter if specified
            if ($CIDR) {
                $queryParams['filter'] = "$ownerFilter and cidr eq '$CIDR'"
            }
            else {
                $queryParams['filter'] = $ownerFilter
            }

            # Request fields
            $queryParams['fields'] = @(
                '$key'
                'vnet'
                'vnet#name as network_name'
                'cidr'
                'description'
                'owner'
            ) -join ','

            try {
                Write-Verbose "Querying network blocks for tenant '$($t.Name)' from $($Server.Server)"
                $response = Invoke-VergeAPI -Method GET -Endpoint 'vnet_cidrs' -Query $queryParams -Connection $Server

                # Handle both single object and array responses
                $blocks = if ($response -is [array]) { $response } else { @($response) }

                foreach ($block in $blocks) {
                    # Skip null entries
                    if (-not $block -or -not $block.cidr) {
                        continue
                    }

                    # Parse CIDR to get network and prefix
                    $cidrParts = $block.cidr -split '/'
                    $networkAddress = $cidrParts[0]
                    $prefixLength = [int]$cidrParts[1]

                    # Calculate number of addresses
                    $addressCount = [math]::Pow(2, 32 - $prefixLength)

                    # Create output object
                    $output = [PSCustomObject]@{
                        PSTypeName     = 'Verge.TenantNetworkBlock'
                        Key            = [int]$block.'$key'
                        TenantKey      = $t.Key
                        TenantName     = $t.Name
                        NetworkKey     = [int]$block.vnet
                        NetworkName    = $block.network_name
                        CIDR           = $block.cidr
                        NetworkAddress = $networkAddress
                        PrefixLength   = $prefixLength
                        AddressCount   = [int]$addressCount
                        Description    = $block.description
                    }

                    # Add hidden properties for pipeline support
                    $output | Add-Member -MemberType NoteProperty -Name '_Connection' -Value $Server -Force

                    Write-Output $output
                }
            }
            catch {
                Write-Error -Message "Failed to get network blocks for tenant '$($t.Name)': $($_.Exception.Message)" -ErrorId 'TenantNetworkBlockQueryFailed'
            }
        }
    }
}
