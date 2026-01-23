function Restart-VergeNode {
    <#
    .SYNOPSIS
        Reboots a VergeOS node using maintenance reboot.

    .DESCRIPTION
        Restart-VergeNode performs a maintenance reboot on a node.
        This safely reboots the node by first migrating workloads
        and then restarting the system.

    .PARAMETER Name
        The name (hostname) of the node to reboot.

    .PARAMETER Key
        The unique key (ID) of the node to reboot.

    .PARAMETER Node
        A node object from Get-VergeNode to reboot.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Restart-VergeNode -Name "node1"

        Performs a maintenance reboot on node1.

    .EXAMPLE
        Get-VergeNode -Name "node1" | Restart-VergeNode

        Reboots node1 using pipeline input.

    .EXAMPLE
        Restart-VergeNode -Name "node1" -Confirm:$false

        Reboots node1 without prompting for confirmation.

    .OUTPUTS
        None. The cmdlet initiates the reboot task.

    .NOTES
        The node must be in maintenance mode or will be put into maintenance mode
        automatically. This operation may take time as VMs are migrated off the node.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(Mandatory, ParameterSetName = 'ByObject', ValueFromPipeline)]
        [PSTypeName('Verge.Node')]
        [PSCustomObject]$Node,

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
        try {
            # Resolve node key
            $nodeKey = $null
            $nodeName = $null

            switch ($PSCmdlet.ParameterSetName) {
                'ByName' {
                    $nodeName = $Name
                    $existingNode = Get-VergeNode -Name $Name -Server $Server
                    if (-not $existingNode) {
                        throw [System.Management.Automation.ItemNotFoundException]::new("Node '$Name' not found.")
                    }
                    $nodeKey = $existingNode.Key
                }
                'ByKey' {
                    $nodeKey = $Key
                    $existingNode = Get-VergeNode -Key $Key -Server $Server
                    if (-not $existingNode) {
                        throw [System.Management.Automation.ItemNotFoundException]::new("Node with key '$Key' not found.")
                    }
                    $nodeName = $existingNode.Name
                }
                'ByObject' {
                    $nodeKey = $Node.Key
                    $nodeName = $Node.Name
                    if ($Node._Connection) {
                        $Server = $Node._Connection
                    }
                }
            }

            if ($PSCmdlet.ShouldProcess($nodeName, 'Maintenance reboot')) {
                Write-Verbose "Initiating maintenance reboot on node '$nodeName' (Key: $nodeKey)"

                # Use the node action API for maintenance reboot
                $body = @{
                    node = $nodeKey
                }

                $response = Invoke-VergeAPI -Method POST -Endpoint 'node_actions/maintenance_reboot' -Body $body -Connection $Server

                Write-Verbose "Maintenance reboot initiated for node '$nodeName'"

                # Return task info if available
                if ($response.task) {
                    [PSCustomObject]@{
                        PSTypeName = 'Verge.Task'
                        TaskKey    = $response.task
                        Node       = $nodeName
                        NodeKey    = $nodeKey
                        Action     = 'maintenance_reboot'
                        Status     = 'Initiated'
                    }
                }
            }
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}
