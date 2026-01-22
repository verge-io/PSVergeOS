function Restart-VergeVM {
    <#
    .SYNOPSIS
        Restarts a VergeOS virtual machine.

    .DESCRIPTION
        Restart-VergeVM reboots one or more virtual machines. By default, a graceful
        reboot is performed (ACPI signal). Use -Force to perform a hard reset,
        equivalent to pressing the physical reset button.

    .PARAMETER Name
        The name of the VM to restart. Supports wildcards (* and ?).

    .PARAMETER Key
        The unique key (ID) of the VM to restart.

    .PARAMETER VM
        A VM object from Get-VergeVM. Accepts pipeline input.

    .PARAMETER Force
        Perform a hard reset instead of graceful reboot.
        Use this when the guest OS is unresponsive.

    .PARAMETER PassThru
        Return the VM object after restarting. By default, no output is returned.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Restart-VergeVM -Name "WebServer01"

        Gracefully reboots the VM named "WebServer01".

    .EXAMPLE
        Restart-VergeVM -Name "WebServer01" -Force

        Performs a hard reset on the VM (like pressing the reset button).

    .EXAMPLE
        Get-VergeVM -Name "App*" -PowerState Running | Restart-VergeVM

        Gracefully reboots all running VMs starting with "App".

    .EXAMPLE
        Restart-VergeVM -Name "FrozenVM" -Force -Confirm:$false

        Hard resets an unresponsive VM without confirmation.

    .OUTPUTS
        None by default. Verge.VM when -PassThru is specified.

    .NOTES
        Graceful restart requires the QEMU Guest Agent to be installed and running
        inside the VM. If the guest agent is not available, use -Force for a hard reset.

        Use -Force when the guest OS is unresponsive (equivalent to reset button).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByName')]
    [OutputType([PSCustomObject])]
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
        # Get VMs to restart based on parameter set
        $vmsToRestart = switch ($PSCmdlet.ParameterSetName) {
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

        foreach ($targetVM in $vmsToRestart) {
            if (-not $targetVM) {
                continue
            }

            # Check if VM is a snapshot
            if ($targetVM.IsSnapshot) {
                Write-Error -Message "Cannot restart VM '$($targetVM.Name)': VM is a snapshot" -ErrorId 'CannotRestartSnapshot'
                continue
            }

            # Check if VM is running
            if ($targetVM.PowerState -ne 'Running') {
                Write-Warning "VM '$($targetVM.Name)' is not running (state: $($targetVM.PowerState)). Use Start-VergeVM to power on."
                if ($PassThru) {
                    Write-Output $targetVM
                }
                continue
            }

            # Check if graceful restart is requested but guest agent is not enabled
            if (-not $Force -and -not $targetVM.GuestAgent) {
                Write-Warning "VM '$($targetVM.Name)' does not have guest agent enabled. Graceful restart requires the QEMU Guest Agent. Use -Force for a hard reset instead."
                continue
            }

            # Determine action type
            # reset = hard reset (like reset button)
            # guestreset = graceful reboot (ACPI signal, requires guest agent)
            $action = if ($Force) { 'reset' } else { 'guestreset' }
            $actionVerb = if ($Force) { 'Hard reset' } else { 'Gracefully restart' }

            # Build action body
            $body = @{
                vm     = $targetVM.Key
                action = $action
            }

            # Confirm action
            if ($PSCmdlet.ShouldProcess($targetVM.Name, "$actionVerb VM")) {
                try {
                    Write-Verbose "$actionVerb VM '$($targetVM.Name)' (Key: $($targetVM.Key))"
                    $response = Invoke-VergeAPI -Method POST -Endpoint 'vm_actions' -Body $body -Connection $Server

                    Write-Verbose "Restart command sent for VM '$($targetVM.Name)'"

                    if ($PassThru) {
                        # Return refreshed VM object
                        Start-Sleep -Milliseconds 500
                        Get-VergeVM -Key $targetVM.Key -Server $Server
                    }
                }
                catch {
                    $errorMessage = $_.Exception.Message
                    # Provide more helpful message for guest agent issues
                    if (-not $Force -and ($errorMessage -match '422' -or $errorMessage -match 'guest')) {
                        Write-Error -Message "Failed to gracefully restart VM '$($targetVM.Name)': Guest agent may not be running. Use -Force for a hard reset." -ErrorId 'GuestAgentRequired'
                    }
                    else {
                        Write-Error -Message "Failed to restart VM '$($targetVM.Name)': $errorMessage" -ErrorId 'VMRestartFailed'
                    }
                }
            }
        }
    }
}
