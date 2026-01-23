function Restart-VergeTenant {
    <#
    .SYNOPSIS
        Restarts a VergeOS tenant.

    .DESCRIPTION
        Restart-VergeTenant sends a reset command to one or more tenants.
        This performs a hard reset of the tenant (similar to pressing a physical reset button).
        The cmdlet supports pipeline input from Get-VergeTenant for bulk operations.

    .PARAMETER Name
        The name of the tenant to restart. Supports wildcards (* and ?).

    .PARAMETER Key
        The unique key (ID) of the tenant to restart.

    .PARAMETER Tenant
        A tenant object from Get-VergeTenant. Accepts pipeline input.

    .PARAMETER PassThru
        Return the tenant object after restarting. By default, no output is returned.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Restart-VergeTenant -Name "Customer01"

        Restarts the tenant named "Customer01".

    .EXAMPLE
        Restart-VergeTenant -Name "Prod*"

        Restarts all tenants whose names start with "Prod".

    .EXAMPLE
        Get-VergeTenant -Status Online | Restart-VergeTenant

        Restarts all online tenants.

    .EXAMPLE
        Restart-VergeTenant -Name "Customer01" -PassThru

        Restarts the tenant and returns the updated tenant object.

    .OUTPUTS
        None by default. Verge.Tenant when -PassThru is specified.

    .NOTES
        Use Start-VergeTenant to power on tenants.
        Use Stop-VergeTenant to power off tenants.
        The tenant must be running to be restarted.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [SupportsWildcards()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByTenant')]
        [PSTypeName('Verge.Tenant')]
        [PSCustomObject]$Tenant,

        [Parameter()]
        [switch]$PassThru,

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
        # Get tenants to restart based on parameter set
        $tenantsToRestart = switch ($PSCmdlet.ParameterSetName) {
            'ByName' {
                Get-VergeTenant -Name $Name -Server $Server
            }
            'ByKey' {
                Get-VergeTenant -Key $Key -Server $Server
            }
            'ByTenant' {
                $Tenant
            }
        }

        foreach ($targetTenant in $tenantsToRestart) {
            if (-not $targetTenant) {
                continue
            }

            # Check if tenant is a snapshot
            if ($targetTenant.IsSnapshot) {
                Write-Error -Message "Cannot restart tenant '$($targetTenant.Name)': Tenant is a snapshot" -ErrorId 'CannotRestartSnapshot'
                continue
            }

            # Check if tenant is running
            if (-not $targetTenant.IsRunning -and $targetTenant.Status -eq 'Offline') {
                Write-Error -Message "Cannot restart tenant '$($targetTenant.Name)': Tenant is not running. Use Start-VergeTenant to power on the tenant first." -ErrorId 'TenantNotRunning'
                continue
            }

            # Build action body
            $body = @{
                tenant = $targetTenant.Key
                action = 'reset'
            }

            # Confirm action
            if ($PSCmdlet.ShouldProcess($targetTenant.Name, 'Restart Tenant')) {
                try {
                    Write-Verbose "Restarting tenant '$($targetTenant.Name)' (Key: $($targetTenant.Key))"
                    $response = Invoke-VergeAPI -Method POST -Endpoint 'tenant_actions' -Body $body -Connection $Server

                    Write-Verbose "Reset command sent for tenant '$($targetTenant.Name)'"

                    if ($PassThru) {
                        # Return refreshed tenant object
                        Start-Sleep -Milliseconds 500
                        Get-VergeTenant -Key $targetTenant.Key -Server $Server
                    }
                }
                catch {
                    Write-Error -Message "Failed to restart tenant '$($targetTenant.Name)': $($_.Exception.Message)" -ErrorId 'TenantRestartFailed'
                }
            }
        }
    }
}
