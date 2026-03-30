function Get-VergeInventory {
    <#
    .SYNOPSIS
        Generates a comprehensive inventory report of VergeOS infrastructure.

    .DESCRIPTION
        Get-VergeInventory aggregates inventory data across all resource types in a VergeOS
        system, similar to RVtools for VMware environments. Returns detailed information
        about VMs, networks, storage, nodes, clusters, tenants, and snapshots.

        The inventory can be exported to CSV, JSON, or used with Export-Excel for
        comprehensive Excel reports.

    .PARAMETER ResourceType
        Filter inventory by resource type(s). Valid values:
        - VMs: Virtual machines with CPU, RAM, OS, power state
        - Networks: Virtual networks with DHCP, DNS, IP configuration
        - Storage: Storage tiers with capacity and usage
        - Nodes: Physical nodes with hardware details
        - Clusters: Cluster configuration and resource utilization
        - Tenants: Multi-tenant environments
        - VMSnapshots: Individual VM and tenant point-in-time snapshots
        - CloudSnapshots: System-wide cloud snapshots (with immutability status)
        - NAS: NAS services, volumes, and shares
        - All: All resource types (default)

    .PARAMETER IncludeSnapshots
        Include snapshot VMs in the VM list. By default, VMs that are point-in-time snapshots
        of other VMs are excluded. Snapshot metadata is available via VMSnapshots and
        CloudSnapshots resource types regardless of this setting.

    .PARAMETER IncludePoweredOff
        Include powered-off VMs. By default, all VMs are included regardless of power state.
        Set to $false to exclude powered-off VMs.

    .PARAMETER Summary
        Return summary counts only instead of detailed inventory data.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeInventory

        Returns complete inventory of all resources.

    .EXAMPLE
        Get-VergeInventory -ResourceType VMs, Networks

        Returns inventory of VMs and networks only.

    .EXAMPLE
        Get-VergeInventory -Summary

        Returns summary counts for all resource types.

    .EXAMPLE
        Get-VergeInventory -ResourceType VMs | Export-Csv -Path "VM_Inventory.csv"

        Exports VM inventory to CSV format.

    .EXAMPLE
        Get-VergeInventory | Export-Excel -Path "VergeOS_Inventory.xlsx" -WorksheetName "Inventory"

        Exports full inventory to Excel (requires ImportExcel module).

    .EXAMPLE
        Get-VergeInventory -ResourceType VMs -IncludePoweredOff:$false

        Returns inventory of running VMs only.

    .EXAMPLE
        $inventory = Get-VergeInventory
        $inventory.VMs | Format-Table Name, PowerState, CPUCores, RAM
        $inventory.Networks | Format-Table Name, Type, NetworkAddress
        $inventory.Storage | Format-Table Tier, CapacityGB, UsedGB, UsedPercent

        Access specific resource types from the inventory object.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.Inventory' containing:
        - VMs: Array of VM objects
        - Networks: Array of network objects
        - Storage: Array of storage tier objects
        - Nodes: Array of node objects
        - Clusters: Array of cluster objects
        - Tenants: Array of tenant objects
        - VMSnapshots: Array of VM/tenant snapshot objects
        - CloudSnapshots: Array of cloud snapshot objects (with immutability info)
        - NAS: Array of NAS service/volume objects
        - Summary: Object with counts per resource type
        - GeneratedAt: Timestamp of inventory generation
        - Server: VergeOS server name

        When -Summary is specified, returns only the Summary object.

    .NOTES
        For large environments, consider filtering by ResourceType to reduce query time.
        Use with Export-Excel module for RVtools-style Excel reports with multiple worksheets.

        When using -ResourceType to filter, Summary fields for non-requested resource types
        will be $null rather than 0. This allows callers to distinguish between "zero resources
        exist" and "this resource type was not queried."
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [ValidateSet('All', 'VMs', 'Networks', 'Storage', 'Nodes', 'Clusters', 'Tenants', 'VMSnapshots', 'CloudSnapshots', 'NAS')]
        [string[]]$ResourceType = @('All'),

        [Parameter()]
        [switch]$IncludeSnapshots,

        [Parameter()]
        [bool]$IncludePoweredOff = $true,

        [Parameter()]
        [switch]$Summary,

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

        # Determine which resources to collect
        $collectAll = $ResourceType -contains 'All'
        $collectVMs = $collectAll -or $ResourceType -contains 'VMs'
        $collectNetworks = $collectAll -or $ResourceType -contains 'Networks'
        $collectStorage = $collectAll -or $ResourceType -contains 'Storage'
        $collectNodes = $collectAll -or $ResourceType -contains 'Nodes'
        $collectClusters = $collectAll -or $ResourceType -contains 'Clusters'
        $collectTenants = $collectAll -or $ResourceType -contains 'Tenants'
        $collectVMSnapshots = $collectAll -or $ResourceType -contains 'VMSnapshots'
        $collectCloudSnapshots = $collectAll -or $ResourceType -contains 'CloudSnapshots'
        $collectNAS = $collectAll -or $ResourceType -contains 'NAS'
    }

    process {
        try {
            Write-Verbose "Generating inventory from $($Server.Server)"

            # Initialize inventory object
            $inventory = [PSCustomObject]@{
                PSTypeName     = 'Verge.Inventory'
                Server         = $Server.Server
                GeneratedAt    = Get-Date
                VMs            = @()
                Networks       = @()
                Storage        = @()
                Nodes          = @()
                Clusters       = @()
                Tenants        = @()
                VMSnapshots    = @()
                CloudSnapshots = @()
                NAS            = @()
                Summary        = $null
            }

            # Collect VMs
            if ($collectVMs) {
                Write-Verbose "Collecting VM inventory..."
                $vmParams = @{ Server = $Server }
                if ($IncludeSnapshots) {
                    $vmParams['IncludeSnapshots'] = $true
                }

                $vms = Get-VergeVM @vmParams

                # Filter powered-off if requested
                if (-not $IncludePoweredOff) {
                    $vms = $vms | Where-Object { $_.PowerState -eq 'Running' }
                }

                # Bulk fetch all drives and NICs in 2 API calls instead of 2N calls
                # This is much more efficient for large environments
                Write-Verbose "Bulk fetching drives and NICs for all VMs..."

                # Fetch all virtual drives (physical_status eq null excludes physical host drives)
                $driveQuery = @{
                    filter = 'physical_status eq null'
                    fields = '$key,name,machine,disksize,used_bytes,media_source#allocated_bytes as allocated_bytes'
                }
                $driveResponse = Invoke-VergeAPI -Method GET -Endpoint 'machine_drives' -Query $driveQuery -Connection $Server -ErrorAction SilentlyContinue
                $allDrives = if ($driveResponse -is [array]) { $driveResponse } elseif ($driveResponse) { @($driveResponse) } else { @() }

                # Fetch all NICs
                $nicQuery = @{
                    fields = '$key,name,machine'
                }
                $nicResponse = Invoke-VergeAPI -Method GET -Endpoint 'machine_nics' -Query $nicQuery -Connection $Server -ErrorAction SilentlyContinue
                $allNICs = if ($nicResponse -is [array]) { $nicResponse } elseif ($nicResponse) { @($nicResponse) } else { @() }

                # Build lookup tables by machine key for O(1) access
                # API returns 'machine' field, not 'MachineKey'
                $drivesByMachine = @{}
                foreach ($drive in $allDrives) {
                    $machineKey = $drive.machine
                    if ($machineKey -and -not $drivesByMachine.ContainsKey($machineKey)) {
                        $drivesByMachine[$machineKey] = [System.Collections.Generic.List[object]]::new()
                    }
                    if ($machineKey) {
                        $drivesByMachine[$machineKey].Add($drive)
                    }
                }

                $nicsByMachine = @{}
                foreach ($nic in $allNICs) {
                    $machineKey = $nic.machine
                    if ($machineKey -and -not $nicsByMachine.ContainsKey($machineKey)) {
                        $nicsByMachine[$machineKey] = [System.Collections.Generic.List[object]]::new()
                    }
                    if ($machineKey) {
                        $nicsByMachine[$machineKey].Add($nic)
                    }
                }

                # Enrich VMs with drive and NIC counts using lookup tables
                $inventory.VMs = foreach ($vm in $vms) {
                    $drives = if ($drivesByMachine.ContainsKey($vm.MachineKey)) {
                        $drivesByMachine[$vm.MachineKey]
                    } else { @() }

                    $nics = if ($nicsByMachine.ContainsKey($vm.MachineKey)) {
                        $nicsByMachine[$vm.MachineKey]
                    } else { @() }

                    # Calculate total disk size from raw API response
                    # disksize or allocated_bytes, convert from bytes to GB
                    $totalDiskBytes = ($drives | ForEach-Object {
                        if ($_.disksize) { $_.disksize }
                        elseif ($_.allocated_bytes) { $_.allocated_bytes }
                        else { 0 }
                    } | Measure-Object -Sum).Sum
                    $totalDiskGB = $totalDiskBytes / 1GB

                    [PSCustomObject]@{
                        PSTypeName       = 'Verge.Inventory.VM'
                        Key              = $vm.Key
                        Name             = $vm.Name
                        Description      = $vm.Description
                        PowerState       = $vm.PowerState
                        CPUCores         = $vm.CPUCores
                        RAMGB            = [math]::Round($vm.RAM / 1024, 1)
                        RAMMb            = $vm.RAM
                        OSFamily         = $vm.OSFamily
                        GuestAgent       = $vm.GuestAgent
                        UEFI             = $vm.UEFI
                        SecureBoot       = $vm.SecureBoot
                        MachineType      = $vm.MachineType
                        Cluster          = $vm.Cluster
                        Node             = $vm.Node
                        HAGroup          = $vm.HAGroup
                        SnapshotProfile  = $vm.SnapshotProfile
                        DiskCount        = @($drives).Count
                        TotalDiskGB      = [math]::Round($totalDiskGB, 1)
                        NICCount         = @($nics).Count
                        Created          = $vm.Created
                        Modified         = $vm.Modified
                    }
                }
            }

            # Collect Networks
            if ($collectNetworks) {
                Write-Verbose "Collecting network inventory..."
                $networks = Get-VergeNetwork -Server $Server

                $inventory.Networks = foreach ($net in $networks) {
                    [PSCustomObject]@{
                        PSTypeName     = 'Verge.Inventory.Network'
                        Key            = $net.Key
                        Name           = $net.Name
                        Description    = $net.Description
                        Type           = $net.Type
                        PowerState     = $net.PowerState
                        NetworkAddress = $net.NetworkAddress
                        IPAddress      = $net.IPAddress
                        Gateway        = $net.Gateway
                        MTU            = $net.MTU
                        DHCPEnabled    = $net.DHCPEnabled
                        DHCPStart      = $net.DHCPStart
                        DHCPStop       = $net.DHCPStop
                        DNS            = $net.DNS
                        Domain         = $net.Domain
                        Cluster        = $net.Cluster
                        Node           = $net.Node
                    }
                }
            }

            # Collect Storage
            if ($collectStorage) {
                Write-Verbose "Collecting storage inventory..."
                $tiers = Get-VergeStorageTier -Server $Server

                $inventory.Storage = foreach ($tier in $tiers) {
                    [PSCustomObject]@{
                        PSTypeName   = 'Verge.Inventory.Storage'
                        Tier         = $tier.Tier
                        Description  = $tier.Description
                        CapacityGB   = $tier.CapacityGB
                        UsedGB       = $tier.UsedGB
                        FreeGB       = $tier.FreeGB
                        AllocatedGB  = $tier.AllocatedGB
                        UsedPercent  = $tier.UsedPercent
                        DedupeRatio  = $tier.DedupeRatio
                        ReadOps      = $tier.ReadOps
                        WriteOps     = $tier.WriteOps
                    }
                }
            }

            # Collect Nodes
            if ($collectNodes) {
                Write-Verbose "Collecting node inventory..."
                $nodes = Get-VergeNode -Server $Server

                $inventory.Nodes = foreach ($node in $nodes) {
                    [PSCustomObject]@{
                        PSTypeName      = 'Verge.Inventory.Node'
                        Key             = $node.Key
                        Name            = $node.Name
                        Status          = $node.Status
                        Cluster         = $node.Cluster
                        Cores           = $node.Cores
                        RAMGB           = [math]::Round($node.RAM / 1024, 1)
                        RAMMb           = $node.RAM
                        MaintenanceMode = $node.MaintenanceMode
                        NeedsRestart    = $node.NeedsRestart
                        RestartReason   = $node.RestartReason
                        IOMMU           = $node.IOMMU
                        VergeOSVersion  = $node.VergeOSVersion
                        KernelVersion   = $node.KernelVersion
                    }
                }
            }

            # Collect Clusters
            if ($collectClusters) {
                Write-Verbose "Collecting cluster inventory..."
                $clusters = Get-VergeCluster -Server $Server

                $inventory.Clusters = foreach ($cluster in $clusters) {
                    [PSCustomObject]@{
                        PSTypeName         = 'Verge.Inventory.Cluster'
                        Key                = $cluster.Key
                        Name               = $cluster.Name
                        Description        = $cluster.Description
                        Status             = $cluster.Status
                        TotalNodes         = $cluster.TotalNodes
                        OnlineNodes        = $cluster.OnlineNodes
                        OnlineCores        = $cluster.OnlineCores
                        UsedCores          = $cluster.UsedCores
                        OnlineRAMGB        = [math]::Round($cluster.OnlineRAM / 1024, 1)
                        UsedRAMGB          = [math]::Round($cluster.UsedRAM / 1024, 1)
                        RunningMachines    = $cluster.RunningMachines
                        DefaultCPUType     = $cluster.DefaultCPUType
                        NestedVirtualization = $cluster.NestedVirtualization
                    }
                }
            }

            # Collect Tenants
            if ($collectTenants) {
                Write-Verbose "Collecting tenant inventory..."
                $tenantParams = @{ Server = $Server }
                if ($IncludeSnapshots) {
                    $tenantParams['IncludeSnapshots'] = $true
                }
                $tenants = Get-VergeTenant @tenantParams

                $inventory.Tenants = foreach ($tenant in $tenants) {
                    [PSCustomObject]@{
                        PSTypeName  = 'Verge.Inventory.Tenant'
                        Key         = $tenant.Key
                        Name        = $tenant.Name
                        Description = $tenant.Description
                        Status      = $tenant.Status
                        State       = $tenant.State
                        IsRunning   = $tenant.IsRunning
                        Isolated    = $tenant.Isolated
                        URL         = $tenant.URL
                        UIAddress   = $tenant.UIAddress
                        NetworkName = $tenant.NetworkName
                        Created     = $tenant.Created
                        Started     = $tenant.Started
                    }
                }
            }

            # Collect VM Snapshots (individual VM point-in-time snapshots - manually created only)
            # Uses bulk API calls instead of per-VM queries to avoid N+1 performance issue
            if ($collectVMSnapshots) {
                Write-Verbose "Collecting VM snapshot inventory..."
                $vmSnapshotList = [System.Collections.Generic.List[object]]::new()

                # Bulk fetch all VM snapshots in a single API call
                # Filter out cloud snapshot entries (snapshot_period is set for cloud snapshots)
                $snapQuery = @{
                    fields = '$key,name,description,created,expires,expires_type,quiesced,created_manually,machine,snap_machine,snapshot_period'
                    filter = 'snapshot_period eq null'
                    sort   = '-created'
                }
                $snapResponse = Invoke-VergeAPI -Method GET -Endpoint 'machine_snapshots' -Query $snapQuery -Connection $Server -ErrorAction SilentlyContinue
                $allMachineSnapshots = if ($snapResponse -is [array]) { $snapResponse } elseif ($snapResponse) { @($snapResponse) } else { @() }

                # Build VM name lookup for display (reuse allVMs if already fetched for VM collection)
                $vmNameLookup = @{}
                $lookupVMs = if ($collectVMs -and $vms) { $vms } else { Get-VergeVM -Server $Server -IncludeSnapshots:$false }
                foreach ($vm in $lookupVMs) {
                    if ($vm.MachineKey) { $vmNameLookup[$vm.MachineKey] = $vm }
                }

                foreach ($snapshot in $allMachineSnapshots) {
                    if (-not $snapshot -or -not $snapshot.name) { continue }

                    $machineKey = $snapshot.machine
                    $vmInfo = if ($vmNameLookup.ContainsKey($machineKey)) { $vmNameLookup[$machineKey] } else { $null }

                    # Convert timestamps
                    $createdDate = if ($snapshot.created) {
                        [DateTimeOffset]::FromUnixTimeSeconds($snapshot.created).LocalDateTime
                    } else { $null }
                    $expiresDate = if ($snapshot.expires -and $snapshot.expires -gt 0) {
                        [DateTimeOffset]::FromUnixTimeSeconds($snapshot.expires).LocalDateTime
                    } else { $null }

                    $vmSnapshotList.Add([PSCustomObject]@{
                        PSTypeName      = 'Verge.Inventory.VMSnapshot'
                        Key             = [int]$snapshot.'$key'
                        Name            = $snapshot.name
                        Description     = $snapshot.description
                        VMName          = if ($vmInfo) { $vmInfo.Name } else { "VM:$machineKey" }
                        VMKey           = if ($vmInfo) { $vmInfo.Key } else { $null }
                        Created         = $createdDate
                        Expires         = $expiresDate
                        NeverExpires    = ($snapshot.expires_type -eq 'never' -or $snapshot.expires -eq 0)
                        Quiesced        = [bool]$snapshot.quiesced
                        CreatedManually = [bool]$snapshot.created_manually
                    })
                }

                # Bulk fetch all tenant snapshots in a single API call
                $tenantSnapQuery = @{
                    fields = '$key,tenant,name,description,created,expires'
                    sort   = '-created'
                }
                $tenantSnapResponse = Invoke-VergeAPI -Method GET -Endpoint 'tenant_snapshots' -Query $tenantSnapQuery -Connection $Server -ErrorAction SilentlyContinue
                $allTenantSnapshots = if ($tenantSnapResponse -is [array]) { $tenantSnapResponse } elseif ($tenantSnapResponse) { @($tenantSnapResponse) } else { @() }

                # Build tenant name lookup
                $tenantNameLookup = @{}
                $lookupTenants = if ($collectTenants -and $tenants) { $tenants } else { Get-VergeTenant -Server $Server -ErrorAction SilentlyContinue }
                foreach ($t in $lookupTenants) {
                    if ($t.Key) { $tenantNameLookup[$t.Key] = $t.Name }
                }

                foreach ($snapshot in $allTenantSnapshots) {
                    if (-not $snapshot -or -not $snapshot.name) { continue }

                    $tenantKey = [int]$snapshot.tenant
                    $tenantName = if ($tenantNameLookup.ContainsKey($tenantKey)) { $tenantNameLookup[$tenantKey] } else { "Tenant:$tenantKey" }

                    $createdDate = if ($snapshot.created) {
                        [DateTimeOffset]::FromUnixTimeSeconds($snapshot.created).LocalDateTime
                    } else { $null }
                    $expiresDate = if ($snapshot.expires -and $snapshot.expires -gt 0) {
                        [DateTimeOffset]::FromUnixTimeSeconds($snapshot.expires).LocalDateTime
                    } else { $null }

                    $vmSnapshotList.Add([PSCustomObject]@{
                        PSTypeName      = 'Verge.Inventory.VMSnapshot'
                        Key             = [int]$snapshot.'$key'
                        Name            = $snapshot.name
                        Description     = $snapshot.description
                        VMName          = "[Tenant] $tenantName"
                        VMKey           = $tenantKey
                        Created         = $createdDate
                        Expires         = $expiresDate
                        NeverExpires    = ($snapshot.expires -eq 0 -or -not $snapshot.expires)
                        Quiesced        = $null
                        CreatedManually = $null
                    })
                }

                $inventory.VMSnapshots = $vmSnapshotList
            }

            # Collect Cloud Snapshots (system-wide snapshots)
            if ($collectCloudSnapshots) {
                Write-Verbose "Collecting cloud snapshot inventory..."
                $cloudSnapshotList = @()

                $cloudSnapshots = Get-VergeCloudSnapshot -Server $Server -IncludeExpired -ErrorAction SilentlyContinue
                foreach ($snap in $cloudSnapshots) {
                    # Determine if snapshot is currently expired
                    $isExpired = if ($snap.Expires) {
                        $snap.Expires -lt (Get-Date)
                    } else {
                        $false
                    }

                    $cloudSnapshotList += [PSCustomObject]@{
                        PSTypeName           = 'Verge.Inventory.CloudSnapshot'
                        Key                  = $snap.Key
                        Name                 = $snap.Name
                        Description          = $snap.Description
                        Created              = $snap.Created
                        Expires              = $snap.Expires
                        NeverExpires         = $snap.NeverExpires
                        IsExpired            = $isExpired
                        Profile              = $snap.SnapshotProfileName
                        Status               = $snap.Status
                        Immutable            = $snap.Immutable
                        ImmutableStatus      = $snap.ImmutableStatus
                        ImmutableLockExpires = $snap.ImmutableLockExpires
                        RemoteSync           = $snap.RemoteSync
                    }
                }

                $inventory.CloudSnapshots = $cloudSnapshotList
            }

            # Collect NAS
            if ($collectNAS) {
                Write-Verbose "Collecting NAS inventory..."
                $nasItems = @()

                # NAS Services
                $nasServices = Get-VergeNASService -Server $Server -ErrorAction SilentlyContinue
                foreach ($svc in $nasServices) {
                    $nasItems += [PSCustomObject]@{
                        PSTypeName  = 'Verge.Inventory.NAS'
                        ItemType    = 'Service'
                        Key         = $svc.Key
                        Name        = $svc.Name
                        Description = $svc.Description
                        Status      = $svc.Status
                        IPAddress   = $svc.IPAddress
                        Cluster     = $svc.Cluster
                        Node        = $svc.Node
                    }
                }

                # NAS Volumes
                $nasVolumes = Get-VergeNASVolume -Server $Server -ErrorAction SilentlyContinue
                foreach ($vol in $nasVolumes) {
                    $nasItems += [PSCustomObject]@{
                        PSTypeName  = 'Verge.Inventory.NAS'
                        ItemType    = 'Volume'
                        Key         = $vol.Key
                        Name        = $vol.Name
                        Description = $vol.Description
                        Status      = $vol.MountStatus
                        Tier        = $vol.PreferredTier
                        SizeGB      = $vol.MaxSizeGB
                        UsedGB      = $vol.UsedGB
                        NASService  = $vol.NASService
                    }
                }

                $inventory.NAS = $nasItems
            }

            # Generate summary - use $null for resource types that were not collected
            # so users can distinguish "zero resources" from "not queried"
            $summaryData = [PSCustomObject]@{
                PSTypeName        = 'Verge.Inventory.Summary'
                Server            = $Server.Server
                GeneratedAt       = $inventory.GeneratedAt
                VMsTotal          = if ($collectVMs) { $inventory.VMs.Count } else { $null }
                VMsRunning        = if ($collectVMs) { ($inventory.VMs | Where-Object PowerState -eq 'Running').Count } else { $null }
                VMsStopped        = if ($collectVMs) { ($inventory.VMs | Where-Object PowerState -eq 'Stopped').Count } else { $null }
                TotalCPUCores     = if ($collectVMs) { ($inventory.VMs | Measure-Object -Property CPUCores -Sum).Sum } else { $null }
                TotalRAMGB        = if ($collectVMs) { [math]::Round(($inventory.VMs | Measure-Object -Property RAMGB -Sum).Sum, 1) } else { $null }
                TotalDiskGB       = if ($collectVMs) { [math]::Round(($inventory.VMs | Measure-Object -Property TotalDiskGB -Sum).Sum, 1) } else { $null }
                NetworksTotal     = if ($collectNetworks) { $inventory.Networks.Count } else { $null }
                NetworksRunning   = if ($collectNetworks) { ($inventory.Networks | Where-Object PowerState -eq 'Running').Count } else { $null }
                StorageTiers      = if ($collectStorage) { $inventory.Storage.Count } else { $null }
                StorageCapacityGB = if ($collectStorage) { [math]::Round(($inventory.Storage | Measure-Object -Property CapacityGB -Sum).Sum, 1) } else { $null }
                StorageUsedGB     = if ($collectStorage) { [math]::Round(($inventory.Storage | Measure-Object -Property UsedGB -Sum).Sum, 1) } else { $null }
                NodesTotal        = if ($collectNodes) { $inventory.Nodes.Count } else { $null }
                NodesOnline       = if ($collectNodes) { ($inventory.Nodes | Where-Object Status -eq 'Running').Count } else { $null }
                ClustersTotal     = if ($collectClusters) { $inventory.Clusters.Count } else { $null }
                TenantsTotal      = if ($collectTenants) { $inventory.Tenants.Count } else { $null }
                TenantsOnline     = if ($collectTenants) { ($inventory.Tenants | Where-Object IsRunning -eq $true).Count } else { $null }
                VMSnapshotsTotal  = if ($collectVMSnapshots) { $inventory.VMSnapshots.Count } else { $null }
                CloudSnapshotsTotal = if ($collectCloudSnapshots) { $inventory.CloudSnapshots.Count } else { $null }
                NASServices       = if ($collectNAS) { ($inventory.NAS | Where-Object ItemType -eq 'Service').Count } else { $null }
                NASVolumes        = if ($collectNAS) { ($inventory.NAS | Where-Object ItemType -eq 'Volume').Count } else { $null }
            }

            $inventory.Summary = $summaryData

            # Return summary only if requested
            if ($Summary) {
                Write-Output $summaryData
            }
            else {
                Write-Output $inventory
            }
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}
