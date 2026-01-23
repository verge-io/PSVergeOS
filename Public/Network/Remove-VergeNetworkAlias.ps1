function Remove-VergeNetworkAlias {
    <#
    .SYNOPSIS
        Deletes an IP alias from a VergeOS virtual network.

    .DESCRIPTION
        Remove-VergeNetworkAlias deletes one or more IP aliases from a network.

    .PARAMETER Network
        The name or key of the network containing the alias.

    .PARAMETER IP
        The IP address of the alias to delete. Supports wildcards (* and ?).

    .PARAMETER Name
        The name/hostname of the alias to delete. Supports wildcards (* and ?).

    .PARAMETER Key
        The unique key (ID) of the alias to delete.

    .PARAMETER AliasObject
        An alias object from Get-VergeNetworkAlias. Accepts pipeline input.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeNetworkAlias -Network "External" -Name "webserver"

        Deletes the IP alias named "webserver".

    .EXAMPLE
        Remove-VergeNetworkAlias -Network "External" -IP "10.0.0.100" -Confirm:$false

        Deletes the alias for 10.0.0.100 without confirmation.

    .EXAMPLE
        Get-VergeNetworkAlias -Network "External" -Name "test*" | Remove-VergeNetworkAlias

        Deletes all aliases starting with "test".

    .OUTPUTS
        None

    .NOTES
        Aliases referenced by firewall rules cannot be deleted until the rules are removed.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByIP')]
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByKey')]
        [string]$Network,

        [Parameter(Mandatory, Position = 1, ParameterSetName = 'ByIP')]
        [SupportsWildcards()]
        [string]$IP,

        [Parameter(Mandatory, Position = 1, ParameterSetName = 'ByName')]
        [SupportsWildcards()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByAliasObject')]
        [PSTypeName('Verge.NetworkAlias')]
        [PSCustomObject]$AliasObject,

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
        # Get aliases to delete
        $aliasesToDelete = switch ($PSCmdlet.ParameterSetName) {
            'ByName' {
                Get-VergeNetworkAlias -Network $Network -Hostname $Name -Server $Server
            }
            'ByIP' {
                Get-VergeNetworkAlias -Network $Network -IP $IP -Server $Server
            }
            'ByKey' {
                Get-VergeNetworkAlias -Network $Network -Key $Key -Server $Server
            }
            'ByAliasObject' {
                $AliasObject
            }
        }

        foreach ($alias in $aliasesToDelete) {
            if (-not $alias) {
                continue
            }

            $displayName = if ($alias.Name) { "$($alias.Name) ($($alias.IP))" } else { $alias.IP }

            if ($PSCmdlet.ShouldProcess($displayName, "Remove IP Alias from $($alias.NetworkName)")) {
                try {
                    Write-Verbose "Deleting IP alias '$displayName' (Key: $($alias.Key))"
                    $response = Invoke-VergeAPI -Method DELETE -Endpoint "vnet_addresses/$($alias.Key)" -Connection $Server

                    Write-Verbose "IP alias '$displayName' deleted successfully"
                }
                catch {
                    $errorMessage = $_.Exception.Message
                    if ($errorMessage -match 'referencing') {
                        Write-Error -Message "Cannot delete IP alias '$displayName': It is referenced by firewall rules. Remove the rules first." -ErrorId 'AliasInUse'
                    }
                    else {
                        Write-Error -Message "Failed to delete IP alias '$displayName': $errorMessage" -ErrorId 'AliasDeleteFailed'
                    }
                }
            }
        }
    }
}
