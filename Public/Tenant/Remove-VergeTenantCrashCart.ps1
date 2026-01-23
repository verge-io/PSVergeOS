function Remove-VergeTenantCrashCart {
    <#
    .SYNOPSIS
        Removes a Crash Cart VM from a VergeOS tenant.

    .DESCRIPTION
        Remove-VergeTenantCrashCart removes the Crash Cart VM that was deployed
        for emergency tenant access. The VM must be stopped before removal.
        This should be called after troubleshooting is complete.

    .PARAMETER Tenant
        A tenant object from Get-VergeTenant. Accepts pipeline input.

    .PARAMETER TenantName
        The name of the tenant whose Crash Cart should be removed.

    .PARAMETER TenantKey
        The unique key (ID) of the tenant whose Crash Cart should be removed.

    .PARAMETER VM
        A VM object representing the Crash Cart to remove.

    .PARAMETER VMName
        The name of the Crash Cart VM to remove.

    .PARAMETER Force
        Skip confirmation prompts and remove without confirmation.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeTenantCrashCart -TenantName "Customer01"

        Removes the Crash Cart VM for the tenant after confirmation.

    .EXAMPLE
        Remove-VergeTenantCrashCart -VMName "Crash Cart - Customer01" -Force

        Removes the specified Crash Cart VM without confirmation.

    .EXAMPLE
        Get-VergeVM -Name "Crash Cart*" | Remove-VergeTenantCrashCart -Force

        Removes all Crash Cart VMs without confirmation.

    .OUTPUTS
        None.

    .NOTES
        The Crash Cart VM must be stopped before removal. Use Stop-VergeVM first
        if the VM is running. This removes the VM permanently.
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

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByVM')]
        [PSTypeName('Verge.VM')]
        [PSCustomObject]$VM,

        [Parameter(Mandatory, ParameterSetName = 'ByVMName')]
        [string]$VMName,

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
        # Resolve Crash Cart VM based on parameter set
        $targetVMs = switch ($PSCmdlet.ParameterSetName) {
            'ByTenantName' {
                # Find Crash Cart VM for the tenant
                $crashCartName = "Crash Cart - $TenantName"
                Get-VergeVM -Name $crashCartName -Server $Server
            }
            'ByTenantKey' {
                # Get tenant name first
                $tenant = Get-VergeTenant -Key $TenantKey -Server $Server
                if ($tenant) {
                    $crashCartName = "Crash Cart - $($tenant.Name)"
                    Get-VergeVM -Name $crashCartName -Server $Server
                }
            }
            'ByTenant' {
                $crashCartName = "Crash Cart - $($Tenant.Name)"
                Get-VergeVM -Name $crashCartName -Server $Server
            }
            'ByVM' {
                $VM
            }
            'ByVMName' {
                Get-VergeVM -Name $VMName -Server $Server
            }
        }

        foreach ($crashCart in $targetVMs) {
            if (-not $crashCart) {
                if ($PSCmdlet.ParameterSetName -in @('ByTenantName', 'ByTenantKey', 'ByTenant')) {
                    Write-Error -Message "Crash Cart VM not found for tenant." -ErrorId 'CrashCartNotFound'
                }
                elseif ($PSCmdlet.ParameterSetName -eq 'ByVMName') {
                    Write-Error -Message "VM '$VMName' not found." -ErrorId 'VMNotFound'
                }
                continue
            }

            # Check if VM is running
            if ($crashCart.IsRunning -or $crashCart.Status -notin @('Offline', 'Error')) {
                Write-Error -Message "Cannot remove Crash Cart VM '$($crashCart.Name)': VM must be powered off first. Use Stop-VergeVM." -ErrorId 'VMNotStopped'
                continue
            }

            # Confirm action
            if ($Force) {
                $shouldContinue = $true
            }
            else {
                $shouldContinue = $PSCmdlet.ShouldProcess($crashCart.Name, "Remove Crash Cart VM")
            }

            if ($shouldContinue) {
                try {
                    Write-Verbose "Removing Crash Cart VM '$($crashCart.Name)'"
                    $response = Invoke-VergeAPI -Method DELETE -Endpoint "vms/$($crashCart.Key)" -Connection $Server

                    Write-Verbose "Crash Cart VM '$($crashCart.Name)' removed"
                }
                catch {
                    $errorMessage = $_.Exception.Message
                    if ($errorMessage -match 'running') {
                        Write-Error -Message "Cannot remove Crash Cart VM '$($crashCart.Name)': VM is still running. Use Stop-VergeVM first." -ErrorId 'VMRunning'
                    }
                    else {
                        Write-Error -Message "Failed to remove Crash Cart VM '$($crashCart.Name)': $errorMessage" -ErrorId 'CrashCartRemoveFailed'
                    }
                }
            }
        }
    }
}
