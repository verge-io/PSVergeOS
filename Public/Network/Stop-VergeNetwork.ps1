function Stop-VergeNetwork {
    <#
    .SYNOPSIS
        Powers off a VergeOS virtual network.

    .DESCRIPTION
        Stop-VergeNetwork sends a power off command to one or more virtual networks.
        The cmdlet supports pipeline input from Get-VergeNetwork for bulk operations.
        By default, uses graceful shutdown. Use -Force for immediate power off.

    .PARAMETER Name
        The name of the network to stop. Supports wildcards (* and ?).

    .PARAMETER Key
        The unique key (ID) of the network to stop.

    .PARAMETER Network
        A network object from Get-VergeNetwork. Accepts pipeline input.

    .PARAMETER Force
        Kill power immediately instead of graceful shutdown.

    .PARAMETER PassThru
        Return the network object after stopping. By default, no output is returned.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Stop-VergeNetwork -Name "Dev-Network"

        Gracefully stops the network named "Dev-Network".

    .EXAMPLE
        Stop-VergeNetwork -Name "Dev-*" -Force

        Forcefully stops all networks whose names start with "Dev-".

    .EXAMPLE
        Get-VergeNetwork -PowerState Running -Type Internal | Stop-VergeNetwork

        Gracefully stops all running internal networks.

    .OUTPUTS
        None by default. Verge.Network when -PassThru is specified.

    .NOTES
        Use Start-VergeNetwork to power on networks.
        Use Get-VergeNetwork to check the current power state.
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
        [switch]$Force,

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
        # Get networks to stop based on parameter set
        $networksToStop = switch ($PSCmdlet.ParameterSetName) {
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

        foreach ($targetNetwork in $networksToStop) {
            if (-not $targetNetwork) {
                continue
            }

            # Check if already stopped
            if ($targetNetwork.PowerState -eq 'Stopped') {
                Write-Warning "Network '$($targetNetwork.Name)' is already stopped."
                if ($PassThru) {
                    Write-Output $targetNetwork
                }
                continue
            }

            # Determine action
            $action = if ($Force) { 'killpower' } else { 'poweroff' }
            $actionDescription = if ($Force) { 'Force stop' } else { 'Stop' }

            # Build action body
            $body = @{
                vnet   = $targetNetwork.Key
                action = $action
            }

            # Confirm action
            if ($PSCmdlet.ShouldProcess($targetNetwork.Name, "$actionDescription Network")) {
                try {
                    Write-Verbose "$actionDescription network '$($targetNetwork.Name)' (Key: $($targetNetwork.Key))"
                    $response = Invoke-VergeAPI -Method POST -Endpoint 'vnet_actions' -Body $body -Connection $Server

                    Write-Verbose "Power off command sent for network '$($targetNetwork.Name)'"

                    if ($PassThru) {
                        # Return refreshed network object
                        Start-Sleep -Milliseconds 500
                        Get-VergeNetwork -Key $targetNetwork.Key -Server $Server
                    }
                }
                catch {
                    Write-Error -Message "Failed to stop network '$($targetNetwork.Name)': $($_.Exception.Message)" -ErrorId 'NetworkStopFailed'
                }
            }
        }
    }
}
