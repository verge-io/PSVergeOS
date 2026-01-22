function Move-VergeVM {
    <#
    .SYNOPSIS
        Moves a VergeOS virtual machine to a different node.

    .DESCRIPTION
        Move-VergeVM live-migrates a running VM to another node in the cluster,
        or moves a stopped VM to a different node. This is useful for load
        balancing, maintenance, or failover scenarios.

    .PARAMETER VM
        A VM object from Get-VergeVM. Accepts pipeline input.

    .PARAMETER Name
        The name of the VM to move.

    .PARAMETER Key
        The key (ID) of the VM to move.

    .PARAMETER DestinationNode
        The key (ID) of the destination node to move to.
        If not specified, VergeOS will automatically select an appropriate node.

    .PARAMETER PassThru
        Return the VM object after the move.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Move-VergeVM -Name "WebServer01"

        Moves the VM to an automatically selected node.

    .EXAMPLE
        Move-VergeVM -Name "WebServer01" -DestinationNode 5

        Moves the VM to the node with key 5.

    .EXAMPLE
        Get-VergeVM -Name "Prod-*" | Move-VergeVM -DestinationNode 3

        Moves all production VMs to node 3.

    .EXAMPLE
        Move-VergeVM -Name "Database01" -PassThru | Select-Object Name, PowerState

        Moves the VM and returns its status.

    .OUTPUTS
        None by default. Verge.VM when -PassThru is specified.

    .NOTES
        Live migration of running VMs requires sufficient resources on the
        destination node. Stopped VMs can be moved without resource constraints.
        Migration time depends on VM memory size and network speed.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByVM')]
        [PSTypeName('Verge.VM')]
        [PSCustomObject]$VM,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter()]
        [int]$DestinationNode,

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
        # Resolve VM based on parameter set
        $targetVMs = switch ($PSCmdlet.ParameterSetName) {
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

        foreach ($targetVM in $targetVMs) {
            if (-not $targetVM) {
                continue
            }

            # Check if VM is a snapshot
            if ($targetVM.IsSnapshot) {
                Write-Error -Message "Cannot move '$($targetVM.Name)': VM is a snapshot" -ErrorId 'CannotMoveSnapshot'
                continue
            }

            # Build action body
            $body = @{
                vm     = $targetVM.Key
                action = 'migrate'
            }

            if ($DestinationNode) {
                $body['params'] = @{
                    node = $DestinationNode
                }
            }

            $destDesc = if ($DestinationNode) { " to node $DestinationNode" } else { ' to auto-selected node' }

            if ($PSCmdlet.ShouldProcess($targetVM.Name, "Move VM$destDesc")) {
                try {
                    Write-Verbose "Moving VM '$($targetVM.Name)'$destDesc"
                    $response = Invoke-VergeAPI -Method POST -Endpoint 'vm_actions' -Body $body -Connection $Server

                    Write-Verbose "Move initiated for VM '$($targetVM.Name)'"

                    if ($PassThru) {
                        # Wait briefly for migration to start/complete
                        Start-Sleep -Seconds 2
                        Get-VergeVM -Key $targetVM.Key -Server $Server
                    }
                }
                catch {
                    Write-Error -Message "Failed to move VM '$($targetVM.Name)': $($_.Exception.Message)" -ErrorId 'MoveFailed'
                }
            }
        }
    }
}
