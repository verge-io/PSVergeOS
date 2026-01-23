function Enable-VergeTenantIsolation {
    <#
    .SYNOPSIS
        Enables network isolation mode for a VergeOS tenant.

    .DESCRIPTION
        Enable-VergeTenantIsolation enables isolation mode for a tenant, which
        disables the tenant's network connectivity. This is useful for security
        purposes or when performing maintenance that requires network isolation.

    .PARAMETER Tenant
        A tenant object from Get-VergeTenant. Accepts pipeline input.

    .PARAMETER TenantName
        The name of the tenant to isolate.

    .PARAMETER TenantKey
        The unique key (ID) of the tenant to isolate.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Enable-VergeTenantIsolation -TenantName "Customer01"

        Enables network isolation for the tenant.

    .EXAMPLE
        Get-VergeTenant -Name "Customer01" | Enable-VergeTenantIsolation

        Enables isolation using pipeline input.

    .EXAMPLE
        Get-VergeTenant -Name "Suspicious*" | Enable-VergeTenantIsolation

        Enables isolation for all tenants with names starting with "Suspicious".

    .OUTPUTS
        None.

    .NOTES
        Enabling isolation disables the tenant's network. The tenant will not
        be able to communicate with external networks until isolation is disabled.
        Use Disable-VergeTenantIsolation to restore network connectivity.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByTenantName')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByTenant')]
        [PSTypeName('Verge.Tenant')]
        [PSCustomObject]$Tenant,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByTenantName')]
        [string]$TenantName,

        [Parameter(Mandatory, ParameterSetName = 'ByTenantKey')]
        [int]$TenantKey,

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

            # Check if tenant is a snapshot
            if ($t.IsSnapshot) {
                Write-Error -Message "Cannot enable isolation for tenant '$($t.Name)': Tenant is a snapshot." -ErrorId 'CannotModifySnapshot'
                continue
            }

            # Check if already isolated
            if ($t.Isolated) {
                Write-Warning "Tenant '$($t.Name)' is already in isolation mode."
                continue
            }

            # Confirm action
            if ($PSCmdlet.ShouldProcess($t.Name, "Enable network isolation")) {
                try {
                    Write-Verbose "Enabling network isolation for tenant '$($t.Name)'"

                    $body = @{
                        tenant = $t.Key
                        action = 'isolateon'
                    }

                    $response = Invoke-VergeAPI -Method POST -Endpoint 'tenant_actions' -Body $body -Connection $Server

                    Write-Verbose "Network isolation enabled for tenant '$($t.Name)'"
                }
                catch {
                    Write-Error -Message "Failed to enable isolation for tenant '$($t.Name)': $($_.Exception.Message)" -ErrorId 'TenantIsolationFailed'
                }
            }
        }
    }
}
