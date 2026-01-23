function Remove-VergeIPSecPolicy {
    <#
    .SYNOPSIS
        Deletes an IPSec Phase 2 policy from a VergeOS network.

    .DESCRIPTION
        Remove-VergeIPSecPolicy deletes an IPSec Phase 2 policy (traffic selector).

    .PARAMETER Policy
        An IPSec policy object from Get-VergeIPSecPolicy. Accepts pipeline input.

    .PARAMETER Key
        The unique key of the policy to delete.

    .PARAMETER Server
        The VergeOS connection to use.

    .EXAMPLE
        Get-VergeIPSecConnection -Network "External" -Name "Site-B" | Get-VergeIPSecPolicy -Name "Old-Policy" | Remove-VergeIPSecPolicy

        Deletes the specified policy.

    .EXAMPLE
        Remove-VergeIPSecPolicy -Key 456 -Confirm:$false

        Deletes policy with key 456 without confirmation.

    .OUTPUTS
        None

    .NOTES
        Changes require network apply to take effect.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByPolicy')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByPolicy')]
        [PSTypeName('Verge.IPSecPolicy')]
        [PSCustomObject]$Policy,

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
        $targetKey = if ($PSCmdlet.ParameterSetName -eq 'ByPolicy') {
            $Policy.Key
        }
        else {
            $Key
        }

        $displayName = if ($PSCmdlet.ParameterSetName -eq 'ByPolicy') {
            "$($Policy.Name) ($($Policy.LocalNetwork) -> $($Policy.RemoteNetwork))"
        }
        else {
            "Key $Key"
        }

        if ($PSCmdlet.ShouldProcess($displayName, "Remove IPSec Policy")) {
            try {
                Write-Verbose "Deleting IPSec policy '$displayName' (Key: $targetKey)"
                $response = Invoke-VergeAPI -Method DELETE -Endpoint "vnet_ipsec_phase2s/$targetKey" -Connection $Server

                Write-Verbose "IPSec policy '$displayName' deleted successfully"
            }
            catch {
                Write-Error -Message "Failed to delete IPSec policy '$displayName': $($_.Exception.Message)" -ErrorId 'IPSecPolicyDeleteFailed'
            }
        }
    }
}
