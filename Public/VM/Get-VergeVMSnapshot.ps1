function Get-VergeVMSnapshot {
    <#
    .SYNOPSIS
        Retrieves snapshots for a VergeOS virtual machine.

    .DESCRIPTION
        Get-VergeVMSnapshot retrieves snapshot information for one or more VMs,
        including snapshot name, creation date, expiration, and quiesce status.

    .PARAMETER VM
        A VM object from Get-VergeVM. Accepts pipeline input.

    .PARAMETER VMName
        The name of the VM to get snapshots for.

    .PARAMETER VMKey
        The key (ID) of the VM to get snapshots for.

    .PARAMETER Name
        Filter snapshots by name. Supports wildcards (* and ?).

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeVMSnapshot -VMName "WebServer01"

        Gets all snapshots for the VM named "WebServer01".

    .EXAMPLE
        Get-VergeVM -Name "WebServer01" | Get-VergeVMSnapshot

        Gets snapshots using pipeline input.

    .EXAMPLE
        Get-VergeVM | Get-VergeVMSnapshot | Where-Object { $_.Expires -lt (Get-Date).AddDays(1) }

        Gets all snapshots expiring within the next 24 hours.

    .EXAMPLE
        Get-VergeVMSnapshot -VMName "WebServer01" -Name "Pre-Update*"

        Gets snapshots matching the name pattern.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.VMSnapshot'

    .NOTES
        Use New-VergeVMSnapshot to create snapshots.
        Use Remove-VergeVMSnapshot to delete snapshots.
        Use Restore-VergeVMSnapshot to revert a VM to a snapshot.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByVMObject')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByVMObject')]
        [PSTypeName('Verge.VM')]
        [PSCustomObject]$VM,

        [Parameter(Mandatory, ParameterSetName = 'ByVMName')]
        [string]$VMName,

        [Parameter(Mandatory, ParameterSetName = 'ByVMKey')]
        [int]$VMKey,

        [Parameter()]
        [SupportsWildcards()]
        [string]$Name,

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
        # Resolve VM based on parameter set
        $targetVMs = switch ($PSCmdlet.ParameterSetName) {
            'ByVMName' {
                Get-VergeVM -Name $VMName -Server $Server
            }
            'ByVMKey' {
                Get-VergeVM -Key $VMKey -Server $Server
            }
            'ByVMObject' {
                $VM
            }
        }

        foreach ($targetVM in $targetVMs) {
            if (-not $targetVM -or -not $targetVM.MachineKey) {
                continue
            }

            # Build query for snapshots
            $queryParams = @{}

            # Filter by machine
            $queryParams['filter'] = "machine eq $($targetVM.MachineKey)"

            # Request snapshot fields
            $queryParams['fields'] = @(
                '$key'
                'name'
                'description'
                'created'
                'expires'
                'expires_type'
                'quiesced'
                'created_manually'
                'machine'
                'snap_machine'
            ) -join ','

            $queryParams['sort'] = '-created'

            try {
                Write-Verbose "Querying snapshots for VM '$($targetVM.Name)' (Machine: $($targetVM.MachineKey))"
                $response = Invoke-VergeAPI -Method GET -Endpoint 'machine_snapshots' -Query $queryParams -Connection $Server

                # Handle both single object and array responses
                $snapshots = if ($response -is [array]) { $response } elseif ($response) { @($response) } else { @() }

                foreach ($snapshot in $snapshots) {
                    if (-not $snapshot -or -not $snapshot.name) {
                        continue
                    }

                    # Apply name filter if specified (with wildcard support)
                    if ($Name) {
                        if ($Name -match '[\*\?]') {
                            if ($snapshot.name -notlike $Name) {
                                continue
                            }
                        }
                        elseif ($snapshot.name -ne $Name) {
                            continue
                        }
                    }

                    # Convert timestamps
                    $createdDate = if ($snapshot.created) {
                        [DateTimeOffset]::FromUnixTimeSeconds($snapshot.created).LocalDateTime
                    } else { $null }

                    $expiresDate = if ($snapshot.expires -and $snapshot.expires -gt 0) {
                        [DateTimeOffset]::FromUnixTimeSeconds($snapshot.expires).LocalDateTime
                    } else { $null }

                    # Create output object
                    $output = [PSCustomObject]@{
                        PSTypeName      = 'Verge.VMSnapshot'
                        Key             = [int]$snapshot.'$key'
                        Name            = $snapshot.name
                        Description     = $snapshot.description
                        Created         = $createdDate
                        Expires         = $expiresDate
                        ExpiresType     = $snapshot.expires_type
                        NeverExpires    = ($snapshot.expires_type -eq 'never' -or $snapshot.expires -eq 0)
                        Quiesced        = [bool]$snapshot.quiesced
                        CreatedManually = [bool]$snapshot.created_manually
                        MachineKey      = $targetVM.MachineKey
                        SnapMachineKey  = $snapshot.snap_machine
                        VMKey           = $targetVM.Key
                        VMName          = $targetVM.Name
                    }

                    # Add hidden properties for pipeline support
                    $output | Add-Member -MemberType NoteProperty -Name '_Connection' -Value $Server -Force
                    $output | Add-Member -MemberType NoteProperty -Name '_VM' -Value $targetVM -Force

                    Write-Output $output
                }
            }
            catch {
                Write-Error -Message "Failed to get snapshots for VM '$($targetVM.Name)': $($_.Exception.Message)" -ErrorId 'GetSnapshotsFailed'
            }
        }
    }
}
