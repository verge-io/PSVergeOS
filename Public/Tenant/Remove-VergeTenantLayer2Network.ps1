function Remove-VergeTenantLayer2Network {
    <#
    .SYNOPSIS
        Removes a Layer 2 network assignment from a VergeOS tenant.

    .DESCRIPTION
        Remove-VergeTenantLayer2Network removes a Layer 2 network assignment
        from a tenant, disconnecting the bridged network connectivity.

    .PARAMETER Layer2Network
        A Layer 2 network object from Get-VergeTenantLayer2Network. Accepts pipeline input.

    .PARAMETER Key
        The unique key (ID) of the Layer 2 network assignment to remove.

    .PARAMETER TenantName
        The name of the tenant. Used with -NetworkName.

    .PARAMETER NetworkName
        The name of the network to remove. Requires -TenantName.

    .PARAMETER Force
        Skip confirmation prompts and remove without confirmation.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeTenantLayer2Network -Key 42

        Removes the Layer 2 network assignment after confirmation.

    .EXAMPLE
        Remove-VergeTenantLayer2Network -TenantName "Customer01" -NetworkName "VLAN100" -Force

        Removes the network assignment without confirmation.

    .EXAMPLE
        Get-VergeTenantLayer2Network -TenantName "Customer01" | Remove-VergeTenantLayer2Network -Force

        Removes all Layer 2 networks from the tenant without confirmation.

    .OUTPUTS
        None.

    .NOTES
        Removing a Layer 2 network disconnects the bridged connectivity between
        the parent and tenant networks. This may affect tenant workloads.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByKey')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [PSTypeName('Verge.TenantLayer2Network')]
        [PSCustomObject]$Layer2Network,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [string]$TenantName,

        [Parameter(Mandatory, Position = 1, ParameterSetName = 'ByName')]
        [string]$NetworkName,

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
        # Resolve Layer 2 network based on parameter set
        $targetObjects = switch ($PSCmdlet.ParameterSetName) {
            'ByKey' {
                Get-VergeTenantLayer2Network -Key $Key -Server $Server
            }
            'ByName' {
                Get-VergeTenantLayer2Network -TenantName $TenantName -Server $Server | Where-Object { $_.NetworkName -eq $NetworkName }
            }
            'ByObject' {
                $Layer2Network
            }
        }

        foreach ($obj in $targetObjects) {
            if (-not $obj) {
                if ($PSCmdlet.ParameterSetName -eq 'ByName') {
                    Write-Error -Message "Layer 2 network '$NetworkName' not found for tenant '$TenantName'." -ErrorId 'Layer2NetworkNotFound'
                }
                elseif ($PSCmdlet.ParameterSetName -eq 'ByKey') {
                    Write-Error -Message "Layer 2 network assignment with key $Key not found." -ErrorId 'Layer2NetworkNotFound'
                }
                continue
            }

            # Build description for confirmation
            $objDesc = "$($obj.TenantName)/$($obj.NetworkName)"

            # Confirm action
            if ($Force) {
                $shouldContinue = $true
            }
            else {
                $shouldContinue = $PSCmdlet.ShouldProcess($objDesc, "Remove Layer 2 network")
            }

            if ($shouldContinue) {
                try {
                    Write-Verbose "Removing Layer 2 network '$($obj.NetworkName)' from tenant '$($obj.TenantName)'"
                    $response = Invoke-VergeAPI -Method DELETE -Endpoint "tenant_layer2_vnets/$($obj.Key)" -Connection $Server

                    Write-Verbose "Layer 2 network '$objDesc' removed"
                }
                catch {
                    Write-Error -Message "Failed to remove Layer 2 network '$objDesc': $($_.Exception.Message)" -ErrorId 'Layer2NetworkRemoveFailed'
                }
            }
        }
    }
}
