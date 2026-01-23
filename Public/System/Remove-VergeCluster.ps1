function Remove-VergeCluster {
    <#
    .SYNOPSIS
        Deletes a VergeOS cluster.

    .DESCRIPTION
        Remove-VergeCluster deletes one or more clusters from VergeOS.
        Clusters cannot be deleted if they have nodes or VMs assigned to them.
        The cmdlet supports pipeline input from Get-VergeCluster for bulk operations.

    .PARAMETER Name
        The name of the cluster to delete. Supports wildcards (* and ?).

    .PARAMETER Key
        The unique key (ID) of the cluster to delete.

    .PARAMETER Cluster
        A cluster object from Get-VergeCluster. Accepts pipeline input.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeCluster -Name "Test-Cluster"

        Deletes the cluster named "Test-Cluster" after confirmation.

    .EXAMPLE
        Remove-VergeCluster -Name "Test-Cluster" -Confirm:$false

        Deletes the cluster without confirmation prompt.

    .EXAMPLE
        Get-VergeCluster -Name "Temp-*" | Remove-VergeCluster

        Deletes all clusters starting with "Temp-".

    .OUTPUTS
        None

    .NOTES
        Clusters cannot be deleted if they have nodes or VMs assigned.
        Reassign nodes and VMs to another cluster before deletion.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [SupportsWildcards()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByCluster')]
        [PSTypeName('Verge.Cluster')]
        [PSCustomObject]$Cluster,

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
        # Get clusters to delete based on parameter set
        $clustersToDelete = switch ($PSCmdlet.ParameterSetName) {
            'ByName' {
                Get-VergeCluster -Name $Name -Server $Server
            }
            'ByKey' {
                Get-VergeCluster -Key $Key -Server $Server
            }
            'ByCluster' {
                $Cluster
            }
        }

        foreach ($targetCluster in $clustersToDelete) {
            if (-not $targetCluster) {
                continue
            }

            # Safety check - don't allow deletion if cluster has nodes
            if ($targetCluster.TotalNodes -gt 0) {
                Write-Error -Message "Cannot delete cluster '$($targetCluster.Name)': Cluster has $($targetCluster.TotalNodes) node(s) assigned. Reassign nodes to another cluster first." -ErrorId 'ClusterHasNodes'
                continue
            }

            # Safety check - don't allow deletion if cluster has running machines
            if ($targetCluster.RunningMachines -gt 0) {
                Write-Error -Message "Cannot delete cluster '$($targetCluster.Name)': Cluster has $($targetCluster.RunningMachines) running machine(s). Stop and reassign VMs first." -ErrorId 'ClusterHasRunningMachines'
                continue
            }

            # Confirm deletion
            if ($PSCmdlet.ShouldProcess($targetCluster.Name, 'Remove Cluster')) {
                try {
                    Write-Verbose "Deleting cluster '$($targetCluster.Name)' (Key: $($targetCluster.Key))"
                    $response = Invoke-VergeAPI -Method DELETE -Endpoint "clusters/$($targetCluster.Key)" -Connection $Server

                    Write-Verbose "Cluster '$($targetCluster.Name)' deleted successfully"
                }
                catch {
                    $errorMessage = $_.Exception.Message
                    if ($errorMessage -match 'nodes still referencing') {
                        Write-Error -Message "Cannot delete cluster '$($targetCluster.Name)': Nodes are still assigned to this cluster. Reassign nodes first." -ErrorId 'ClusterHasNodes'
                    }
                    elseif ($errorMessage -match 'machines still referencing') {
                        Write-Error -Message "Cannot delete cluster '$($targetCluster.Name)': VMs are still assigned to this cluster. Reassign VMs first." -ErrorId 'ClusterHasMachines'
                    }
                    else {
                        Write-Error -Message "Failed to delete cluster '$($targetCluster.Name)': $errorMessage" -ErrorId 'ClusterDeleteFailed'
                    }
                }
            }
        }
    }
}
