function Set-VergeCluster {
    <#
    .SYNOPSIS
        Modifies the configuration of a VergeOS cluster.

    .DESCRIPTION
        Set-VergeCluster modifies cluster settings such as CPU type, resource limits,
        power management, and other configuration options.

    .PARAMETER Cluster
        A cluster object from Get-VergeCluster. Accepts pipeline input.

    .PARAMETER Name
        The name of the cluster to modify.

    .PARAMETER Key
        The key (ID) of the cluster to modify.

    .PARAMETER NewName
        Rename the cluster to this new name.

    .PARAMETER Description
        Set the cluster description.

    .PARAMETER Enabled
        Enable or disable the cluster.

    .PARAMETER Compute
        Enable or disable compute workloads.

    .PARAMETER NestedVirtualization
        Enable or disable nested virtualization.

    .PARAMETER AllowNestedVirtMigration
        Allow live migration of VMs with nested virtualization.

    .PARAMETER AllowVGPUMigration
        Allow live migration of VMs with vGPU devices.

    .PARAMETER DefaultCPUType
        Set the default CPU type for VMs.

    .PARAMETER DisableCPUSecurityMitigations
        Disable CPU security mitigations.

    .PARAMETER DisableSMT
        Disable Simultaneous Multi-Threading.

    .PARAMETER EnableSplitLockDetection
        Enable split lock detection.

    .PARAMETER EnergyPerfPolicy
        Set the CPU energy-performance policy.

    .PARAMETER ScalingGovernor
        Set the CPU scaling governor.

    .PARAMETER RAMPerUnit
        Set RAM per billing unit in MB.

    .PARAMETER CoresPerUnit
        Set CPU cores per billing unit.

    .PARAMETER CostPerUnit
        Set cost per billing unit.

    .PARAMETER PricePerUnit
        Set price per billing unit.

    .PARAMETER MaxRAMPerVM
        Set maximum RAM allowed per VM in MB.

    .PARAMETER MaxCoresPerVM
        Set maximum CPU cores allowed per VM.

    .PARAMETER TargetRAMPercent
        Set target maximum RAM utilization percentage.

    .PARAMETER RAMOvercommitPercent
        Set percentage of reserve RAM to use for machines.

    .PARAMETER StorageCachePerNode
        Set storage cache per node in MB.

    .PARAMETER StorageBufferPerNode
        Set storage buffer per node in MB.

    .PARAMETER StorageHugepages
        Enable or disable hugepages for storage.

    .PARAMETER EnableNVMePowerManagement
        Enable or disable NVMe power management.

    .PARAMETER SwapTier
        Set storage tier for swap (-1 to disable).

    .PARAMETER SwapPerDrive
        Set swap space per drive in MB.

    .PARAMETER MaxCoreTemp
        Set maximum core temperature in Celsius.

    .PARAMETER CriticalCoreTemp
        Set critical core temperature in Celsius.

    .PARAMETER MaxCoreTempWarnPercent
        Set temperature warning threshold percentage.

    .PARAMETER DisableSleep
        Enable or disable CPU sleep state disabling.

    .PARAMETER LogFilter
        Set system log filter expression.

    .PARAMETER PassThru
        Return the modified cluster object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Set-VergeCluster -Name "Production" -MaxRAMPerVM 131072 -MaxCoresPerVM 64

        Increases VM resource limits on the Production cluster.

    .EXAMPLE
        Get-VergeCluster -Name "Development" | Set-VergeCluster -NestedVirtualization $true

        Enables nested virtualization on the Development cluster.

    .EXAMPLE
        Set-VergeCluster -Name "OldName" -NewName "NewName" -PassThru

        Renames a cluster and returns the updated object.

    .EXAMPLE
        Set-VergeCluster -Name "Production" -DefaultCPUType "EPYC-Milan" -EnergyPerfPolicy Performance

        Updates CPU type and power policy.

    .OUTPUTS
        None by default. Verge.Cluster when -PassThru is specified.

    .NOTES
        Some changes may require node reboots to take effect.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByCluster')]
        [PSTypeName('Verge.Cluster')]
        [PSCustomObject]$Cluster,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter()]
        [ValidateLength(1, 128)]
        [string]$NewName,

        [Parameter()]
        [ValidateLength(0, 2048)]
        [string]$Description,

        [Parameter()]
        [bool]$Enabled,

        [Parameter()]
        [bool]$Compute,

        [Parameter()]
        [bool]$NestedVirtualization,

        [Parameter()]
        [bool]$AllowNestedVirtMigration,

        [Parameter()]
        [bool]$AllowVGPUMigration,

        [Parameter()]
        [ValidateSet(
            'qemu64', 'kvm64', 'host',
            'Broadwell', 'Cascadelake-Server', 'Conroe', 'Cooperlake',
            'core2duo', 'coreduo', 'Denverton',
            'EPYC', 'EPYC-Genoa', 'EPYC-Milan', 'EPYC-Rome',
            'GraniteRapids', 'Haswell', 'Icelake-Server', 'IvyBridge',
            'KnightsMill', 'n270', 'Nehalem',
            'Opteron_G1', 'Opteron_G2', 'Opteron_G3', 'Opteron_G4', 'Opteron_G5',
            'Penryn', 'phenom', 'SandyBridge', 'SapphireRapids',
            'Skylake-Client', 'Skylake-Server', 'Snowridge', 'Westmere'
        )]
        [string]$DefaultCPUType,

        [Parameter()]
        [bool]$DisableCPUSecurityMitigations,

        [Parameter()]
        [bool]$DisableSMT,

        [Parameter()]
        [bool]$EnableSplitLockDetection,

        [Parameter()]
        [ValidateSet('Performance', 'BalancePerformance', 'BalancePower', 'Normal', 'Power')]
        [string]$EnergyPerfPolicy,

        [Parameter()]
        [ValidateSet('Performance', 'OnDemand', 'PowerSave')]
        [string]$ScalingGovernor,

        [Parameter()]
        [ValidateRange(0, 1048576)]
        [int]$RAMPerUnit,

        [Parameter()]
        [ValidateRange(0, 1024)]
        [int]$CoresPerUnit,

        [Parameter()]
        [ValidateRange(0, [double]::MaxValue)]
        [double]$CostPerUnit,

        [Parameter()]
        [ValidateRange(0, [double]::MaxValue)]
        [double]$PricePerUnit,

        [Parameter()]
        [ValidateRange(0, 1048576)]
        [int]$MaxRAMPerVM,

        [Parameter()]
        [ValidateRange(0, 1024)]
        [int]$MaxCoresPerVM,

        [Parameter()]
        [ValidateRange(0, 100)]
        [double]$TargetRAMPercent,

        [Parameter()]
        [ValidateRange(0, 100)]
        [double]$RAMOvercommitPercent,

        [Parameter()]
        [ValidateRange(0, 5000000)]
        [int]$StorageCachePerNode,

        [Parameter()]
        [ValidateRange(0, 5000000)]
        [int]$StorageBufferPerNode,

        [Parameter()]
        [bool]$StorageHugepages,

        [Parameter()]
        [bool]$EnableNVMePowerManagement,

        [Parameter()]
        [ValidateRange(-1, 5)]
        [int]$SwapTier,

        [Parameter()]
        [ValidateRange(0, 1000000)]
        [int]$SwapPerDrive,

        [Parameter()]
        [ValidateRange(0, 150)]
        [int]$MaxCoreTemp,

        [Parameter()]
        [ValidateRange(0, 150)]
        [int]$CriticalCoreTemp,

        [Parameter()]
        [ValidateRange(-1, 100)]
        [int]$MaxCoreTempWarnPercent,

        [Parameter()]
        [bool]$DisableSleep,

        [Parameter()]
        [string]$LogFilter,

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

        # Map friendly names to API values
        $energyPerfMap = @{
            'Performance'        = 'performance'
            'BalancePerformance' = 'balance-performance'
            'BalancePower'       = 'balance-power'
            'Normal'             = 'normal'
            'Power'              = 'power'
        }

        $scalingGovMap = @{
            'Performance' = 'performance'
            'OnDemand'    = 'ondemand'
            'PowerSave'   = 'powersave'
        }
    }

    process {
        # Resolve cluster based on parameter set
        $targetCluster = switch ($PSCmdlet.ParameterSetName) {
            'ByName' {
                Get-VergeCluster -Name $Name -Server $Server | Select-Object -First 1
            }
            'ByKey' {
                Get-VergeCluster -Key $Key -Server $Server
            }
            'ByCluster' {
                $Cluster
            }
        }

        if (-not $targetCluster) {
            Write-Error -Message "Cluster not found" -ErrorId 'ClusterNotFound'
            return
        }

        # Build the update body with only specified parameters
        $body = @{}
        $changes = [System.Collections.Generic.List[string]]::new()

        if ($PSBoundParameters.ContainsKey('NewName')) {
            $body['name'] = $NewName
            $changes.Add("Name: $($targetCluster.Name) -> $NewName")
        }

        if ($PSBoundParameters.ContainsKey('Description')) {
            $body['description'] = $Description
            $changes.Add("Description updated")
        }

        if ($PSBoundParameters.ContainsKey('Enabled')) {
            $body['enabled'] = $Enabled
            $changes.Add("Enabled: $Enabled")
        }

        if ($PSBoundParameters.ContainsKey('Compute')) {
            $body['compute'] = $Compute
            $changes.Add("Compute: $Compute")
        }

        if ($PSBoundParameters.ContainsKey('NestedVirtualization')) {
            $body['kvm_nested'] = $NestedVirtualization
            $changes.Add("Nested Virtualization: $NestedVirtualization")
        }

        if ($PSBoundParameters.ContainsKey('AllowNestedVirtMigration')) {
            $body['allow_nested_virt_migration'] = $AllowNestedVirtMigration
            $changes.Add("Allow Nested Virt Migration: $AllowNestedVirtMigration")
        }

        if ($PSBoundParameters.ContainsKey('AllowVGPUMigration')) {
            $body['allow_vgpu_migration'] = $AllowVGPUMigration
            $changes.Add("Allow vGPU Migration: $AllowVGPUMigration")
        }

        if ($PSBoundParameters.ContainsKey('DefaultCPUType')) {
            $body['default_cpu'] = $DefaultCPUType
            $changes.Add("Default CPU Type: $DefaultCPUType")
        }

        if ($PSBoundParameters.ContainsKey('DisableCPUSecurityMitigations')) {
            $body['disable_cpu_security_mitigations'] = $DisableCPUSecurityMitigations
            $changes.Add("Disable CPU Security Mitigations: $DisableCPUSecurityMitigations")
        }

        if ($PSBoundParameters.ContainsKey('DisableSMT')) {
            $body['disable_smt'] = $DisableSMT
            $changes.Add("Disable SMT: $DisableSMT")
        }

        if ($PSBoundParameters.ContainsKey('EnableSplitLockDetection')) {
            $body['enable_split_lock_detection'] = $EnableSplitLockDetection
            $changes.Add("Enable Split Lock Detection: $EnableSplitLockDetection")
        }

        if ($PSBoundParameters.ContainsKey('EnergyPerfPolicy')) {
            $body['x86_energy_perf_policy'] = $energyPerfMap[$EnergyPerfPolicy]
            $changes.Add("Energy Perf Policy: $EnergyPerfPolicy")
        }

        if ($PSBoundParameters.ContainsKey('ScalingGovernor')) {
            $body['scaling_governor'] = $scalingGovMap[$ScalingGovernor]
            $changes.Add("Scaling Governor: $ScalingGovernor")
        }

        if ($PSBoundParameters.ContainsKey('RAMPerUnit')) {
            $body['ram_per_unit'] = $RAMPerUnit
            $changes.Add("RAM Per Unit: ${RAMPerUnit}MB")
        }

        if ($PSBoundParameters.ContainsKey('CoresPerUnit')) {
            $body['cores_per_unit'] = $CoresPerUnit
            $changes.Add("Cores Per Unit: $CoresPerUnit")
        }

        if ($PSBoundParameters.ContainsKey('CostPerUnit')) {
            $body['cost_per_unit'] = $CostPerUnit
            $changes.Add("Cost Per Unit: $CostPerUnit")
        }

        if ($PSBoundParameters.ContainsKey('PricePerUnit')) {
            $body['price_per_unit'] = $PricePerUnit
            $changes.Add("Price Per Unit: $PricePerUnit")
        }

        if ($PSBoundParameters.ContainsKey('MaxRAMPerVM')) {
            $body['max_ram_per_vm'] = $MaxRAMPerVM
            $changes.Add("Max RAM Per VM: ${MaxRAMPerVM}MB")
        }

        if ($PSBoundParameters.ContainsKey('MaxCoresPerVM')) {
            $body['max_cores_per_vm'] = $MaxCoresPerVM
            $changes.Add("Max Cores Per VM: $MaxCoresPerVM")
        }

        if ($PSBoundParameters.ContainsKey('TargetRAMPercent')) {
            $body['target_ram_pct'] = $TargetRAMPercent
            $changes.Add("Target RAM Percent: $TargetRAMPercent%")
        }

        if ($PSBoundParameters.ContainsKey('RAMOvercommitPercent')) {
            $body['ram_overcommit_pct'] = $RAMOvercommitPercent
            $changes.Add("RAM Overcommit Percent: $RAMOvercommitPercent%")
        }

        if ($PSBoundParameters.ContainsKey('StorageCachePerNode')) {
            $body['storage_cachesize'] = $StorageCachePerNode
            $changes.Add("Storage Cache Per Node: ${StorageCachePerNode}MB")
        }

        if ($PSBoundParameters.ContainsKey('StorageBufferPerNode')) {
            $body['storage_buffersize'] = $StorageBufferPerNode
            $changes.Add("Storage Buffer Per Node: ${StorageBufferPerNode}MB")
        }

        if ($PSBoundParameters.ContainsKey('StorageHugepages')) {
            $body['storage_hugepages'] = $StorageHugepages
            $changes.Add("Storage Hugepages: $StorageHugepages")
        }

        if ($PSBoundParameters.ContainsKey('EnableNVMePowerManagement')) {
            $body['enable_nvme_power_management'] = $EnableNVMePowerManagement
            $changes.Add("Enable NVMe Power Management: $EnableNVMePowerManagement")
        }

        if ($PSBoundParameters.ContainsKey('SwapTier')) {
            $body['swap_tier'] = $SwapTier
            $changes.Add("Swap Tier: $SwapTier")
        }

        if ($PSBoundParameters.ContainsKey('SwapPerDrive')) {
            $body['swap_per_drive'] = $SwapPerDrive
            $changes.Add("Swap Per Drive: ${SwapPerDrive}MB")
        }

        if ($PSBoundParameters.ContainsKey('MaxCoreTemp')) {
            $body['max_core_temp'] = $MaxCoreTemp
            $changes.Add("Max Core Temp: ${MaxCoreTemp}°C")
        }

        if ($PSBoundParameters.ContainsKey('CriticalCoreTemp')) {
            $body['critical_core_temp'] = $CriticalCoreTemp
            $changes.Add("Critical Core Temp: ${CriticalCoreTemp}°C")
        }

        if ($PSBoundParameters.ContainsKey('MaxCoreTempWarnPercent')) {
            $body['max_core_temp_warn_perc'] = $MaxCoreTempWarnPercent
            $changes.Add("Max Core Temp Warn Percent: $MaxCoreTempWarnPercent%")
        }

        if ($PSBoundParameters.ContainsKey('DisableSleep')) {
            $body['disable_sleep'] = $DisableSleep
            $changes.Add("Disable Sleep: $DisableSleep")
        }

        if ($PSBoundParameters.ContainsKey('LogFilter')) {
            $body['log_filter'] = $LogFilter
            $changes.Add("Log Filter: $LogFilter")
        }

        # Check if there are any changes to make
        if ($body.Count -eq 0) {
            Write-Warning "No changes specified for cluster '$($targetCluster.Name)'"
            if ($PassThru) {
                Write-Output $targetCluster
            }
            return
        }

        # Build change summary for confirmation
        $changeSummary = $changes -join ', '

        if ($PSCmdlet.ShouldProcess($targetCluster.Name, "Modify Cluster ($changeSummary)")) {
            try {
                Write-Verbose "Modifying cluster '$($targetCluster.Name)' (Key: $($targetCluster.Key))"
                Write-Verbose "Changes: $changeSummary"

                $response = Invoke-VergeAPI -Method PUT -Endpoint "clusters/$($targetCluster.Key)" -Body $body -Connection $Server

                Write-Verbose "Cluster '$($targetCluster.Name)' modified successfully"

                if ($PassThru) {
                    # Return the updated cluster
                    Start-Sleep -Milliseconds 500
                    Get-VergeCluster -Key $targetCluster.Key -Server $Server
                }
            }
            catch {
                Write-Error -Message "Failed to modify cluster '$($targetCluster.Name)': $($_.Exception.Message)" -ErrorId 'ClusterModifyFailed'
            }
        }
    }
}
