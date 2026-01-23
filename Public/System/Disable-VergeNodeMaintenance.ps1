function Disable-VergeNodeMaintenance {
    <#
    .SYNOPSIS
        Disables maintenance mode on a VergeOS node.

    .DESCRIPTION
        Disable-VergeNodeMaintenance takes a node out of maintenance mode.
        Once disabled, the node will be available to run VMs and receive
        new workloads.

    .PARAMETER Name
        The name (hostname) of the node to take out of maintenance mode.

    .PARAMETER Key
        The unique key (ID) of the node to take out of maintenance mode.

    .PARAMETER Node
        A node object from Get-VergeNode to take out of maintenance mode.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Disable-VergeNodeMaintenance -Name "node1"

        Takes node1 out of maintenance mode.

    .EXAMPLE
        Get-VergeNode -Name "node1" | Disable-VergeNodeMaintenance

        Takes node1 out of maintenance mode using pipeline input.

    .EXAMPLE
        Get-VergeNode -MaintenanceMode $true | Disable-VergeNodeMaintenance

        Takes all nodes in maintenance mode out of maintenance.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.Node'

    .NOTES
        Use Enable-VergeNodeMaintenance to put a node into maintenance mode.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByName')]
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

            if ($PSCmdlet.ShouldProcess($nodeName, 'Disable maintenance mode')) {
                Write-Verbose "Disabling maintenance mode on node '$nodeName' (Key: $nodeKey)"

                # Use the node action API
                $body = @{
                    node = $nodeKey
                }

                $response = Invoke-VergeAPI -Method POST -Endpoint 'node_actions/disable_maintenance' -Body $body -Connection $Server

                # Return the updated node
                Get-VergeNode -Key $nodeKey -Server $Server
            }
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}
