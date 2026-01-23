function Get-VergeTenantStorage {
    <#
    .SYNOPSIS
        Retrieves storage tier allocations for a VergeOS tenant.

    .DESCRIPTION
        Get-VergeTenantStorage retrieves the storage tier allocations for one or more tenants.
        Each tenant can have storage allocated from different storage tiers, and this cmdlet
        shows the provisioned, used, and allocated amounts for each tier.

    .PARAMETER Tenant
        A tenant object from Get-VergeTenant. Accepts pipeline input.

    .PARAMETER TenantName
        The name of the tenant to get storage allocations for.

    .PARAMETER TenantKey
        The unique key (ID) of the tenant to get storage allocations for.

    .PARAMETER Tier
        Filter by storage tier name.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeTenantStorage -TenantName "Customer01"

        Gets storage allocations for the tenant named "Customer01".

    .EXAMPLE
        Get-VergeTenant -Name "Customer01" | Get-VergeTenantStorage

        Gets storage allocations for the tenant using pipeline input.

    .EXAMPLE
        Get-VergeTenant | Get-VergeTenantStorage

        Gets storage allocations for all tenants.

    .EXAMPLE
        Get-VergeTenantStorage -TenantName "Customer01" -Tier "Tier 1"

        Gets only Tier 1 storage allocation for the tenant.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.TenantStorage'

    .NOTES
        Storage values are returned in bytes. Use helper properties like
        ProvisionedGB, UsedGB, AllocatedGB for easier reading.
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
        [string]$Tier,

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

            # Build filter string
            $filters = [System.Collections.Generic.List[string]]::new()
            $filters.Add("tenant eq $($t.Key)")

            # Apply filters
            if ($filters.Count -gt 0) {
                $queryParams['filter'] = $filters -join ' and '
            }

            # Request fields
            # Note: storage_tiers uses 'tier' (number) as the display field, not a 'name' field
            $queryParams['fields'] = @(
                '$key'
                'tenant'
                'tier'
                'tier#tier as tier_number'
                'tier#description as tier_description'
                'provisioned'
                'used'
                'allocated'
                'used_pct'
                'last_update'
            ) -join ','

            try {
                Write-Verbose "Querying tenant storage for '$($t.Name)' from $($Server.Server)"
                $response = Invoke-VergeAPI -Method GET -Endpoint 'tenant_storage' -Query $queryParams -Connection $Server

                # Handle both single object and array responses
                $storageItems = if ($response -is [array]) { $response } else { @($response) }

                # Filter by tier if specified (can be tier number or "Tier X" format)
                if ($Tier) {
                    $storageItems = $storageItems | Where-Object {
                        $tierNum = $_.tier_number
                        $tierDisplay = "Tier $tierNum"
                        ($tierNum -eq $Tier) -or ($tierDisplay -like $Tier) -or ($Tier -match '^\d+$' -and [int]$Tier -eq $tierNum)
                    }
                }

                foreach ($storage in $storageItems) {
                    # Skip null entries
                    if (-not $storage -or -not $storage.tier) {
                        continue
                    }

                    # Convert bytes to GB for convenience properties
                    $provisionedBytes = [long]$storage.provisioned
                    $usedBytes = [long]$storage.used
                    $allocatedBytes = [long]$storage.allocated

                    # Format tier name as "Tier X"
                    $tierNumber = if ($null -ne $storage.tier_number) { [int]$storage.tier_number } else { [int]$storage.tier }
                    $tierName = "Tier $tierNumber"

                    # Create output object
                    $output = [PSCustomObject]@{
                        PSTypeName      = 'Verge.TenantStorage'
                        Key             = [int]$storage.'$key'
                        TenantKey       = [int]$storage.tenant
                        TenantName      = $t.Name
                        TierKey         = [int]$storage.tier
                        Tier            = $tierNumber
                        TierName        = $tierName
                        TierDescription = $storage.tier_description
                        Provisioned     = $provisionedBytes
                        Used            = $usedBytes
                        Allocated       = $allocatedBytes
                        UsedPercent     = [int]$storage.used_pct
                        ProvisionedGB   = [math]::Round($provisionedBytes / 1GB, 2)
                        UsedGB          = [math]::Round($usedBytes / 1GB, 2)
                        AllocatedGB     = [math]::Round($allocatedBytes / 1GB, 2)
                        LastUpdate      = if ($storage.last_update) { [DateTimeOffset]::FromUnixTimeSeconds($storage.last_update).LocalDateTime } else { $null }
                    }

                    # Add hidden properties for pipeline support
                    $output | Add-Member -MemberType NoteProperty -Name '_Connection' -Value $Server -Force

                    Write-Output $output
                }
            }
            catch {
                Write-Error -Message "Failed to get storage for tenant '$($t.Name)': $($_.Exception.Message)" -ErrorId 'TenantStorageQueryFailed'
            }
        }
    }
}
