function Get-VergeCloudSnapshot {
    <#
    .SYNOPSIS
        Retrieves cloud (system) snapshots from VergeOS.

    .DESCRIPTION
        Get-VergeCloudSnapshot retrieves cloud snapshot information from a VergeOS system.
        Cloud snapshots (also known as system snapshots) capture the entire system state
        including all VMs and tenants at a point in time.

    .PARAMETER Name
        Filter by snapshot name. Supports wildcards (* and ?).

    .PARAMETER Key
        Get a specific cloud snapshot by its key (ID).

    .PARAMETER IncludeExpired
        Include snapshots that have already expired (default excludes expired).

    .PARAMETER IncludeVMs
        Include the list of VMs contained in the snapshot.

    .PARAMETER IncludeTenants
        Include the list of tenants contained in the snapshot.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeCloudSnapshot

        Gets all cloud snapshots that haven't expired.

    .EXAMPLE
        Get-VergeCloudSnapshot -Name "Daily*"

        Gets cloud snapshots with names starting with "Daily".

    .EXAMPLE
        Get-VergeCloudSnapshot -IncludeVMs -IncludeTenants

        Gets all cloud snapshots including their VM and tenant contents.

    .EXAMPLE
        Get-VergeCloudSnapshot -Key 5 -IncludeVMs

        Gets a specific cloud snapshot and lists the VMs it contains.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.CloudSnapshot'

    .NOTES
        Cloud snapshots differ from VM snapshots in that they capture the entire
        system state rather than individual VMs.

        Use New-VergeCloudSnapshot to create a new cloud snapshot.
        Use Restore-VergeVMFromCloudSnapshot to recover a VM from a cloud snapshot.
        Use Restore-VergeTenantFromCloudSnapshot to recover a tenant from a cloud snapshot.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ParameterSetName = 'List')]
        [SupportsWildcards()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter()]
        [switch]$IncludeExpired,

        [Parameter()]
        [switch]$IncludeVMs,

        [Parameter()]
        [switch]$IncludeTenants,

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
        # Build query parameters
        $queryParams = @{}
        $queryParams['fields'] = @(
            '$key'
            'name'
            'description'
            'created'
            'expires'
            'expires_type'
            'snapshot_profile'
            'private'
            'remote_sync'
            'immutable'
            'immutable_status'
            'immutable_lock_expires'
            'status'
            'status_info'
        ) -join ','

        # Build filters
        $filters = @()

        # Handle specific key lookup
        if ($PSCmdlet.ParameterSetName -eq 'ByKey') {
            $filters += "`$key eq $Key"
        }
        elseif ($Name -and $Name -notmatch '[\*\?]') {
            # Exact name match
            $filters += "name eq '$Name'"
        }

        # Exclude expired snapshots unless IncludeExpired is specified
        if (-not $IncludeExpired) {
            $now = [int][DateTimeOffset]::Now.ToUnixTimeSeconds()
            $filters += "(expires eq 0 or expires gt $now)"
        }

        if ($filters.Count -gt 0) {
            $queryParams['filter'] = $filters -join ' and '
        }

        $queryParams['sort'] = '-created'

        try {
            Write-Verbose "Querying cloud snapshots from VergeOS"
            $response = Invoke-VergeAPI -Method GET -Endpoint 'cloud_snapshots' -Query $queryParams -Connection $Server

            # Handle both single object and array responses
            $snapshots = if ($response -is [array]) { $response } elseif ($response) { @($response) } else { @() }

            foreach ($snapshot in $snapshots) {
                if (-not $snapshot -or -not $snapshot.name) {
                    continue
                }

                # Apply wildcard filter if specified
                if ($Name -and $Name -match '[\*\?]') {
                    if ($snapshot.name -notlike $Name) {
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

                $immutableLockExpires = if ($snapshot.immutable_lock_expires -and $snapshot.immutable_lock_expires -gt 0) {
                    [DateTimeOffset]::FromUnixTimeSeconds($snapshot.immutable_lock_expires).LocalDateTime
                } else { $null }

                # Get snapshot profile name if linked
                $profileName = $null
                if ($snapshot.snapshot_profile) {
                    try {
                        $profileObj = Get-VergeSnapshotProfile -Key $snapshot.snapshot_profile -Server $Server
                        $profileName = $profileObj.Name
                    } catch {
                        Write-Verbose "Could not retrieve snapshot profile name: $($_.Exception.Message)"
                    }
                }

                # Create output object
                $output = [PSCustomObject]@{
                    PSTypeName          = 'Verge.CloudSnapshot'
                    Key                 = [int]$snapshot.'$key'
                    Name                = $snapshot.name
                    Description         = $snapshot.description
                    Created             = $createdDate
                    Expires             = $expiresDate
                    ExpiresType         = $snapshot.expires_type
                    NeverExpires        = ($snapshot.expires_type -eq 'never' -or $snapshot.expires -eq 0)
                    SnapshotProfileKey  = $snapshot.snapshot_profile
                    SnapshotProfileName = $profileName
                    Private             = [bool]$snapshot.private
                    RemoteSync          = [bool]$snapshot.remote_sync
                    Immutable           = [bool]$snapshot.immutable
                    ImmutableStatus     = $snapshot.immutable_status
                    ImmutableLockExpires = $immutableLockExpires
                    Status              = $snapshot.status
                    StatusInfo          = $snapshot.status_info
                }

                # Get VMs if requested
                if ($IncludeVMs) {
                    $vms = @()
                    try {
                        $vmParams = @{
                            'fields' = @(
                                '$key'
                                'name'
                                'description'
                                'uuid'
                                'machine_uuid'
                                'cpu_cores'
                                'ram'
                                'os_family'
                                'is_snapshot'
                                'status'
                                'status_info'
                                'original_key'
                            ) -join ','
                            'filter' = "cloud_snapshot eq $($snapshot.'$key')"
                            'sort' = '+name'
                        }
                        $vmResponse = Invoke-VergeAPI -Method GET -Endpoint 'cloud_snapshot_vms' -Query $vmParams -Connection $Server
                        $vmList = if ($vmResponse -is [array]) { $vmResponse } elseif ($vmResponse) { @($vmResponse) } else { @() }

                        foreach ($vm in $vmList) {
                            if (-not $vm) { continue }
                            $vmObj = [PSCustomObject]@{
                                PSTypeName   = 'Verge.CloudSnapshotVM'
                                Key          = [int]$vm.'$key'
                                Name         = $vm.name
                                Description  = $vm.description
                                UUID         = $vm.uuid
                                MachineUUID  = $vm.machine_uuid
                                CPUCores     = $vm.cpu_cores
                                RAM          = $vm.ram
                                RAMMB        = $vm.ram
                                OSFamily     = $vm.os_family
                                IsSnapshot   = [bool]$vm.is_snapshot
                                Status       = $vm.status
                                StatusInfo   = $vm.status_info
                                OriginalKey  = $vm.original_key
                            }
                            $vms += $vmObj
                        }
                    }
                    catch {
                        Write-Warning "Failed to retrieve VMs for cloud snapshot '$($snapshot.name)': $($_.Exception.Message)"
                    }
                    $output | Add-Member -MemberType NoteProperty -Name 'VMs' -Value $vms -Force
                }

                # Get Tenants if requested
                if ($IncludeTenants) {
                    $tenants = @()
                    try {
                        $tenantParams = @{
                            'fields' = @(
                                '$key'
                                'name'
                                'description'
                                'uuid'
                                'nodes'
                                'cpu_cores'
                                'ram'
                                'is_snapshot'
                                'status'
                                'status_info'
                                'original_key'
                            ) -join ','
                            'filter' = "cloud_snapshot eq $($snapshot.'$key')"
                            'sort' = '+name'
                        }
                        $tenantResponse = Invoke-VergeAPI -Method GET -Endpoint 'cloud_snapshot_tenants' -Query $tenantParams -Connection $Server
                        $tenantList = if ($tenantResponse -is [array]) { $tenantResponse } elseif ($tenantResponse) { @($tenantResponse) } else { @() }

                        foreach ($tenant in $tenantList) {
                            if (-not $tenant) { continue }
                            $tenantObj = [PSCustomObject]@{
                                PSTypeName   = 'Verge.CloudSnapshotTenant'
                                Key          = [int]$tenant.'$key'
                                Name         = $tenant.name
                                Description  = $tenant.description
                                UUID         = $tenant.uuid
                                Nodes        = $tenant.nodes
                                CPUCores     = $tenant.cpu_cores
                                RAM          = $tenant.ram
                                RAMMB        = $tenant.ram
                                IsSnapshot   = [bool]$tenant.is_snapshot
                                Status       = $tenant.status
                                StatusInfo   = $tenant.status_info
                                OriginalKey  = $tenant.original_key
                            }
                            $tenants += $tenantObj
                        }
                    }
                    catch {
                        Write-Warning "Failed to retrieve tenants for cloud snapshot '$($snapshot.name)': $($_.Exception.Message)"
                    }
                    $output | Add-Member -MemberType NoteProperty -Name 'Tenants' -Value $tenants -Force
                }

                # Add hidden property for pipeline support
                $output | Add-Member -MemberType NoteProperty -Name '_Connection' -Value $Server -Force

                Write-Output $output
            }
        }
        catch {
            Write-Error -Message "Failed to get cloud snapshots: $($_.Exception.Message)" -ErrorId 'GetCloudSnapshotsFailed'
        }
    }
}
