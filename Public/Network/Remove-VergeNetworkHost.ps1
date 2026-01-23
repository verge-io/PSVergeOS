function Remove-VergeNetworkHost {
    <#
    .SYNOPSIS
        Deletes a DNS/DHCP host override from a VergeOS virtual network.

    .DESCRIPTION
        Remove-VergeNetworkHost deletes one or more host overrides from a network.

    .PARAMETER Network
        The name or key of the network containing the host override.

    .PARAMETER Hostname
        The hostname of the override to delete. Supports wildcards (* and ?).

    .PARAMETER Key
        The unique key (ID) of the host override to delete.

    .PARAMETER HostObject
        A host override object from Get-VergeNetworkHost. Accepts pipeline input.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeNetworkHost -Network "Internal" -Hostname "server01"

        Deletes the host override for server01.

    .EXAMPLE
        Remove-VergeNetworkHost -Network "Internal" -Hostname "test*" -Confirm:$false

        Deletes all host overrides starting with "test" without confirmation.

    .EXAMPLE
        Get-VergeNetworkHost -Network "Internal" -IP "10.0.0.*" | Remove-VergeNetworkHost

        Deletes all host overrides in the 10.0.0.x range.

    .OUTPUTS
        None

    .NOTES
        Host override changes require DNS apply to take effect.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByHostname')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByHostname')]
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByKey')]
        [string]$Network,

        [Parameter(Mandatory, Position = 1, ParameterSetName = 'ByHostname')]
        [SupportsWildcards()]
        [string]$Hostname,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByHostObject')]
        [PSTypeName('Verge.NetworkHost')]
        [PSCustomObject]$HostObject,

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
        # Get hosts to delete
        $hostsToDelete = switch ($PSCmdlet.ParameterSetName) {
            'ByHostname' {
                Get-VergeNetworkHost -Network $Network -Hostname $Hostname -Server $Server
            }
            'ByKey' {
                Get-VergeNetworkHost -Network $Network -Key $Key -Server $Server
            }
            'ByHostObject' {
                $HostObject
            }
        }

        foreach ($targetHost in $hostsToDelete) {
            if (-not $targetHost) {
                continue
            }

            if ($PSCmdlet.ShouldProcess($targetHost.Hostname, "Remove Host Override from $($targetHost.NetworkName)")) {
                try {
                    Write-Verbose "Deleting host override '$($targetHost.Hostname)' (Key: $($targetHost.Key))"
                    $response = Invoke-VergeAPI -Method DELETE -Endpoint "vnet_hosts/$($targetHost.Key)" -Connection $Server

                    Write-Verbose "Host override '$($targetHost.Hostname)' deleted successfully"
                }
                catch {
                    Write-Error -Message "Failed to delete host override '$($targetHost.Hostname)': $($_.Exception.Message)" -ErrorId 'HostDeleteFailed'
                }
            }
        }
    }
}
