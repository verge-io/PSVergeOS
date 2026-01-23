function Disable-VergeTenantIsolation {
    <#
    .SYNOPSIS
        Disables network isolation mode for a VergeOS tenant.

    .DESCRIPTION
        Disable-VergeTenantIsolation disables isolation mode for a tenant, which
        restores the tenant's network connectivity. Use this after troubleshooting
        or security investigation is complete.

    .PARAMETER Tenant
        A tenant object from Get-VergeTenant. Accepts pipeline input.

    .PARAMETER TenantName
        The name of the tenant to remove from isolation.

    .PARAMETER TenantKey
        The unique key (ID) of the tenant to remove from isolation.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Disable-VergeTenantIsolation -TenantName "Customer01"

        Disables network isolation for the tenant.

    .EXAMPLE
        Get-VergeTenant -Name "Customer01" | Disable-VergeTenantIsolation

        Disables isolation using pipeline input.

    .EXAMPLE
        Get-VergeTenant | Where-Object IsIsolated | Disable-VergeTenantIsolation

        Disables isolation for all currently isolated tenants.

    .OUTPUTS
        None.

    .NOTES
        Disabling isolation restores the tenant's network connectivity.
        The tenant will be able to communicate with external networks again.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByTenantName')]
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
                Write-Error -Message "Cannot disable isolation for tenant '$($t.Name)': Tenant is a snapshot." -ErrorId 'CannotModifySnapshot'
                continue
            }

            # Check if not isolated
            if (-not $t.Isolated) {
                Write-Warning "Tenant '$($t.Name)' is not in isolation mode."
                continue
            }

            # Confirm action
            if ($PSCmdlet.ShouldProcess($t.Name, "Disable network isolation")) {
                try {
                    Write-Verbose "Disabling network isolation for tenant '$($t.Name)'"

                    $body = @{
                        tenant = $t.Key
                        action = 'isolateoff'
                    }

                    $response = Invoke-VergeAPI -Method POST -Endpoint 'tenant_actions' -Body $body -Connection $Server

                    Write-Verbose "Network isolation disabled for tenant '$($t.Name)'"
                }
                catch {
                    Write-Error -Message "Failed to disable isolation for tenant '$($t.Name)': $($_.Exception.Message)" -ErrorId 'TenantIsolationFailed'
                }
            }
        }
    }
}
