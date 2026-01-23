function Start-VergeNetwork {
    <#
    .SYNOPSIS
        Powers on a VergeOS virtual network.

    .DESCRIPTION
        Start-VergeNetwork sends a power on command to one or more virtual networks.
        The cmdlet supports pipeline input from Get-VergeNetwork for bulk operations.

    .PARAMETER Name
        The name of the network to start. Supports wildcards (* and ?).

    .PARAMETER Key
        The unique key (ID) of the network to start.

    .PARAMETER Network
        A network object from Get-VergeNetwork. Accepts pipeline input.

    .PARAMETER ApplyRules
        Apply firewall rules after starting. Default is $true.

    .PARAMETER PreferredNode
        Optionally specify a preferred node to start the network on.

    .PARAMETER PassThru
        Return the network object after starting. By default, no output is returned.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Start-VergeNetwork -Name "Dev-Network"

        Starts the network named "Dev-Network".

    .EXAMPLE
        Start-VergeNetwork -Name "Dev-*"

        Starts all networks whose names start with "Dev-".

    .EXAMPLE
        Get-VergeNetwork -PowerState Stopped -Type Internal | Start-VergeNetwork

        Starts all stopped internal networks.

    .EXAMPLE
        Start-VergeNetwork -Name "Web-DMZ" -ApplyRules:$false

        Starts the network without applying firewall rules.

    .OUTPUTS
        None by default. Verge.Network when -PassThru is specified.

    .NOTES
        Use Stop-VergeNetwork to power off networks.
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
        [bool]$ApplyRules = $true,

        [Parameter()]
        [int]$PreferredNode,

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
        # Get networks to start based on parameter set
        $networksToStart = switch ($PSCmdlet.ParameterSetName) {
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

        foreach ($targetNetwork in $networksToStart) {
            if (-not $targetNetwork) {
                continue
            }

            # Check if already running
            if ($targetNetwork.PowerState -eq 'Running') {
                Write-Warning "Network '$($targetNetwork.Name)' is already running."
                if ($PassThru) {
                    Write-Output $targetNetwork
                }
                continue
            }

            # Build action body
            $body = @{
                vnet   = $targetNetwork.Key
                action = 'poweron'
                params = @{
                    apply = $ApplyRules
                }
            }

            # Add preferred node if specified
            if ($PSBoundParameters.ContainsKey('PreferredNode')) {
                $body['params']['preferred_node'] = $PreferredNode
            }

            # Confirm action
            if ($PSCmdlet.ShouldProcess($targetNetwork.Name, 'Start Network')) {
                try {
                    Write-Verbose "Starting network '$($targetNetwork.Name)' (Key: $($targetNetwork.Key))"
                    $response = Invoke-VergeAPI -Method POST -Endpoint 'vnet_actions' -Body $body -Connection $Server

                    Write-Verbose "Power on command sent for network '$($targetNetwork.Name)'"

                    if ($PassThru) {
                        # Return refreshed network object
                        Start-Sleep -Milliseconds 500
                        Get-VergeNetwork -Key $targetNetwork.Key -Server $Server
                    }
                }
                catch {
                    Write-Error -Message "Failed to start network '$($targetNetwork.Name)': $($_.Exception.Message)" -ErrorId 'NetworkStartFailed'
                }
            }
        }
    }
}
