function Remove-VergeVM {
    <#
    .SYNOPSIS
        Removes a virtual machine from VergeOS.

    .DESCRIPTION
        Remove-VergeVM permanently deletes one or more virtual machines from VergeOS.
        This operation cannot be undone. The VM must be powered off before removal
        unless -Force is specified, which will forcefully stop the VM first.

    .PARAMETER Name
        The name of the VM to remove. Supports wildcards (* and ?).

    .PARAMETER Key
        The unique key (ID) of the VM to remove.

    .PARAMETER VM
        A VM object from Get-VergeVM. Accepts pipeline input.

    .PARAMETER Force
        Force removal of running VMs by powering them off first.
        Without this switch, attempting to remove a running VM will fail.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeVM -Name "OldServer01"

        Removes the VM named "OldServer01" after confirmation.

    .EXAMPLE
        Remove-VergeVM -Name "OldServer01" -Confirm:$false

        Removes the VM without prompting for confirmation.

    .EXAMPLE
        Remove-VergeVM -Name "TestVM*" -Force

        Forcefully removes all VMs matching "TestVM*", stopping any that are running.

    .EXAMPLE
        Get-VergeVM -Name "temp-*" | Remove-VergeVM -Force -Confirm:$false

        Removes all VMs starting with "temp-" without confirmation, stopping any running VMs.

    .EXAMPLE
        Get-VergeVM -PowerState Stopped | Where-Object { $_.Created -lt (Get-Date).AddDays(-30) } | Remove-VergeVM

        Removes all stopped VMs older than 30 days.

    .OUTPUTS
        None.

    .NOTES
        This is a destructive operation that cannot be undone.
        VM snapshots are also deleted when the VM is removed.
        Use Get-VergeVM to verify which VMs will be affected before removal.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [SupportsWildcards()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByVM')]
        [PSTypeName('Verge.VM')]
        [PSCustomObject]$VM,

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
        # Get VMs to remove based on parameter set
        $vmsToRemove = switch ($PSCmdlet.ParameterSetName) {
            'ByName' {
                Get-VergeVM -Name $Name -Server $Server
            }
            'ByKey' {
                Get-VergeVM -Key $Key -Server $Server
            }
            'ByVM' {
                $VM
            }
        }

        foreach ($targetVM in $vmsToRemove) {
            if (-not $targetVM) {
                continue
            }

            # Check if VM is a snapshot - snapshots are removed differently
            if ($targetVM.IsSnapshot) {
                Write-Error -Message "Cannot remove '$($targetVM.Name)': Use Remove-VergeVMSnapshot to remove snapshots" -ErrorId 'CannotRemoveSnapshot'
                continue
            }

            # Check if VM is running
            if ($targetVM.PowerState -notin @('Stopped', 'stopped')) {
                if ($Force) {
                    # Stop the VM first
                    Write-Verbose "VM '$($targetVM.Name)' is $($targetVM.PowerState). Forcing power off..."
                    try {
                        $killBody = @{
                            vm     = $targetVM.Key
                            action = 'kill'
                        }
                        Invoke-VergeAPI -Method POST -Endpoint 'vm_actions' -Body $killBody -Connection $Server | Out-Null

                        # Wait briefly for VM to stop
                        Start-Sleep -Seconds 2
                    }
                    catch {
                        Write-Error -Message "Failed to stop VM '$($targetVM.Name)' before removal: $($_.Exception.Message)" -ErrorId 'VMStopFailed'
                        continue
                    }
                }
                else {
                    Write-Error -Message "Cannot remove VM '$($targetVM.Name)': VM is $($targetVM.PowerState). Use -Force to stop and remove, or stop the VM first." -ErrorId 'VMNotStopped'
                    continue
                }
            }

            # Confirm action
            if ($PSCmdlet.ShouldProcess($targetVM.Name, 'Remove VM')) {
                try {
                    Write-Verbose "Removing VM '$($targetVM.Name)' (Key: $($targetVM.Key))"
                    Invoke-VergeAPI -Method DELETE -Endpoint "vms/$($targetVM.Key)" -Connection $Server | Out-Null
                    Write-Verbose "VM '$($targetVM.Name)' removed successfully"
                }
                catch {
                    Write-Error -Message "Failed to remove VM '$($targetVM.Name)': $($_.Exception.Message)" -ErrorId 'VMRemoveFailed'
                }
            }
        }
    }
}
