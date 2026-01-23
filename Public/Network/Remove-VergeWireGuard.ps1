function Remove-VergeWireGuard {
    <#
    .SYNOPSIS
        Deletes a WireGuard VPN interface from a VergeOS network.

    .DESCRIPTION
        Remove-VergeWireGuard deletes a WireGuard VPN interface.
        This also removes all associated peers.

    .PARAMETER WireGuard
        A WireGuard interface object from Get-VergeWireGuard. Accepts pipeline input.

    .PARAMETER Key
        The unique key of the interface to delete.

    .PARAMETER Server
        The VergeOS connection to use.

    .EXAMPLE
        Get-VergeWireGuard -Network "Internal" -Name "wg-old" | Remove-VergeWireGuard

        Deletes the wg-old WireGuard interface.

    .EXAMPLE
        Remove-VergeWireGuard -Key 123 -Confirm:$false

        Deletes interface with key 123 without confirmation.

    .OUTPUTS
        None

    .NOTES
        Deleting an interface also removes all associated peers.
        Changes require network apply to take effect.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByWireGuard')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByWireGuard')]
        [PSTypeName('Verge.WireGuard')]
        [PSCustomObject]$WireGuard,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

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
        # Get target
        $targetKey = if ($PSCmdlet.ParameterSetName -eq 'ByWireGuard') {
            $WireGuard.Key
        }
        else {
            $Key
        }

        $displayName = if ($PSCmdlet.ParameterSetName -eq 'ByWireGuard') {
            "$($WireGuard.Name) ($($WireGuard.CIDR))"
        }
        else {
            "Key $Key"
        }

        if ($PSCmdlet.ShouldProcess($displayName, "Remove WireGuard Interface")) {
            try {
                Write-Verbose "Deleting WireGuard interface '$displayName' (Key: $targetKey)"
                $response = Invoke-VergeAPI -Method DELETE -Endpoint "vnet_wireguards/$targetKey" -Connection $Server

                Write-Verbose "WireGuard interface '$displayName' deleted successfully"
            }
            catch {
                Write-Error -Message "Failed to delete WireGuard interface '$displayName': $($_.Exception.Message)" -ErrorId 'WireGuardDeleteFailed'
            }
        }
    }
}
