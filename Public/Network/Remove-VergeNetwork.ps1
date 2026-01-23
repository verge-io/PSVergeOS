function Remove-VergeNetwork {
    <#
    .SYNOPSIS
        Deletes a VergeOS virtual network.

    .DESCRIPTION
        Remove-VergeNetwork deletes one or more virtual networks from VergeOS.
        The network must be powered off before it can be deleted.
        The cmdlet supports pipeline input from Get-VergeNetwork for bulk operations.

    .PARAMETER Name
        The name of the network to delete. Supports wildcards (* and ?).

    .PARAMETER Key
        The unique key (ID) of the network to delete.

    .PARAMETER Network
        A network object from Get-VergeNetwork. Accepts pipeline input.

    .PARAMETER Force
        Force deletion by powering off the network if it is running.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeNetwork -Name "Test-Network"

        Deletes the network named "Test-Network" after confirmation.

    .EXAMPLE
        Remove-VergeNetwork -Name "Test-Network" -Confirm:$false

        Deletes the network without confirmation prompt.

    .EXAMPLE
        Get-VergeNetwork -Name "Temp-*" | Remove-VergeNetwork -Force

        Deletes all networks starting with "Temp-", forcefully stopping any that are running.

    .OUTPUTS
        None

    .NOTES
        Networks must be powered off before deletion unless -Force is specified.
        Networks with attached NICs or other dependencies cannot be deleted.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByName')]
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
        # Get networks to delete based on parameter set
        $networksToDelete = switch ($PSCmdlet.ParameterSetName) {
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

        foreach ($targetNetwork in $networksToDelete) {
            if (-not $targetNetwork) {
                continue
            }

            # Safety check - don't allow deletion of Physical or Core networks
            if ($targetNetwork.TypeRaw -in @('physical', 'core')) {
                Write-Error -Message "Cannot delete $($targetNetwork.Type) network '$($targetNetwork.Name)'. System networks cannot be removed." -ErrorId 'CannotDeleteSystemNetwork'
                continue
            }

            # Check if network is running
            if ($targetNetwork.PowerState -ne 'Stopped') {
                if ($Force) {
                    Write-Verbose "Network '$($targetNetwork.Name)' is running. Stopping due to -Force..."
                    try {
                        $stopBody = @{
                            vnet   = $targetNetwork.Key
                            action = 'poweroff'
                        }
                        Invoke-VergeAPI -Method POST -Endpoint 'vnet_actions' -Body $stopBody -Connection $Server | Out-Null

                        # Wait for network to stop
                        $maxWait = 30
                        $waited = 0
                        do {
                            Start-Sleep -Seconds 1
                            $waited++
                            $checkNetwork = Get-VergeNetwork -Key $targetNetwork.Key -Server $Server
                        } while ($checkNetwork.PowerState -ne 'Stopped' -and $waited -lt $maxWait)

                        if ($checkNetwork.PowerState -ne 'Stopped') {
                            Write-Error -Message "Failed to stop network '$($targetNetwork.Name)' within $maxWait seconds" -ErrorId 'NetworkStopTimeout'
                            continue
                        }
                    }
                    catch {
                        Write-Error -Message "Failed to stop network '$($targetNetwork.Name)': $($_.Exception.Message)" -ErrorId 'NetworkStopFailed'
                        continue
                    }
                }
                else {
                    Write-Error -Message "Network '$($targetNetwork.Name)' is $($targetNetwork.PowerState). Stop the network first or use -Force." -ErrorId 'NetworkNotStopped'
                    continue
                }
            }

            # Confirm deletion
            if ($PSCmdlet.ShouldProcess($targetNetwork.Name, 'Remove Network')) {
                try {
                    Write-Verbose "Deleting network '$($targetNetwork.Name)' (Key: $($targetNetwork.Key))"
                    $response = Invoke-VergeAPI -Method DELETE -Endpoint "vnets/$($targetNetwork.Key)" -Connection $Server

                    Write-Verbose "Network '$($targetNetwork.Name)' deleted successfully"
                }
                catch {
                    $errorMessage = $_.Exception.Message
                    if ($errorMessage -match 'Machine NICs are attached') {
                        Write-Error -Message "Cannot delete network '$($targetNetwork.Name)': VMs have NICs attached to this network. Remove the NICs first." -ErrorId 'NetworkHasAttachedNICs'
                    }
                    elseif ($errorMessage -match 'referencing') {
                        Write-Error -Message "Cannot delete network '$($targetNetwork.Name)': Other resources reference this network. $errorMessage" -ErrorId 'NetworkHasReferences'
                    }
                    else {
                        Write-Error -Message "Failed to delete network '$($targetNetwork.Name)': $errorMessage" -ErrorId 'NetworkDeleteFailed'
                    }
                }
            }
        }
    }
}
