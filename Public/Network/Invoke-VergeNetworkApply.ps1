function Invoke-VergeNetworkApply {
    <#
    .SYNOPSIS
        Applies pending firewall rules to a VergeOS virtual network.

    .DESCRIPTION
        Invoke-VergeNetworkApply sends the apply command to reload and activate
        any pending firewall rule changes on a network. This is required after
        creating, modifying, or deleting rules.

    .PARAMETER Network
        The name or key of the network to apply rules on.

    .PARAMETER NetworkObject
        A network object from Get-VergeNetwork. Accepts pipeline input.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Invoke-VergeNetworkApply -Network "External"

        Applies pending rules on the External network.

    .EXAMPLE
        Get-VergeNetwork -Name "External" | Invoke-VergeNetworkApply

        Applies rules using pipeline input.

    .EXAMPLE
        Get-VergeNetwork | Where-Object { $_.NeedFWApply } | Invoke-VergeNetworkApply

        Applies rules on all networks that have pending changes.

    .OUTPUTS
        None

    .NOTES
        Rule changes are not active until this cmdlet is called.
        The network must be running for rules to be applied.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByNetworkName')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByNetworkName')]
        [string]$Network,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByNetworkObject')]
        [PSTypeName('Verge.Network')]
        [PSCustomObject]$NetworkObject,

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
        # Resolve network
        $targetNetwork = $null
        if ($PSCmdlet.ParameterSetName -eq 'ByNetworkObject') {
            $targetNetwork = $NetworkObject
        }
        else {
            if ($Network -match '^\d+$') {
                $targetNetwork = Get-VergeNetwork -Key ([int]$Network) -Server $Server
            }
            else {
                $targetNetwork = Get-VergeNetwork -Name $Network -Server $Server
            }
        }

        if (-not $targetNetwork) {
            Write-Error -Message "Network '$Network' not found" -ErrorId 'NetworkNotFound'
            return
        }

        # Check if network is running
        if ($targetNetwork.PowerState -ne 'Running') {
            Write-Warning "Network '$($targetNetwork.Name)' is not running. Rules will be applied when the network starts."
        }

        if ($PSCmdlet.ShouldProcess($targetNetwork.Name, 'Apply Firewall Rules')) {
            try {
                Write-Verbose "Applying rules on network '$($targetNetwork.Name)' (Key: $($targetNetwork.Key))"
                $response = Invoke-VergeAPI -Method PUT -Endpoint "vnets/$($targetNetwork.Key)/apply" -Connection $Server

                Write-Verbose "Rules applied successfully on network '$($targetNetwork.Name)'"
            }
            catch {
                Write-Error -Message "Failed to apply rules on network '$($targetNetwork.Name)': $($_.Exception.Message)" -ErrorId 'RuleApplyFailed'
            }
        }
    }
}
