function Stop-VergeTenant {
    <#
    .SYNOPSIS
        Powers off a VergeOS tenant.

    .DESCRIPTION
        Stop-VergeTenant sends a power off command to one or more tenants.
        The cmdlet supports pipeline input from Get-VergeTenant for bulk operations.

    .PARAMETER Name
        The name of the tenant to stop. Supports wildcards (* and ?).

    .PARAMETER Key
        The unique key (ID) of the tenant to stop.

    .PARAMETER Tenant
        A tenant object from Get-VergeTenant. Accepts pipeline input.

    .PARAMETER PassThru
        Return the tenant object after stopping. By default, no output is returned.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Stop-VergeTenant -Name "Customer01"

        Stops the tenant named "Customer01".

    .EXAMPLE
        Stop-VergeTenant -Name "Dev*"

        Stops all tenants whose names start with "Dev".

    .EXAMPLE
        Get-VergeTenant -Status Online | Stop-VergeTenant

        Stops all online tenants.

    .EXAMPLE
        Stop-VergeTenant -Name "Customer01" -PassThru

        Stops the tenant and returns the updated tenant object.

    .OUTPUTS
        None by default. Verge.Tenant when -PassThru is specified.

    .NOTES
        Use Start-VergeTenant to power on tenants.
        Use Get-VergeTenant to check the current power state.
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
        # Get tenants to stop based on parameter set
        $tenantsToStop = switch ($PSCmdlet.ParameterSetName) {
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

        foreach ($targetTenant in $tenantsToStop) {
            if (-not $targetTenant) {
                continue
            }

            # Check if tenant is a snapshot
            if ($targetTenant.IsSnapshot) {
                Write-Error -Message "Cannot stop tenant '$($targetTenant.Name)': Tenant is a snapshot" -ErrorId 'CannotStopSnapshot'
                continue
            }

            # Check if already stopped
            if ($targetTenant.Status -eq 'Offline' -and -not $targetTenant.IsRunning) {
                Write-Warning "Tenant '$($targetTenant.Name)' is already stopped."
                if ($PassThru) {
                    Write-Output $targetTenant
                }
                continue
            }

            # Check if already stopping
            if ($targetTenant.IsStopping -or $targetTenant.Status -eq 'Stopping') {
                Write-Warning "Tenant '$($targetTenant.Name)' is already stopping."
                if ($PassThru) {
                    Write-Output $targetTenant
                }
                continue
            }

            # Build action body
            $body = @{
                tenant = $targetTenant.Key
                action = 'poweroff'
            }

            # Confirm action
            if ($PSCmdlet.ShouldProcess($targetTenant.Name, 'Stop Tenant')) {
                try {
                    Write-Verbose "Stopping tenant '$($targetTenant.Name)' (Key: $($targetTenant.Key))"
                    $response = Invoke-VergeAPI -Method POST -Endpoint 'tenant_actions' -Body $body -Connection $Server

                    Write-Verbose "Power off command sent for tenant '$($targetTenant.Name)'"

                    if ($PassThru) {
                        # Return refreshed tenant object
                        Start-Sleep -Milliseconds 500
                        Get-VergeTenant -Key $targetTenant.Key -Server $Server
                    }
                }
                catch {
                    Write-Error -Message "Failed to stop tenant '$($targetTenant.Name)': $($_.Exception.Message)" -ErrorId 'TenantStopFailed'
                }
            }
        }
    }
}
