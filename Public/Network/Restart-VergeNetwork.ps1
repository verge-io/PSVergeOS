function Restart-VergeNetwork {
    <#
    .SYNOPSIS
        Restarts a VergeOS virtual network.

    .DESCRIPTION
        Restart-VergeNetwork sends a reset command to one or more virtual networks.
        The cmdlet supports pipeline input from Get-VergeNetwork for bulk operations.

    .PARAMETER Name
        The name of the network to restart. Supports wildcards (* and ?).

    .PARAMETER Key
        The unique key (ID) of the network to restart.

    .PARAMETER Network
        A network object from Get-VergeNetwork. Accepts pipeline input.

    .PARAMETER ApplyRules
        Apply firewall rules after restarting. Default is $true.

    .PARAMETER PassThru
        Return the network object after restarting. By default, no output is returned.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Restart-VergeNetwork -Name "Dev-Network"

        Restarts the network named "Dev-Network".

    .EXAMPLE
        Get-VergeNetwork -Name "Prod-*" -PowerState Running | Restart-VergeNetwork

        Restarts all running networks whose names start with "Prod-".

    .EXAMPLE
        Restart-VergeNetwork -Name "Web-DMZ" -ApplyRules:$false

        Restarts the network without applying firewall rules.

    .OUTPUTS
        None by default. Verge.Network when -PassThru is specified.

    .NOTES
        Use Start-VergeNetwork and Stop-VergeNetwork for individual power operations.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [SupportsWildcards()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByNetwork')]
        [PSTypeName('Verge.Network')]
        [PSCustomObject]$Network,

        [Parameter()]
        [bool]$ApplyRules = $true,

        [Parameter()]
        [switch]$PassThru,

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
        # Get networks to restart based on parameter set
        $networksToRestart = switch ($PSCmdlet.ParameterSetName) {
            'ByName' {
                Get-VergeNetwork -Name $Name -Server $Server
            }
            'ByKey' {
                Get-VergeNetwork -Key $Key -Server $Server
            }
            'ByNetwork' {
                $Network
            }
        }

        foreach ($targetNetwork in $networksToRestart) {
            if (-not $targetNetwork) {
                continue
            }

            # Build action body
            $body = @{
                vnet   = $targetNetwork.Key
                action = 'reset'
                params = @{
                    apply = $ApplyRules
                }
            }

            # Confirm action
            if ($PSCmdlet.ShouldProcess($targetNetwork.Name, 'Restart Network')) {
                try {
                    Write-Verbose "Restarting network '$($targetNetwork.Name)' (Key: $($targetNetwork.Key))"
                    $response = Invoke-VergeAPI -Method POST -Endpoint 'vnet_actions' -Body $body -Connection $Server

                    Write-Verbose "Reset command sent for network '$($targetNetwork.Name)'"

                    if ($PassThru) {
                        # Return refreshed network object
                        Start-Sleep -Milliseconds 1000
                        Get-VergeNetwork -Key $targetNetwork.Key -Server $Server
                    }
                }
                catch {
                    Write-Error -Message "Failed to restart network '$($targetNetwork.Name)': $($_.Exception.Message)" -ErrorId 'NetworkRestartFailed'
                }
            }
        }
    }
}
