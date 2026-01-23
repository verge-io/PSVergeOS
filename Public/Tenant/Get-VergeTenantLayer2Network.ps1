function Get-VergeTenantLayer2Network {
    <#
    .SYNOPSIS
        Retrieves Layer 2 network assignments for a VergeOS tenant.

    .DESCRIPTION
        Get-VergeTenantLayer2Network retrieves the Layer 2 networks that have been
        assigned to a tenant. Layer 2 networks allow tenants direct access to
        parent network segments for bridged connectivity.

    .PARAMETER Tenant
        A tenant object from Get-VergeTenant. Accepts pipeline input.

    .PARAMETER TenantName
        The name of the tenant to get Layer 2 networks for.

    .PARAMETER TenantKey
        The unique key (ID) of the tenant to get Layer 2 networks for.

    .PARAMETER Key
        The unique key of a specific Layer 2 network assignment.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeTenantLayer2Network -TenantName "Customer01"

        Gets all Layer 2 network assignments for the tenant.

    .EXAMPLE
        Get-VergeTenant -Name "Customer01" | Get-VergeTenantLayer2Network

        Gets Layer 2 networks using pipeline input.

    .EXAMPLE
        Get-VergeTenantLayer2Network -Key 42

        Gets a specific Layer 2 network assignment by key.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.TenantLayer2Network'

    .NOTES
        Layer 2 networks provide bridged connectivity between parent and tenant
        networks. Only certain network types can be assigned as Layer 2 networks.
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
        # Handle direct key lookup
        if ($PSCmdlet.ParameterSetName -eq 'ByKey') {
            $queryParams = @{
                filter = "`$key eq $Key"
                fields = '$key,tenant,tenant#name as tenant_name,vnet,vnet#name as vnet_name,vnet#type as vnet_type,enabled'
            }

            try {
                $response = Invoke-VergeAPI -Method GET -Endpoint 'tenant_layer2_vnets' -Query $queryParams -Connection $Server

                if ($response) {
                    $output = [PSCustomObject]@{
                        PSTypeName   = 'Verge.TenantLayer2Network'
                        Key          = [int]$response.'$key'
                        TenantKey    = [int]$response.tenant
                        TenantName   = $response.tenant_name
                        NetworkKey   = [int]$response.vnet
                        NetworkName  = $response.vnet_name
                        NetworkType  = $response.vnet_type
                        Enabled      = [bool]$response.enabled
                    }
                    $output | Add-Member -MemberType NoteProperty -Name '_Connection' -Value $Server -Force
                    Write-Output $output
                }
                else {
                    Write-Error -Message "Layer 2 network assignment with key $Key not found." -ErrorId 'Layer2NetworkNotFound'
                }
            }
            catch {
                Write-Error -Message "Failed to get Layer 2 network assignment: $($_.Exception.Message)" -ErrorId 'Layer2NetworkQueryFailed'
            }
            return
        }

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
            $queryParams = @{
                filter = "tenant eq $($t.Key)"
                fields = '$key,tenant,vnet,vnet#name as vnet_name,vnet#type as vnet_type,enabled'
            }

            try {
                Write-Verbose "Querying Layer 2 networks for tenant '$($t.Name)' from $($Server.Server)"
                $response = Invoke-VergeAPI -Method GET -Endpoint 'tenant_layer2_vnets' -Query $queryParams -Connection $Server

                # Handle both single object and array responses
                $networks = if ($response -is [array]) { $response } else { @($response) }

                foreach ($net in $networks) {
                    # Skip null entries
                    if (-not $net -or -not $net.'$key') {
                        continue
                    }

                    # Create output object
                    $output = [PSCustomObject]@{
                        PSTypeName   = 'Verge.TenantLayer2Network'
                        Key          = [int]$net.'$key'
                        TenantKey    = $t.Key
                        TenantName   = $t.Name
                        NetworkKey   = [int]$net.vnet
                        NetworkName  = $net.vnet_name
                        NetworkType  = $net.vnet_type
                        Enabled      = [bool]$net.enabled
                    }

                    # Add hidden properties for pipeline support
                    $output | Add-Member -MemberType NoteProperty -Name '_Connection' -Value $Server -Force

                    Write-Output $output
                }
            }
            catch {
                Write-Error -Message "Failed to get Layer 2 networks for tenant '$($t.Name)': $($_.Exception.Message)" -ErrorId 'Layer2NetworkQueryFailed'
            }
        }
    }
}
