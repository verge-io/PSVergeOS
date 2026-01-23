function Get-VergeTenantSnapshot {
    <#
    .SYNOPSIS
        Retrieves snapshots for a VergeOS tenant.

    .DESCRIPTION
        Get-VergeTenantSnapshot retrieves snapshot information for one or more tenants.
        Snapshots are point-in-time copies of the tenant that can be used for
        backup/recovery or creating new tenant clones.

    .PARAMETER Tenant
        A tenant object from Get-VergeTenant. Accepts pipeline input.

    .PARAMETER TenantName
        The name of the tenant to get snapshots for.

    .PARAMETER TenantKey
        The unique key (ID) of the tenant to get snapshots for.

    .PARAMETER Name
        Filter snapshots by name. Supports wildcards (* and ?).

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeTenantSnapshot -TenantName "Customer01"

        Gets all snapshots for the tenant named "Customer01".

    .EXAMPLE
        Get-VergeTenant -Name "Customer01" | Get-VergeTenantSnapshot

        Gets snapshots for the tenant using pipeline input.

    .EXAMPLE
        Get-VergeTenant | Get-VergeTenantSnapshot

        Gets snapshots for all tenants.

    .EXAMPLE
        Get-VergeTenantSnapshot -TenantName "Customer01" -Name "Daily*"

        Gets snapshots with names starting with "Daily" for the tenant.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.TenantSnapshot'

    .NOTES
        Tenant snapshots are created automatically by snapshot profiles or manually.
        Snapshots can be used to restore a tenant or create a clone.
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
        [SupportsWildcards()]
        [string]$Name,

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
            $queryParams['fields'] = @(
                '$key'
                'tenant'
                'name'
                'description'
                'profile'
                'period'
                'min_snapshots'
                'created'
                'expires'
            ) -join ','

            try {
                Write-Verbose "Querying tenant snapshots for '$($t.Name)' from $($Server.Server)"
                $response = Invoke-VergeAPI -Method GET -Endpoint 'tenant_snapshots' -Query $queryParams -Connection $Server

                # Handle both single object and array responses
                $snapshots = if ($response -is [array]) { $response } else { @($response) }

                # Filter by name if specified
                if ($Name) {
                    if ($Name -match '[\*\?]') {
                        # Wildcard - use -like
                        $snapshots = $snapshots | Where-Object { $_.name -like $Name }
                    }
                    else {
                        # Exact match
                        $snapshots = $snapshots | Where-Object { $_.name -eq $Name }
                    }
                }

                foreach ($snapshot in $snapshots) {
                    # Skip null entries
                    if (-not $snapshot -or -not $snapshot.name) {
                        continue
                    }

                    # Create output object
                    $output = [PSCustomObject]@{
                        PSTypeName    = 'Verge.TenantSnapshot'
                        Key           = [int]$snapshot.'$key'
                        TenantKey     = [int]$snapshot.tenant
                        TenantName    = $t.Name
                        Name          = $snapshot.name
                        Description   = $snapshot.description
                        Profile       = $snapshot.profile
                        Period        = $snapshot.period
                        MinSnapshots  = [int]$snapshot.min_snapshots
                        Created       = if ($snapshot.created) { [DateTimeOffset]::FromUnixTimeSeconds($snapshot.created).LocalDateTime } else { $null }
                        Expires       = if ($snapshot.expires -and $snapshot.expires -gt 0) { [DateTimeOffset]::FromUnixTimeSeconds($snapshot.expires).LocalDateTime } else { $null }
                        ExpiresTimestamp = [int]$snapshot.expires
                    }

                    # Add hidden properties for pipeline support
                    $output | Add-Member -MemberType NoteProperty -Name '_Connection' -Value $Server -Force

                    Write-Output $output
                }
            }
            catch {
                Write-Error -Message "Failed to get snapshots for tenant '$($t.Name)': $($_.Exception.Message)" -ErrorId 'TenantSnapshotQueryFailed'
            }
        }
    }
}
