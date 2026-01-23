function New-VergeCluster {
    <#
    .SYNOPSIS
        Creates a new cluster in VergeOS.

    .DESCRIPTION
        New-VergeCluster creates a new cluster with the specified configuration.
        Clusters group nodes for compute and storage resources.

    .PARAMETER Name
        The name of the new cluster. Must be unique and 1-128 characters.

    .PARAMETER Description
        An optional description for the cluster.

    .PARAMETER Enabled
        Enable the cluster after creation. Default is true.

    .PARAMETER Compute
        Enable compute workloads on this cluster.

    .PARAMETER NestedVirtualization
        Enable nested virtualization (running VMs inside VMs).

    .PARAMETER AllowNestedVirtMigration
        Allow live migration of VMs with nested virtualization enabled.

    .PARAMETER AllowVGPUMigration
        Allow live migration of VMs with vGPU devices (experimental).

    .PARAMETER DefaultCPUType
        The default CPU type for VMs in this cluster.

    .PARAMETER DisableCPUSecurityMitigations
        Disable CPU security mitigations. Only use if you trust all guests.

    .PARAMETER DisableSMT
        Disable Simultaneous Multi-Threading (hyper-threading).

    .PARAMETER EnableSplitLockDetection
        Enable split lock detection. May impact VM performance.

    .PARAMETER EnergyPerfPolicy
        CPU energy-performance policy: Performance, BalancePerformance, BalancePower, Normal, Power.

    .PARAMETER ScalingGovernor
        CPU scaling governor: Performance, OnDemand, PowerSave.

    .PARAMETER RAMPerUnit
        RAM per billing unit in MB.

    .PARAMETER CoresPerUnit
        CPU cores per billing unit.

    .PARAMETER CostPerUnit
        Cost per billing unit.

    .PARAMETER PricePerUnit
        Price per billing unit.

    .PARAMETER MaxRAMPerVM
        Maximum RAM allowed per VM in MB.

    .PARAMETER MaxCoresPerVM
        Maximum CPU cores allowed per VM.

    .PARAMETER TargetRAMPercent
        Target maximum RAM utilization percentage (0-100).

    .PARAMETER RAMOvercommitPercent
        Percentage of reserve RAM to use for machines (0-100).

    .PARAMETER StorageCachePerNode
        Storage cache per node in MB.

    .PARAMETER StorageBufferPerNode
        Storage buffer per node in MB.

    .PARAMETER StorageHugepages
        Allocate hugepages for storage.

    .PARAMETER EnableNVMePowerManagement
        Enable NVMe power management. Some drives have issues with this.

    .PARAMETER SwapTier
        Storage tier used for swap (-1 to disable, 0-5 for tier).

    .PARAMETER SwapPerDrive
        Swap space per drive in MB.

    .PARAMETER MaxCoreTemp
        Maximum core temperature in Celsius.

    .PARAMETER CriticalCoreTemp
        Critical core temperature in Celsius.

    .PARAMETER MaxCoreTempWarnPercent
        Temperature warning threshold percentage.

    .PARAMETER DisableSleep
        Disable CPU sleep states. Increases power usage and heat.

    .PARAMETER LogFilter
        System log filter expression.

    .PARAMETER PassThru
        Return the created cluster object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeCluster -Name "Development"

        Creates a basic cluster named "Development".

    .EXAMPLE
        New-VergeCluster -Name "Production" -Description "Production workloads" -Compute -MaxRAMPerVM 65536 -MaxCoresPerVM 32

        Creates a production cluster with compute enabled and VM resource limits.

    .EXAMPLE
        New-VergeCluster -Name "GPU-Cluster" -NestedVirtualization -AllowVGPUMigration -PassThru

        Creates a cluster with nested virtualization and vGPU support.

    .OUTPUTS
        None by default. Verge.Cluster when -PassThru is specified.

    .NOTES
        After creating a cluster, add nodes using Set-VergeNode to assign them.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [ValidateLength(1, 128)]
        [string]$Name,

        [Parameter()]
        [ValidateLength(0, 2048)]
        [string]$Description,

        [Parameter()]
        [bool]$Enabled = $true,

        [Parameter()]
        [switch]$Compute,

        [Parameter()]
        [switch]$NestedVirtualization,

        [Parameter()]
        [bool]$AllowNestedVirtMigration = $true,

        [Parameter()]
        [switch]$AllowVGPUMigration,

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
        [switch]$DisableCPUSecurityMitigations,

        [Parameter()]
        [switch]$DisableSMT,

        [Parameter()]
        [switch]$EnableSplitLockDetection,

        [Parameter()]
        [ValidateSet('Performance', 'BalancePerformance', 'BalancePower', 'Normal', 'Power')]
        [string]$EnergyPerfPolicy = 'Performance',

        [Parameter()]
        [ValidateSet('Performance', 'OnDemand', 'PowerSave')]
        [string]$ScalingGovernor = 'Performance',

        [Parameter()]
        [ValidateRange(0, 1048576)]
        [int]$RAMPerUnit = 4096,

        [Parameter()]
        [ValidateRange(0, 1024)]
        [int]$CoresPerUnit = 1,

        [Parameter()]
        [ValidateRange(0, [double]::MaxValue)]
        [double]$CostPerUnit = 0,

        [Parameter()]
        [ValidateRange(0, [double]::MaxValue)]
        [double]$PricePerUnit = 0,

        [Parameter()]
        [ValidateRange(0, 1048576)]
        [int]$MaxRAMPerVM = 65536,

        [Parameter()]
        [ValidateRange(0, 1024)]
        [int]$MaxCoresPerVM = 16,

        [Parameter()]
        [ValidateRange(0, 100)]
        [double]$TargetRAMPercent = 80,

        [Parameter()]
        [ValidateRange(0, 100)]
        [double]$RAMOvercommitPercent = 0,

        [Parameter()]
        [ValidateRange(0, 5000000)]
        [int]$StorageCachePerNode,

        [Parameter()]
        [ValidateRange(0, 5000000)]
        [int]$StorageBufferPerNode,

        [Parameter()]
        [bool]$StorageHugepages = $true,

        [Parameter()]
        [switch]$EnableNVMePowerManagement,

        [Parameter()]
        [ValidateRange(-1, 5)]
        [int]$SwapTier = -1,

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
        [int]$MaxCoreTempWarnPercent = 10,

        [Parameter()]
        [switch]$DisableSleep,

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
        # Build request body
        $body = @{
            name                           = $Name
            enabled                        = $Enabled
            compute                        = [bool]$Compute
            kvm_nested                     = [bool]$NestedVirtualization
            allow_nested_virt_migration    = $AllowNestedVirtMigration
            allow_vgpu_migration           = [bool]$AllowVGPUMigration
            disable_cpu_security_mitigations = [bool]$DisableCPUSecurityMitigations
            disable_smt                    = [bool]$DisableSMT
            enable_split_lock_detection    = [bool]$EnableSplitLockDetection
            x86_energy_perf_policy         = $energyPerfMap[$EnergyPerfPolicy]
            scaling_governor               = $scalingGovMap[$ScalingGovernor]
            ram_per_unit                   = $RAMPerUnit
            cores_per_unit                 = $CoresPerUnit
            cost_per_unit                  = $CostPerUnit
            price_per_unit                 = $PricePerUnit
            max_ram_per_vm                 = $MaxRAMPerVM
            max_cores_per_vm               = $MaxCoresPerVM
            target_ram_pct                 = $TargetRAMPercent
            ram_overcommit_pct             = $RAMOvercommitPercent
            storage_hugepages              = $StorageHugepages
            enable_nvme_power_management   = [bool]$EnableNVMePowerManagement
            swap_tier                      = $SwapTier
            disable_sleep                  = [bool]$DisableSleep
            max_core_temp_warn_perc        = $MaxCoreTempWarnPercent
        }

        # Add optional parameters
        if ($Description) {
            $body['description'] = $Description
        }

        if ($DefaultCPUType) {
            $body['default_cpu'] = $DefaultCPUType
        }

        if ($PSBoundParameters.ContainsKey('StorageCachePerNode')) {
            $body['storage_cachesize'] = $StorageCachePerNode
        }

        if ($PSBoundParameters.ContainsKey('StorageBufferPerNode')) {
            $body['storage_buffersize'] = $StorageBufferPerNode
        }

        if ($PSBoundParameters.ContainsKey('SwapPerDrive')) {
            $body['swap_per_drive'] = $SwapPerDrive
        }

        if ($PSBoundParameters.ContainsKey('MaxCoreTemp')) {
            $body['max_core_temp'] = $MaxCoreTemp
        }

        if ($PSBoundParameters.ContainsKey('CriticalCoreTemp')) {
            $body['critical_core_temp'] = $CriticalCoreTemp
        }

        if ($LogFilter) {
            $body['log_filter'] = $LogFilter
        }

        if ($PSCmdlet.ShouldProcess($Name, 'Create Cluster')) {
            try {
                Write-Verbose "Creating cluster '$Name'"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'clusters' -Body $body -Connection $Server

                # Get the created cluster key
                $clusterKey = $response.'$key'
                if (-not $clusterKey -and $response.key) {
                    $clusterKey = $response.key
                }

                Write-Verbose "Cluster '$Name' created with Key: $clusterKey"

                if ($PassThru -and $clusterKey) {
                    # Return the created cluster
                    Start-Sleep -Milliseconds 500
                    Get-VergeCluster -Key $clusterKey -Server $Server
                }
            }
            catch {
                $errorMessage = $_.Exception.Message
                if ($errorMessage -match 'already in use' -or $errorMessage -match 'unique') {
                    throw "A cluster with the name '$Name' already exists."
                }
                throw "Failed to create cluster '$Name': $errorMessage"
            }
        }
    }
}
