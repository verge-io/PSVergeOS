function Remove-VergeWireGuardPeer {
    <#
    .SYNOPSIS
        Deletes a WireGuard VPN peer from a VergeOS WireGuard interface.

    .DESCRIPTION
        Remove-VergeWireGuardPeer deletes a peer configuration from a
        WireGuard interface.

    .PARAMETER Peer
        A WireGuard peer object from Get-VergeWireGuardPeer. Accepts pipeline input.

    .PARAMETER Key
        The unique key of the peer to delete.

    .PARAMETER Server
        The VergeOS connection to use.

    .EXAMPLE
        Get-VergeWireGuard -Network "Internal" -Name "wg0" | Get-VergeWireGuardPeer -Name "old-peer" | Remove-VergeWireGuardPeer

        Deletes the specified peer.

    .EXAMPLE
        Remove-VergeWireGuardPeer -Key 456 -Confirm:$false

        Deletes peer with key 456 without confirmation.

    .OUTPUTS
        None

    .NOTES
        Changes require network apply to take effect.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByPeer')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByPeer')]
        [PSTypeName('Verge.WireGuardPeer')]
        [PSCustomObject]$Peer,

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
        $targetKey = if ($PSCmdlet.ParameterSetName -eq 'ByPeer') {
            $Peer.Key
        }
        else {
            $Key
        }

        $displayName = if ($PSCmdlet.ParameterSetName -eq 'ByPeer') {
            "$($Peer.Name) ($($Peer.PeerIP))"
        }
        else {
            "Key $Key"
        }

        if ($PSCmdlet.ShouldProcess($displayName, "Remove WireGuard Peer")) {
            try {
                Write-Verbose "Deleting WireGuard peer '$displayName' (Key: $targetKey)"
                $response = Invoke-VergeAPI -Method DELETE -Endpoint "vnet_wireguard_peers/$targetKey" -Connection $Server

                Write-Verbose "WireGuard peer '$displayName' deleted successfully"
            }
            catch {
                Write-Error -Message "Failed to delete WireGuard peer '$displayName': $($_.Exception.Message)" -ErrorId 'WireGuardPeerDeleteFailed'
            }
        }
    }
}
