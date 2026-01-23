function Set-VergeNASService {
    <#
    .SYNOPSIS
        Modifies settings for a NAS service in VergeOS.

    .DESCRIPTION
        Set-VergeNASService modifies both the underlying VM settings (CPU cores, RAM,
        description) and NAS-specific settings (max imports, max syncs, etc.) for a
        NAS service. Some changes may require the NAS service to be restarted.

    .PARAMETER NASService
        A NAS service object from Get-VergeNASService. Accepts pipeline input.

    .PARAMETER Name
        The name of the NAS service to modify.

    .PARAMETER Key
        The unique key (ID) of the NAS service.

    .PARAMETER Description
        Set the NAS service description.

    .PARAMETER CPUCores
        Set the number of CPU cores for the NAS service VM (1-32).

    .PARAMETER MemoryGB
        Set the amount of RAM in GB for the NAS service VM (1-256).

    .PARAMETER MaxImports
        Maximum number of simultaneous import jobs (1-10).

    .PARAMETER MaxSyncs
        Maximum number of simultaneous sync jobs (1-10).

    .PARAMETER DisableSwap
        Enable or disable swap on the NAS service.

    .PARAMETER ReadAheadKB
        Read-ahead buffer size in KB. Valid values: 0 (Automatic), 64, 128, 256, 512, 1024, 2048, 4096.

    .PARAMETER PassThru
        Return the modified NAS service object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Set-VergeNASService -Name "NAS01" -CPUCores 4 -MemoryGB 8

        Increases the NAS service VM to 4 CPU cores and 8GB RAM.

    .EXAMPLE
        Set-VergeNASService -Name "NAS01" -MaxImports 5 -MaxSyncs 3

        Sets the maximum concurrent import and sync jobs.

    .EXAMPLE
        Get-VergeNASService -Name "FileServer" | Set-VergeNASService -Description "Production file server" -PassThru

        Updates the description and returns the modified NAS service.

    .EXAMPLE
        Set-VergeNASService -Name "NAS01" -DisableSwap $true -ReadAheadKB 1024

        Disables swap and sets read-ahead to 1MB.

    .OUTPUTS
        None by default. Verge.NASService when -PassThru is specified.

    .NOTES
        Changes to CPU and RAM settings require the NAS service to be powered off
        or restarted to take effect. Use Restart-VergeVM -Key <VMKey> after making
        changes that require a restart.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [PSTypeName('Verge.NASService')]
        [PSCustomObject]$NASService,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter()]
        [ValidateLength(0, 2048)]
        [string]$Description,

        [Parameter()]
        [ValidateRange(1, 32)]
        [int]$CPUCores,

        [Parameter()]
        [ValidateRange(1, 256)]
        [int]$MemoryGB,

        [Parameter()]
        [ValidateRange(1, 10)]
        [int]$MaxImports,

        [Parameter()]
        [ValidateRange(1, 10)]
        [int]$MaxSyncs,

        [Parameter()]
        [bool]$DisableSwap,

        [Parameter()]
        [ValidateSet(0, 64, 128, 256, 512, 1024, 2048, 4096)]
        [int]$ReadAheadKB,

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
                continue
            }

            # Build the VM update body (for CPU, RAM, Description)
            $vmBody = @{}
            $vmChanges = @()

            # Build the NAS service update body (for MaxImports, MaxSyncs, etc.)
            $serviceBody = @{}
            $serviceChanges = @()

            # VM-level settings
            if ($PSBoundParameters.ContainsKey('Description')) {
                $vmBody['description'] = $Description
                $vmChanges += "Description updated"
            }

            if ($PSBoundParameters.ContainsKey('CPUCores')) {
                $vmBody['cpu_cores'] = $CPUCores
                $vmChanges += "CPUCores: $($service.VMCores) -> $CPUCores"
            }

            if ($PSBoundParameters.ContainsKey('MemoryGB')) {
                # Convert GB to MB for the API (API expects MB in the machine, but bytes in display)
                $ramMB = $MemoryGB * 1024
                $vmBody['ram'] = $ramMB
                $vmChanges += "Memory: $($service.VMRAMGB)GB -> ${MemoryGB}GB"
            }

            # NAS service-level settings
            if ($PSBoundParameters.ContainsKey('MaxImports')) {
                $serviceBody['max_imports'] = $MaxImports
                $serviceChanges += "MaxImports: $($service.MaxImports) -> $MaxImports"
            }

            if ($PSBoundParameters.ContainsKey('MaxSyncs')) {
                $serviceBody['max_syncs'] = $MaxSyncs
                $serviceChanges += "MaxSyncs: $($service.MaxSyncs) -> $MaxSyncs"
            }

            if ($PSBoundParameters.ContainsKey('DisableSwap')) {
                $serviceBody['disable_swap'] = $DisableSwap
                $serviceChanges += "DisableSwap=$DisableSwap"
            }

            if ($PSBoundParameters.ContainsKey('ReadAheadKB')) {
                $serviceBody['read_ahead_kb_default'] = $ReadAheadKB
                $readAheadDisplay = if ($ReadAheadKB -eq 0) { 'Automatic' } else { "${ReadAheadKB}KB" }
                $serviceChanges += "ReadAheadKB=$readAheadDisplay"
            }

            # Check if there are any changes
            if ($vmBody.Count -eq 0 -and $serviceBody.Count -eq 0) {
                Write-Warning "No changes specified for NAS service '$($service.Name)'."
                continue
            }

            $allChanges = $vmChanges + $serviceChanges
            $changeDescription = $allChanges -join ', '

            # Confirm action
            if ($PSCmdlet.ShouldProcess($service.Name, "Modify NAS service ($changeDescription)")) {
                $vmUpdateSuccess = $true
                $serviceUpdateSuccess = $true

                # Update VM settings if any
                if ($vmBody.Count -gt 0) {
                    try {
                        Write-Verbose "Updating VM settings for NAS service '$($service.Name)' (VM Key: $($service.VMKey))"
                        $response = Invoke-VergeAPI -Method PUT -Endpoint "vms/$($service.VMKey)" -Body $vmBody -Connection $Server
                        Write-Verbose "VM settings updated successfully"

                        # Warn if CPU/RAM changes need restart
                        if ($vmBody.ContainsKey('cpu_cores') -or $vmBody.ContainsKey('ram')) {
                            if ($service.IsRunning) {
                                Write-Warning "NAS service '$($service.Name)' must be restarted for CPU/RAM changes to take effect."
                            }
                        }
                    }
                    catch {
                        $vmUpdateSuccess = $false
                        Write-Error -Message "Failed to update VM settings for NAS service '$($service.Name)': $($_.Exception.Message)" -ErrorId 'SetVMSettingsFailed'
                    }
                }

                # Update NAS service settings if any
                if ($serviceBody.Count -gt 0) {
                    try {
                        Write-Verbose "Updating NAS service settings for '$($service.Name)'"
                        $response = Invoke-VergeAPI -Method PUT -Endpoint "vm_services/$($service.Key)" -Body $serviceBody -Connection $Server
                        Write-Verbose "NAS service settings updated successfully"
                    }
                    catch {
                        $serviceUpdateSuccess = $false
                        Write-Error -Message "Failed to update NAS service settings for '$($service.Name)': $($_.Exception.Message)" -ErrorId 'SetNASServiceSettingsFailed'
                    }
                }

                if ($PassThru -and ($vmUpdateSuccess -or $serviceUpdateSuccess)) {
                    Start-Sleep -Milliseconds 500
                    Get-VergeNASService -Key $service.Key -Server $Server
                }
            }
        }
    }
}
