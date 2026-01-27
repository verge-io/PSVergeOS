function New-VergeVM {
    <#
    .SYNOPSIS
        Creates a new virtual machine in VergeOS.

    .DESCRIPTION
        New-VergeVM creates a new virtual machine with the specified configuration.
        The VM is created in a stopped state by default. Use -PowerOn to start
        the VM immediately after creation.

    .PARAMETER Name
        The name of the new VM. Must be unique and 1-128 characters.

    .PARAMETER Description
        An optional description for the VM.

    .PARAMETER CPUCores
        The number of CPU cores for the VM. Default is 1. Range: 1-1024.

    .PARAMETER RAM
        The amount of RAM in MB. Default is 1024. Range: 256-1048576.
        Value will be normalized to 256 MB increments.

    .PARAMETER OSFamily
        The operating system family. Valid values: Linux, Windows, FreeBSD, Other.
        Default is Linux.

    .PARAMETER Cluster
        The name or key of the cluster to place the VM in.

    .PARAMETER CPUType
        The CPU type to emulate. Common values include:
        - host: Use host CPU (best performance)
        - qemu64: Generic QEMU CPU
        - Haswell, Broadwell, Skylake-Server: Intel CPU types
        - EPYC, EPYC-Rome, EPYC-Milan: AMD CPU types

    .PARAMETER MachineType
        The machine/chipset type. Default is 'pc-q35-10.0' (Q35 + ICH9).
        Use 'pc' for legacy i440FX compatibility.

    .PARAMETER UEFI
        Enable UEFI boot instead of legacy BIOS.

    .PARAMETER SecureBoot
        Enable Secure Boot (requires UEFI).

    .PARAMETER GuestAgent
        Enable QEMU Guest Agent support for enhanced VM management.

    .PARAMETER Console
        The console type. Valid values: VNC, Spice, Serial, None. Default is VNC.

    .PARAMETER Video
        The video card type. Valid values: Standard, Cirrus, VMware, QXL, Virtio, None.
        Default is Standard.

    .PARAMETER BootOrder
        The boot device order. Valid values:
        - DiskCD: Disk, then CD-ROM (default)
        - DiskCDNetwork: Disk, CD-ROM, Network
        - CDDisk: CD-ROM, then Disk
        - NetworkDisk: Network, then Disk
        - Network: Network only
        - Disk: Disk only
        - CD: CD-ROM only

    .PARAMETER CloudInit
        Enable cloud-init datasource for VM provisioning. Valid values:
        - None: Disabled (default)
        - ConfigDrive: Config Drive v2 - Standard cloud-init config drive
        - NoCloud: NoCloud datasource

        When enabled, the VM will look for cloud-init files (/user-data, /meta-data,
        /network-config) to configure itself on first boot. Use New-VergeCloudInitFile
        to create the configuration files.

    .PARAMETER SnapshotProfile
        The name or key of a snapshot profile to assign.

    .PARAMETER Enabled
        Whether the VM is enabled. Default is $true.

    .PARAMETER PowerOn
        Start the VM immediately after creation.

    .PARAMETER PassThru
        Return the created VM object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeVM -Name "WebServer01"

        Creates a VM with default settings (1 CPU, 1GB RAM, Linux).

    .EXAMPLE
        New-VergeVM -Name "WebServer01" -CPUCores 4 -RAM 8192 -OSFamily Linux

        Creates a Linux VM with 4 cores and 8GB RAM.

    .EXAMPLE
        New-VergeVM -Name "WinServer" -CPUCores 4 -RAM 16384 -OSFamily Windows -UEFI -PowerOn

        Creates a Windows VM with UEFI and starts it immediately.

    .EXAMPLE
        New-VergeVM -Name "Database01" -CPUCores 8 -RAM 32768 -GuestAgent -SnapshotProfile "Hourly" -PassThru

        Creates a VM with guest agent and snapshot profile, returning the VM object.

    .EXAMPLE
        $vmParams = @{
            Name = "AppServer"
            CPUCores = 4
            RAM = 8192
            OSFamily = "Linux"
            UEFI = $true
            GuestAgent = $true
            Cluster = "Production"
        }
        New-VergeVM @vmParams -PassThru

        Creates a VM using splatting for cleaner parameter passing.

    .EXAMPLE
        New-VergeVM -Name "CloudServer" -CPUCores 2 -RAM 2048 -OSFamily Linux -UEFI -CloudInit ConfigDrive -PassThru

        Creates a VM with cloud-init Config Drive enabled. After creating the VM,
        use New-VergeCloudInitFile to add /user-data, /meta-data, and /network-config files.

    .OUTPUTS
        None by default. Verge.VM when -PassThru is specified.

    .NOTES
        The VM is created without drives or NICs. Use New-VergeDrive and New-VergeNIC
        to add storage and networking after creation.
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
        [ValidateRange(1, 1024)]
        [int]$CPUCores = 1,

        [Parameter()]
        [ValidateRange(256, 1048576)]
        [int]$RAM = 1024,

        [Parameter()]
        [ValidateSet('Linux', 'Windows', 'FreeBSD', 'Other')]
        [string]$OSFamily = 'Linux',

        [Parameter()]
        [string]$Cluster,

        [Parameter()]
        [string]$CPUType,

        [Parameter()]
        [string]$MachineType,

        [Parameter()]
        [switch]$UEFI,

        [Parameter()]
        [switch]$SecureBoot,

        [Parameter()]
        [switch]$GuestAgent,

        [Parameter()]
        [ValidateSet('VNC', 'Spice', 'Serial', 'None')]
        [string]$Console = 'VNC',

        [Parameter()]
        [ValidateSet('Standard', 'Cirrus', 'VMware', 'QXL', 'Virtio', 'None')]
        [string]$Video = 'Standard',

        [Parameter()]
        [ValidateSet('DiskCD', 'DiskCDNetwork', 'CDDisk', 'NetworkDisk', 'Network', 'Disk', 'CD')]
        [string]$BootOrder = 'DiskCD',

        [Parameter()]
        [ValidateSet('None', 'ConfigDrive', 'NoCloud')]
        [string]$CloudInit = 'None',

        [Parameter()]
        [string]$SnapshotProfile,

        [Parameter()]
        [bool]$Enabled = $true,

        [Parameter()]
        [switch]$PowerOn,

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
        $osFamilyMap = @{
            'Linux'   = 'linux'
            'Windows' = 'windows'
            'FreeBSD' = 'freebsd'
            'Other'   = 'other'
        }

        $consoleMap = @{
            'VNC'    = 'vnc'
            'Spice'  = 'spice'
            'Serial' = 'serial'
            'None'   = 'none'
        }

        $videoMap = @{
            'Standard' = 'std'
            'Cirrus'   = 'cirrus'
            'VMware'   = 'vmware'
            'QXL'      = 'qxl'
            'Virtio'   = 'virtio'
            'None'     = 'none'
        }

        $bootOrderMap = @{
            'DiskCD'        = 'cd'
            'DiskCDNetwork' = 'cdn'
            'CDDisk'        = 'dc'
            'NetworkDisk'   = 'nc'
            'Network'       = 'n'
            'Disk'          = 'c'
            'CD'            = 'd'
        }

        $cloudInitMap = @{
            'None'        = 'none'
            'ConfigDrive' = 'config_drive_v2'
            'NoCloud'     = 'nocloud'
        }
    }

    process {
        # Normalize RAM to 256 MB increments
        $normalizedRAM = [Math]::Ceiling($RAM / 256) * 256
        if ($normalizedRAM -ne $RAM) {
            Write-Verbose "RAM normalized from $RAM MB to $normalizedRAM MB (256 MB increments)"
        }

        # Build request body with required and specified fields
        $body = @{
            name       = $Name
            cpu_cores  = $CPUCores
            ram        = $normalizedRAM
            os_family  = $osFamilyMap[$OSFamily]
            enabled    = $Enabled
            console    = $consoleMap[$Console]
            video      = $videoMap[$Video]
            boot_order = $bootOrderMap[$BootOrder]
        }

        # Add optional parameters
        if ($Description) {
            $body['description'] = $Description
        }

        if ($UEFI) {
            $body['uefi'] = $true
        }

        if ($SecureBoot) {
            if (-not $UEFI) {
                Write-Warning "Secure Boot requires UEFI. Enabling UEFI automatically."
                $body['uefi'] = $true
            }
            $body['secure_boot'] = $true
        }

        if ($GuestAgent) {
            $body['guest_agent'] = $true
        }

        if ($CloudInit -ne 'None') {
            $body['cloudinit_datasource'] = $cloudInitMap[$CloudInit]
        }

        if ($CPUType) {
            $body['cpu_type'] = $CPUType
        }

        if ($MachineType) {
            $body['machine_type'] = $MachineType
        }

        # Resolve cluster if specified
        if ($Cluster) {
            # Check if it's a numeric key or name
            if ($Cluster -match '^\d+$') {
                $body['cluster'] = [int]$Cluster
            }
            else {
                # Look up cluster by name
                try {
                    $clusterResponse = Invoke-VergeAPI -Method GET -Endpoint 'clusters' -Query @{
                        filter = "name eq '$Cluster'"
                        fields = '$key,name'
                    } -Connection $Server

                    if ($clusterResponse -and $clusterResponse.'$key') {
                        $body['cluster'] = $clusterResponse.'$key'
                    }
                    elseif ($clusterResponse -is [array] -and $clusterResponse.Count -gt 0) {
                        $body['cluster'] = $clusterResponse[0].'$key'
                    }
                    else {
                        throw "Cluster '$Cluster' not found"
                    }
                }
                catch {
                    throw "Failed to resolve cluster '$Cluster': $($_.Exception.Message)"
                }
            }
        }

        # Resolve snapshot profile if specified
        if ($SnapshotProfile) {
            if ($SnapshotProfile -match '^\d+$') {
                $body['snapshot_profile'] = [int]$SnapshotProfile
            }
            else {
                try {
                    $profileResponse = Invoke-VergeAPI -Method GET -Endpoint 'snapshot_profiles' -Query @{
                        filter = "name eq '$SnapshotProfile'"
                        fields = '$key,name'
                    } -Connection $Server

                    if ($profileResponse -and $profileResponse.'$key') {
                        $body['snapshot_profile'] = $profileResponse.'$key'
                    }
                    elseif ($profileResponse -is [array] -and $profileResponse.Count -gt 0) {
                        $body['snapshot_profile'] = $profileResponse[0].'$key'
                    }
                    else {
                        throw "Snapshot profile '$SnapshotProfile' not found"
                    }
                }
                catch {
                    throw "Failed to resolve snapshot profile '$SnapshotProfile': $($_.Exception.Message)"
                }
            }
        }

        # Confirm action
        $actionDescription = "Create VM '$Name' with $CPUCores CPU(s), $($normalizedRAM)MB RAM, $OSFamily"
        if ($PSCmdlet.ShouldProcess($Name, 'Create VM')) {
            try {
                Write-Verbose "Creating VM '$Name'"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'vms' -Body $body -Connection $Server

                # Get the created VM key
                $vmKey = $response.'$key'
                if (-not $vmKey -and $response.key) {
                    $vmKey = $response.key
                }

                Write-Verbose "VM '$Name' created with Key: $vmKey"

                # Power on if requested
                if ($PowerOn -and $vmKey) {
                    Write-Verbose "Powering on VM '$Name'"
                    $powerBody = @{
                        vm     = $vmKey
                        action = 'poweron'
                    }
                    Invoke-VergeAPI -Method POST -Endpoint 'vm_actions' -Body $powerBody -Connection $Server | Out-Null
                }

                if ($PassThru -and $vmKey) {
                    # Return the created VM
                    Start-Sleep -Milliseconds 500
                    Get-VergeVM -Key $vmKey -Server $Server
                }
            }
            catch {
                $errorMessage = $_.Exception.Message
                if ($errorMessage -match 'already in use') {
                    throw "A VM with the name '$Name' already exists."
                }
                throw "Failed to create VM '$Name': $errorMessage"
            }
        }
    }
}
