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
        - Snapshots: VM and tenant snapshots
        - NAS: NAS services, volumes, and shares
        - All: All resource types (default)

    .PARAMETER TenantName
        Filter inventory to a specific tenant context. Only applies to VMs and Networks.

    .PARAMETER IncludeSnapshots
        Include snapshot details for VMs and tenants. By default, snapshots are excluded
        from VM and tenant lists but included in the dedicated Snapshots resource type.

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
        - Snapshots: Array of snapshot objects (VMs and tenants)
        - NAS: Array of NAS service/volume objects
        - Summary: Object with counts per resource type
        - GeneratedAt: Timestamp of inventory generation
        - Server: VergeOS server name

        When -Summary is specified, returns only the Summary object.

    .NOTES
        For large environments, consider filtering by ResourceType to reduce query time.
        Use with Export-Excel module for RVtools-style Excel reports with multiple worksheets.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [ValidateSet('All', 'VMs', 'Networks', 'Storage', 'Nodes', 'Clusters', 'Tenants', 'Snapshots', 'NAS')]
        [string[]]$ResourceType = @('All'),

        [Parameter()]
        [string]$TenantName,

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
        $collectSnapshots = $collectAll -or $ResourceType -contains 'Snapshots'
        $collectNAS = $collectAll -or $ResourceType -contains 'NAS'
    }

    process {
        try {
            Write-Verbose "Generating inventory from $($Server.Server)"

            # Initialize inventory object
            $inventory = [PSCustomObject]@{
                PSTypeName  = 'Verge.Inventory'
                Server      = $Server.Server
                GeneratedAt = Get-Date
                VMs         = @()
                Networks    = @()
                Storage     = @()
                Nodes       = @()
                Clusters    = @()
                Tenants     = @()
                Snapshots   = @()
                NAS         = @()
                Summary     = $null
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

                # Enrich with drive and NIC counts
                $inventory.VMs = foreach ($vm in $vms) {
                    $drives = @(Get-VergeDrive -VMKey $vm.Key -Server $Server -ErrorAction SilentlyContinue)
                    $nics = @(Get-VergeNIC -VMKey $vm.Key -Server $Server -ErrorAction SilentlyContinue)

                    # Calculate total disk size
                    $totalDiskGB = ($drives | Measure-Object -Property SizeGB -Sum).Sum

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
                        DiskCount        = $drives.Count
                        TotalDiskGB      = [math]::Round($totalDiskGB, 1)
                        NICCount         = $nics.Count
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

            # Collect Snapshots
            if ($collectSnapshots) {
                Write-Verbose "Collecting snapshot inventory..."
                $snapshots = @()

                # VM Snapshots - need to iterate over VMs
                $allVMs = if ($collectVMs -and $inventory.VMs.Count -gt 0) {
                    # Reuse VMs already collected
                    Get-VergeVM -Server $Server -IncludeSnapshots:$false
                } else {
                    Get-VergeVM -Server $Server -IncludeSnapshots:$false
                }

                foreach ($vm in $allVMs) {
                    $vmSnapshots = Get-VergeVMSnapshot -VM $vm -Server $Server -ErrorAction SilentlyContinue
                    foreach ($snap in $vmSnapshots) {
                        $snapshots += [PSCustomObject]@{
                            PSTypeName     = 'Verge.Inventory.Snapshot'
                            Type           = 'VM'
                            Key            = $snap.Key
                            Name           = $snap.Name
                            Description    = $snap.Description
                            ParentName     = $snap.VMName
                            ParentKey      = $snap.VMKey
                            Created        = $snap.Created
                            ExpirationDate = $snap.Expires
                            NeverExpires   = $snap.NeverExpires
                        }
                    }
                }

                # Tenant Snapshots - need to iterate over tenants
                $allTenants = Get-VergeTenant -Server $Server -ErrorAction SilentlyContinue
                foreach ($tenant in $allTenants) {
                    $tenantSnapshots = Get-VergeTenantSnapshot -Tenant $tenant -Server $Server -ErrorAction SilentlyContinue
                    foreach ($snap in $tenantSnapshots) {
                        $snapshots += [PSCustomObject]@{
                            PSTypeName     = 'Verge.Inventory.Snapshot'
                            Type           = 'Tenant'
                            Key            = $snap.Key
                            Name           = $snap.Name
                            Description    = $snap.Description
                            ParentName     = $snap.TenantName
                            ParentKey      = $snap.TenantKey
                            Created        = $snap.Created
                            ExpirationDate = $snap.Expires
                            NeverExpires   = ($snap.ExpiresTimestamp -eq 0)
                        }
                    }
                }

                $inventory.Snapshots = $snapshots
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

            # Generate summary
            $summaryData = [PSCustomObject]@{
                PSTypeName      = 'Verge.Inventory.Summary'
                Server          = $Server.Server
                GeneratedAt     = $inventory.GeneratedAt
                VMsTotal        = $inventory.VMs.Count
                VMsRunning      = ($inventory.VMs | Where-Object PowerState -eq 'Running').Count
                VMsStopped      = ($inventory.VMs | Where-Object PowerState -eq 'Stopped').Count
                TotalCPUCores   = ($inventory.VMs | Measure-Object -Property CPUCores -Sum).Sum
                TotalRAMGB      = [math]::Round(($inventory.VMs | Measure-Object -Property RAMGB -Sum).Sum, 1)
                TotalDiskGB     = [math]::Round(($inventory.VMs | Measure-Object -Property TotalDiskGB -Sum).Sum, 1)
                NetworksTotal   = $inventory.Networks.Count
                NetworksRunning = ($inventory.Networks | Where-Object PowerState -eq 'Running').Count
                StorageTiers    = $inventory.Storage.Count
                StorageCapacityGB = [math]::Round(($inventory.Storage | Measure-Object -Property CapacityGB -Sum).Sum, 1)
                StorageUsedGB   = [math]::Round(($inventory.Storage | Measure-Object -Property UsedGB -Sum).Sum, 1)
                NodesTotal      = $inventory.Nodes.Count
                NodesOnline     = ($inventory.Nodes | Where-Object Status -eq 'Running').Count
                ClustersTotal   = $inventory.Clusters.Count
                TenantsTotal    = $inventory.Tenants.Count
                TenantsOnline   = ($inventory.Tenants | Where-Object IsRunning -eq $true).Count
                SnapshotsTotal  = $inventory.Snapshots.Count
                VMSnapshots     = ($inventory.Snapshots | Where-Object Type -eq 'VM').Count
                TenantSnapshots = ($inventory.Snapshots | Where-Object Type -eq 'Tenant').Count
                NASServices     = ($inventory.NAS | Where-Object ItemType -eq 'Service').Count
                NASVolumes      = ($inventory.NAS | Where-Object ItemType -eq 'Volume').Count
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
