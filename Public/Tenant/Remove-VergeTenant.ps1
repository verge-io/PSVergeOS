function Remove-VergeTenant {
    <#
    .SYNOPSIS
        Removes a tenant from VergeOS.

    .DESCRIPTION
        Remove-VergeTenant deletes a tenant and all its associated resources.
        The tenant must be stopped (powered off) before it can be removed.
        This is a destructive operation and cannot be undone.

    .PARAMETER Name
        The name of the tenant to remove. Supports wildcards (* and ?).

    .PARAMETER Key
        The unique key (ID) of the tenant to remove.

    .PARAMETER Tenant
        A tenant object from Get-VergeTenant. Accepts pipeline input.

    .PARAMETER Force
        Skip confirmation prompts and remove the tenant without confirmation.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeTenant -Name "Customer01"

        Removes the tenant named "Customer01" after confirmation.

    .EXAMPLE
        Remove-VergeTenant -Name "Customer01" -Force

        Removes the tenant without confirmation.

    .EXAMPLE
        Get-VergeTenant -Name "Test*" | Remove-VergeTenant

        Removes all tenants whose names start with "Test" after confirmation.

    .OUTPUTS
        None.

    .NOTES
        The tenant must be powered off before removal. Use Stop-VergeTenant first.
        This operation permanently deletes all tenant data including VMs, networks,
        and storage. This cannot be undone.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByName')]
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
        [switch]$Force,

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
        # Get tenants to remove based on parameter set
        $tenantsToRemove = switch ($PSCmdlet.ParameterSetName) {
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

        foreach ($targetTenant in $tenantsToRemove) {
            if (-not $targetTenant) {
                continue
            }

            # Check if tenant is a snapshot
            if ($targetTenant.IsSnapshot) {
                Write-Error -Message "Cannot remove tenant '$($targetTenant.Name)': This is a snapshot. Use Remove-VergeTenantSnapshot instead." -ErrorId 'CannotRemoveSnapshot'
                continue
            }

            # Check if tenant is running
            if ($targetTenant.IsRunning -or $targetTenant.Status -notin @('Offline', 'Error')) {
                Write-Error -Message "Cannot remove tenant '$($targetTenant.Name)': Tenant must be powered off first. Use Stop-VergeTenant to power off the tenant." -ErrorId 'TenantNotStopped'
                continue
            }

            # Confirm action
            $warningMessage = "This will permanently delete tenant '$($targetTenant.Name)' and ALL associated resources (VMs, networks, storage). This cannot be undone."

            if ($Force) {
                # Skip confirmation with Force parameter
                $shouldContinue = $true
            }
            else {
                $shouldContinue = $PSCmdlet.ShouldProcess($targetTenant.Name, "Remove Tenant (WARNING: $warningMessage)")
            }

            if ($shouldContinue) {
                try {
                    Write-Verbose "Removing tenant '$($targetTenant.Name)' (Key: $($targetTenant.Key))"
                    $response = Invoke-VergeAPI -Method DELETE -Endpoint "tenants/$($targetTenant.Key)" -Connection $Server

                    Write-Verbose "Tenant '$($targetTenant.Name)' removed successfully"
                }
                catch {
                    $errorMessage = $_.Exception.Message
                    if ($errorMessage -match 'running') {
                        Write-Error -Message "Cannot remove tenant '$($targetTenant.Name)': Tenant is still running. Use Stop-VergeTenant first." -ErrorId 'TenantRunning'
                    }
                    else {
                        Write-Error -Message "Failed to remove tenant '$($targetTenant.Name)': $errorMessage" -ErrorId 'TenantRemoveFailed'
                    }
                }
            }
        }
    }
}
