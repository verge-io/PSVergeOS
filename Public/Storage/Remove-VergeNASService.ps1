function Remove-VergeNASService {
    <#
    .SYNOPSIS
        Removes a NAS service VM from VergeOS.

    .DESCRIPTION
        Remove-VergeNASService removes a NAS service VM and its associated configuration.
        The NAS service must be stopped before removal. If the service has volumes,
        they must be removed first unless -Force is specified.

    .PARAMETER Name
        The name of the NAS service to remove.

    .PARAMETER Key
        The unique key (ID) of the NAS service to remove.

    .PARAMETER NASService
        A NAS service object from Get-VergeNASService. Accepts pipeline input.

    .PARAMETER Force
        Remove the NAS service even if it has volumes. This will also remove all
        associated volumes and data. Use with caution.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeNASService -Name "NAS01"

        Removes the NAS service named "NAS01" after confirmation.

    .EXAMPLE
        Get-VergeNASService -Name "pstest-*" | Remove-VergeNASService -Force

        Removes all NAS services matching "pstest-*" including their volumes.

    .EXAMPLE
        Remove-VergeNASService -Key 5 -WhatIf

        Shows what would happen if the NAS service with key 5 were removed.

    .OUTPUTS
        None.

    .NOTES
        The NAS service VM must be stopped before removal. Use Stop-VergeVM first
        if the service is running. Removing a NAS service also removes its
        vm_services entry and any orphaned volumes.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [PSTypeName('Verge.NASService')]
        [PSCustomObject]$NASService,

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
        # Resolve NAS service based on parameter set
        $targetServices = switch ($PSCmdlet.ParameterSetName) {
            'ByName' {
                Get-VergeNASService -Name $Name -Server $Server
            }
            'ByKey' {
                Get-VergeNASService -Key $Key -Server $Server
            }
            'ByObject' {
                $NASService
            }
        }

        foreach ($service in $targetServices) {
            if (-not $service) {
                if ($PSCmdlet.ParameterSetName -eq 'ByName') {
                    Write-Error -Message "NAS service '$Name' not found." -ErrorId 'NASServiceNotFound'
                }
                elseif ($PSCmdlet.ParameterSetName -eq 'ByKey') {
                    Write-Error -Message "NAS service with key '$Key' not found." -ErrorId 'NASServiceNotFound'
                }
                continue
            }

            # Check if service has volumes
            if ($service.VolumeCount -gt 0 -and -not $Force) {
                Write-Error -Message "Cannot remove NAS service '$($service.Name)': Service has $($service.VolumeCount) volume(s). Remove volumes first or use -Force to remove everything." -ErrorId 'ServiceHasVolumes'
                continue
            }

            # Check if service is running
            if ($service.IsRunning) {
                Write-Error -Message "Cannot remove NAS service '$($service.Name)': Service VM is running. Use Stop-VergeVM to stop it first." -ErrorId 'ServiceRunning'
                continue
            }

            # Build confirmation message
            $confirmMessage = "Remove NAS service"
            if ($service.VolumeCount -gt 0) {
                $confirmMessage += " and $($service.VolumeCount) volume(s)"
            }

            # Confirm action - Force bypasses ShouldProcess for High impact
            $shouldRemove = if ($Force) {
                $true
            } else {
                $PSCmdlet.ShouldProcess($service.Name, $confirmMessage)
            }

            if ($shouldRemove) {
                try {
                    # If Force and there are volumes, warn about data loss
                    if ($Force -and $service.VolumeCount -gt 0) {
                        Write-Warning "Removing NAS service '$($service.Name)' with $($service.VolumeCount) volume(s). All data will be lost."
                    }

                    Write-Verbose "Removing NAS service VM '$($service.Name)' (VM Key: $($service.VMKey))"

                    # Delete the VM - this cascades to recipe instance and vm_services
                    $response = Invoke-VergeAPI -Method DELETE -Endpoint "vms/$($service.VMKey)" -Connection $Server

                    Write-Verbose "NAS service '$($service.Name)' removed successfully"
                }
                catch {
                    $errorMessage = $_.Exception.Message
                    if ($errorMessage -match 'running') {
                        Write-Error -Message "Cannot remove NAS service '$($service.Name)': Service VM is still running. Use Stop-VergeVM first." -ErrorId 'VMRunning'
                    }
                    elseif ($errorMessage -match 'volumes') {
                        Write-Error -Message "Cannot remove NAS service '$($service.Name)': Service has associated volumes. Remove volumes first or use -Force." -ErrorId 'HasVolumes'
                    }
                    else {
                        Write-Error -Message "Failed to remove NAS service '$($service.Name)': $errorMessage" -ErrorId 'NASServiceRemoveFailed'
                    }
                }
            }
        }
    }
}
