function Enable-VergeNodeMaintenance {
    <#
    .SYNOPSIS
        Enables maintenance mode on a VergeOS node.

    .DESCRIPTION
        Enable-VergeNodeMaintenance puts a node into maintenance mode.
        When in maintenance mode, VMs will be migrated off the node and
        no new workloads will be scheduled to it.

    .PARAMETER Name
        The name (hostname) of the node to put into maintenance mode.

    .PARAMETER Key
        The unique key (ID) of the node to put into maintenance mode.

    .PARAMETER Node
        A node object from Get-VergeNode to put into maintenance mode.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Enable-VergeNodeMaintenance -Name "node1"

        Puts node1 into maintenance mode.

    .EXAMPLE
        Get-VergeNode -Name "node1" | Enable-VergeNodeMaintenance

        Puts node1 into maintenance mode using pipeline input.

    .EXAMPLE
        Enable-VergeNodeMaintenance -Name "node1" -Confirm:$false

        Puts node1 into maintenance mode without prompting for confirmation.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.Node'

    .NOTES
        This operation may take time as VMs are migrated off the node.
        Use Disable-VergeNodeMaintenance to take the node out of maintenance mode.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByName')]
    [OutputType([PSCustomObject])]
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

            if ($PSCmdlet.ShouldProcess($nodeName, 'Enable maintenance mode')) {
                Write-Verbose "Enabling maintenance mode on node '$nodeName' (Key: $nodeKey)"

                # Use the node action API
                $body = @{
                    node = $nodeKey
                }

                $response = Invoke-VergeAPI -Method POST -Endpoint 'node_actions/enable_maintenance' -Body $body -Connection $Server

                # Return the updated node
                Get-VergeNode -Key $nodeKey -Server $Server
            }
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}
