function Start-VergeVM {
    <#
    .SYNOPSIS
        Powers on a VergeOS virtual machine.

    .DESCRIPTION
        Start-VergeVM sends a power on command to one or more virtual machines.
        The cmdlet supports pipeline input from Get-VergeVM for bulk operations.

    .PARAMETER Name
        The name of the VM to start. Supports wildcards (* and ?).

    .PARAMETER Key
        The unique key (ID) of the VM to start.

    .PARAMETER VM
        A VM object from Get-VergeVM. Accepts pipeline input.

    .PARAMETER PreferredNode
        Optionally specify a preferred node to start the VM on.

    .PARAMETER PassThru
        Return the VM object after starting. By default, no output is returned.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Start-VergeVM -Name "WebServer01"

        Starts the VM named "WebServer01".

    .EXAMPLE
        Start-VergeVM -Name "Web*"

        Starts all VMs whose names start with "Web".

    .EXAMPLE
        Get-VergeVM -PowerState Stopped | Start-VergeVM

        Starts all stopped VMs.

    .EXAMPLE
        Start-VergeVM -Name "WebServer01" -PassThru

        Starts the VM and returns the updated VM object.

    .EXAMPLE
        Get-VergeVM -Name "Prod-*" -PowerState Stopped | Start-VergeVM -Confirm:$false

        Starts all stopped production VMs without confirmation prompts.

    .OUTPUTS
        None by default. Verge.VM when -PassThru is specified.

    .NOTES
        Use Stop-VergeVM to power off VMs.
        Use Get-VergeVM to check the current power state.
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
        # Get VMs to start based on parameter set
        $vmsToStart = switch ($PSCmdlet.ParameterSetName) {
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

        foreach ($targetVM in $vmsToStart) {
            if (-not $targetVM) {
                continue
            }

            # Check if VM is a snapshot
            if ($targetVM.IsSnapshot) {
                Write-Error -Message "Cannot start VM '$($targetVM.Name)': VM is a snapshot" -ErrorId 'CannotStartSnapshot'
                continue
            }

            # Check if already running
            if ($targetVM.PowerState -eq 'Running') {
                Write-Warning "VM '$($targetVM.Name)' is already running."
                if ($PassThru) {
                    Write-Output $targetVM
                }
                continue
            }

            # Build action body
            $body = @{
                vm     = $targetVM.Key
                action = 'poweron'
            }

            # Add preferred node if specified
            if ($PSBoundParameters.ContainsKey('PreferredNode')) {
                $body['params'] = @{
                    preferred_node = $PreferredNode
                }
            }

            # Confirm action
            $actionDescription = "Power on VM '$($targetVM.Name)'"
            if ($PSCmdlet.ShouldProcess($targetVM.Name, 'Start VM')) {
                try {
                    Write-Verbose "Starting VM '$($targetVM.Name)' (Key: $($targetVM.Key))"
                    $response = Invoke-VergeAPI -Method POST -Endpoint 'vm_actions' -Body $body -Connection $Server

                    Write-Verbose "Power on command sent for VM '$($targetVM.Name)'"

                    if ($PassThru) {
                        # Return refreshed VM object
                        Start-Sleep -Milliseconds 500
                        Get-VergeVM -Key $targetVM.Key -Server $Server
                    }
                }
                catch {
                    Write-Error -Message "Failed to start VM '$($targetVM.Name)': $($_.Exception.Message)" -ErrorId 'VMStartFailed'
                }
            }
        }
    }
}
