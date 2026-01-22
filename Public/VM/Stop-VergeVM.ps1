function Stop-VergeVM {
    <#
    .SYNOPSIS
        Powers off a VergeOS virtual machine.

    .DESCRIPTION
        Stop-VergeVM sends a power off command to one or more virtual machines.
        By default, a graceful shutdown is performed (ACPI power button).
        Use -Force to immediately terminate the VM without graceful shutdown.

    .PARAMETER Name
        The name of the VM to stop. Supports wildcards (* and ?).

    .PARAMETER Key
        The unique key (ID) of the VM to stop.

    .PARAMETER VM
        A VM object from Get-VergeVM. Accepts pipeline input.

    .PARAMETER Force
        Immediately terminate the VM without graceful shutdown (kill power).
        Use this when the guest OS is unresponsive.

    .PARAMETER PassThru
        Return the VM object after stopping. By default, no output is returned.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Stop-VergeVM -Name "WebServer01"

        Gracefully shuts down the VM named "WebServer01".

    .EXAMPLE
        Stop-VergeVM -Name "WebServer01" -Force

        Immediately terminates the VM without graceful shutdown.

    .EXAMPLE
        Get-VergeVM -PowerState Running | Stop-VergeVM

        Gracefully shuts down all running VMs.

    .EXAMPLE
        Stop-VergeVM -Name "Test*" -Force -Confirm:$false

        Immediately terminates all VMs starting with "Test" without confirmation.

    .EXAMPLE
        Get-VergeVM -Name "Prod-*" -PowerState Running | Stop-VergeVM -PassThru

        Gracefully shuts down production VMs and returns their updated state.

    .OUTPUTS
        None by default. Verge.VM when -PassThru is specified.

    .NOTES
        Use Start-VergeVM to power on VMs.
        Use -Force when the guest OS is unresponsive (equivalent to pulling the power cord).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByName')]
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
        # Get VMs to stop based on parameter set
        $vmsToStop = switch ($PSCmdlet.ParameterSetName) {
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

        foreach ($targetVM in $vmsToStop) {
            if (-not $targetVM) {
                continue
            }

            # Check if VM is a snapshot
            if ($targetVM.IsSnapshot) {
                Write-Error -Message "Cannot stop VM '$($targetVM.Name)': VM is a snapshot" -ErrorId 'CannotStopSnapshot'
                continue
            }

            # Check if already stopped
            if ($targetVM.PowerState -eq 'Stopped') {
                Write-Warning "VM '$($targetVM.Name)' is already stopped."
                if ($PassThru) {
                    Write-Output $targetVM
                }
                continue
            }

            # Determine action type
            $action = if ($Force) { 'kill' } else { 'poweroff' }
            $actionVerb = if ($Force) { 'Force stop (kill)' } else { 'Gracefully stop' }

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

                    Write-Verbose "Power off command sent for VM '$($targetVM.Name)'"

                    if ($PassThru) {
                        # Return refreshed VM object
                        Start-Sleep -Milliseconds 500
                        Get-VergeVM -Key $targetVM.Key -Server $Server
                    }
                }
                catch {
                    Write-Error -Message "Failed to stop VM '$($targetVM.Name)': $($_.Exception.Message)" -ErrorId 'VMStopFailed'
                }
            }
        }
    }
}
