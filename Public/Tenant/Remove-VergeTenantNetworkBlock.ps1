function Remove-VergeTenantNetworkBlock {
    <#
    .SYNOPSIS
        Removes a network block (CIDR range) assignment from a VergeOS tenant.

    .DESCRIPTION
        Remove-VergeTenantNetworkBlock removes a CIDR network block assignment from a tenant.
        The network block will be released and can be reassigned to other tenants.

    .PARAMETER NetworkBlock
        A network block object from Get-VergeTenantNetworkBlock. Accepts pipeline input.

    .PARAMETER TenantName
        The name of the tenant. Used with -CIDR.

    .PARAMETER CIDR
        The network block to remove. Requires -TenantName.

    .PARAMETER Key
        The unique key (ID) of the network block assignment to remove.

    .PARAMETER Force
        Skip confirmation prompts and remove without confirmation.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeTenantNetworkBlock -TenantName "Customer01" -CIDR "192.168.100.0/24"

        Removes the network block assignment after confirmation.

    .EXAMPLE
        Get-VergeTenantNetworkBlock -TenantName "Customer01" | Remove-VergeTenantNetworkBlock -Force

        Removes all network blocks from the tenant without confirmation.

    .EXAMPLE
        Remove-VergeTenantNetworkBlock -Key 42 -Force

        Removes the network block assignment by key without confirmation.

    .OUTPUTS
        None.

    .NOTES
        Removing a network block may disrupt connectivity for services using addresses in that range.
        Firewall rules referencing the block must be removed first.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByNetworkBlock')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByNetworkBlock')]
        [PSTypeName('Verge.TenantNetworkBlock')]
        [PSCustomObject]$NetworkBlock,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByTenantCIDR')]
        [string]$TenantName,

        [Parameter(Mandatory, Position = 1, ParameterSetName = 'ByTenantCIDR')]
        [string]$CIDR,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

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
        # Resolve network block based on parameter set
        $targetBlocks = switch ($PSCmdlet.ParameterSetName) {
            'ByNetworkBlock' {
                $NetworkBlock
            }
            'ByTenantCIDR' {
                Get-VergeTenantNetworkBlock -TenantName $TenantName -CIDR $CIDR -Server $Server
            }
            'ByKey' {
                # Query directly by key
                $queryParams = @{
                    filter = "`$key eq $Key"
                    fields = '$key,cidr,vnet#name as network_name,owner'
                }
                $response = Invoke-VergeAPI -Method GET -Endpoint 'vnet_cidrs' -Query $queryParams -Connection $Server
                if ($response) {
                    [PSCustomObject]@{
                        PSTypeName  = 'Verge.TenantNetworkBlock'
                        Key         = [int]$response.'$key'
                        CIDR        = $response.cidr
                        NetworkName = $response.network_name
                        _Connection = $Server
                    }
                }
                else {
                    Write-Error -Message "Network block with key $Key not found." -ErrorId 'NetworkBlockNotFound'
                    return
                }
            }
        }

        foreach ($block in $targetBlocks) {
            if (-not $block) {
                if ($PSCmdlet.ParameterSetName -eq 'ByTenantCIDR') {
                    Write-Error -Message "Network block '$CIDR' not found for tenant '$TenantName'." -ErrorId 'NetworkBlockNotFound'
                }
                continue
            }

            # Build description for confirmation
            $blockDesc = if ($block.TenantName) {
                "$($block.TenantName)/$($block.CIDR)"
            }
            else {
                $block.CIDR
            }

            # Confirm action
            if ($Force) {
                $shouldContinue = $true
            }
            else {
                $shouldContinue = $PSCmdlet.ShouldProcess($blockDesc, "Remove Network Block Assignment")
            }

            if ($shouldContinue) {
                try {
                    Write-Verbose "Removing network block '$($block.CIDR)'"
                    $response = Invoke-VergeAPI -Method DELETE -Endpoint "vnet_cidrs/$($block.Key)" -Connection $Server

                    Write-Verbose "Network block '$($block.CIDR)' removed"
                }
                catch {
                    $errorMessage = $_.Exception.Message
                    if ($errorMessage -match 'referencing') {
                        Write-Error -Message "Cannot remove network block '$($block.CIDR)': Firewall rules are referencing this block. Remove the rules first." -ErrorId 'BlockHasReferences'
                    }
                    else {
                        Write-Error -Message "Failed to remove network block '$($block.CIDR)': $errorMessage" -ErrorId 'NetworkBlockRemoveFailed'
                    }
                }
            }
        }
    }
}
