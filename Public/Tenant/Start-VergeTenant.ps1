function Start-VergeTenant {
    <#
    .SYNOPSIS
        Powers on a VergeOS tenant.

    .DESCRIPTION
        Start-VergeTenant sends a power on command to one or more tenants.
        The cmdlet supports pipeline input from Get-VergeTenant for bulk operations.

    .PARAMETER Name
        The name of the tenant to start. Supports wildcards (* and ?).

    .PARAMETER Key
        The unique key (ID) of the tenant to start.

    .PARAMETER Tenant
        A tenant object from Get-VergeTenant. Accepts pipeline input.

    .PARAMETER PreferredNode
        Optionally specify a preferred node to start the tenant on.

    .PARAMETER PassThru
        Return the tenant object after starting. By default, no output is returned.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Start-VergeTenant -Name "Customer01"

        Starts the tenant named "Customer01".

    .EXAMPLE
        Start-VergeTenant -Name "Prod*"

        Starts all tenants whose names start with "Prod".

    .EXAMPLE
        Get-VergeTenant -Status Offline | Start-VergeTenant

        Starts all offline tenants.

    .EXAMPLE
        Start-VergeTenant -Name "Customer01" -PassThru

        Starts the tenant and returns the updated tenant object.

    .OUTPUTS
        None by default. Verge.Tenant when -PassThru is specified.

    .NOTES
        Use Stop-VergeTenant to power off tenants.
        Use Get-VergeTenant to check the current power state.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByName')]
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
        [int]$PreferredNode,

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
        # Get tenants to start based on parameter set
        $tenantsToStart = switch ($PSCmdlet.ParameterSetName) {
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

        foreach ($targetTenant in $tenantsToStart) {
            if (-not $targetTenant) {
                continue
            }

            # Check if tenant is a snapshot
            if ($targetTenant.IsSnapshot) {
                Write-Error -Message "Cannot start tenant '$($targetTenant.Name)': Tenant is a snapshot" -ErrorId 'CannotStartSnapshot'
                continue
            }

            # Check if already running
            if ($targetTenant.IsRunning -or $targetTenant.Status -eq 'Online') {
                Write-Warning "Tenant '$($targetTenant.Name)' is already running."
                if ($PassThru) {
                    Write-Output $targetTenant
                }
                continue
            }

            # Check if starting
            if ($targetTenant.IsStarting -or $targetTenant.Status -eq 'Starting') {
                Write-Warning "Tenant '$($targetTenant.Name)' is already starting."
                if ($PassThru) {
                    Write-Output $targetTenant
                }
                continue
            }

            # Build action body
            $body = @{
                tenant = $targetTenant.Key
                action = 'poweron'
            }

            # Add preferred node if specified
            if ($PSBoundParameters.ContainsKey('PreferredNode')) {
                $body['params'] = @{
                    preferred_node = $PreferredNode
                }
            }

            # Confirm action
            if ($PSCmdlet.ShouldProcess($targetTenant.Name, 'Start Tenant')) {
                try {
                    Write-Verbose "Starting tenant '$($targetTenant.Name)' (Key: $($targetTenant.Key))"
                    $response = Invoke-VergeAPI -Method POST -Endpoint 'tenant_actions' -Body $body -Connection $Server

                    Write-Verbose "Power on command sent for tenant '$($targetTenant.Name)'"

                    if ($PassThru) {
                        # Return refreshed tenant object
                        Start-Sleep -Milliseconds 500
                        Get-VergeTenant -Key $targetTenant.Key -Server $Server
                    }
                }
                catch {
                    Write-Error -Message "Failed to start tenant '$($targetTenant.Name)': $($_.Exception.Message)" -ErrorId 'TenantStartFailed'
                }
            }
        }
    }
}
