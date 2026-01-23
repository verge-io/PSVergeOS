function Remove-VergeIPSecConnection {
    <#
    .SYNOPSIS
        Deletes an IPSec VPN connection from a VergeOS network.

    .DESCRIPTION
        Remove-VergeIPSecConnection deletes an IPSec Phase 1 (IKE) VPN connection.
        This also removes all associated Phase 2 policies.

    .PARAMETER Connection
        An IPSec connection object from Get-VergeIPSecConnection. Accepts pipeline input.

    .PARAMETER Key
        The unique key of the connection to delete.

    .PARAMETER Server
        The VergeOS connection to use.

    .EXAMPLE
        Get-VergeIPSecConnection -Network "External" -Name "Old-Site" | Remove-VergeIPSecConnection

        Deletes the Old-Site IPSec connection.

    .EXAMPLE
        Remove-VergeIPSecConnection -Key 123 -Confirm:$false

        Deletes connection with key 123 without confirmation.

    .OUTPUTS
        None

    .NOTES
        Deleting a connection also removes all Phase 2 policies.
        Changes require network apply to take effect.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByConnection')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByConnection')]
        [PSTypeName('Verge.IPSecConnection')]
        [PSCustomObject]$Connection,

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
        $targetKey = if ($PSCmdlet.ParameterSetName -eq 'ByConnection') {
            $Connection.Key
        }
        else {
            $Key
        }

        $displayName = if ($PSCmdlet.ParameterSetName -eq 'ByConnection') {
            "$($Connection.Name) to $($Connection.RemoteGateway)"
        }
        else {
            "Key $Key"
        }

        if ($PSCmdlet.ShouldProcess($displayName, "Remove IPSec Connection")) {
            try {
                Write-Verbose "Deleting IPSec connection '$displayName' (Key: $targetKey)"
                $response = Invoke-VergeAPI -Method DELETE -Endpoint "vnet_ipsec_phase1s/$targetKey" -Connection $Server

                Write-Verbose "IPSec connection '$displayName' deleted successfully"
            }
            catch {
                Write-Error -Message "Failed to delete IPSec connection '$displayName': $($_.Exception.Message)" -ErrorId 'IPSecDeleteFailed'
            }
        }
    }
}
