function Get-VergeNodeDevice {
    <#
    .SYNOPSIS
        Retrieves hardware devices from VergeOS nodes.

    .DESCRIPTION
        Get-VergeNodeDevice retrieves PCI, USB, and GPU devices from VergeOS nodes.
        This includes network controllers, display controllers, storage controllers,
        USB devices, and other hardware attached to the nodes.

    .PARAMETER Node
        The name of the node to retrieve devices for. Supports wildcards (* and ?).
        If not specified, devices for all nodes are returned.

    .PARAMETER NodeObject
        A node object from Get-VergeNode to retrieve devices for.

    .PARAMETER DeviceType
        Filter by device type: PCI, USB, or GPU.

    .PARAMETER DeviceClass
        Filter PCI devices by class. Common values include:
        - 'Network controller'
        - 'Display controller'
        - 'Mass storage controller'
        - 'Serial bus controller'

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeNodeDevice

        Retrieves all devices from all nodes.

    .EXAMPLE
        Get-VergeNodeDevice -Node "node1"

        Retrieves all devices from node1.

    .EXAMPLE
        Get-VergeNodeDevice -DeviceType PCI

        Retrieves all PCI devices from all nodes.

    .EXAMPLE
        Get-VergeNodeDevice -DeviceType PCI -DeviceClass "Display controller"

        Retrieves all GPUs/display controllers.

    .EXAMPLE
        Get-VergeNode -Name "node1" | Get-VergeNodeDevice -DeviceType USB

        Retrieves USB devices from node1 using pipeline input.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.NodeDevice'

    .NOTES
        PCI devices can be used for GPU passthrough when IOMMU is enabled.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Filter')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ParameterSetName = 'Filter')]
        [SupportsWildcards()]
        [string]$Node,

        [Parameter(Mandatory, ParameterSetName = 'ByNode', ValueFromPipeline)]
        [PSTypeName('Verge.Node')]
        [PSCustomObject]$NodeObject,

        [Parameter()]
        [ValidateSet('PCI', 'USB', 'GPU')]
        [string]$DeviceType,

        [Parameter()]
        [string]$DeviceClass,

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
        try {
            Write-Verbose "Querying node devices from $($Server.Server)"

            # Resolve node key if needed
            $nodeKey = $null
            if ($PSCmdlet.ParameterSetName -eq 'ByNode') {
                $nodeKey = $NodeObject.Key
                if ($NodeObject._Connection) {
                    $Server = $NodeObject._Connection
                }
            }
            elseif ($Node) {
                $nodeObj = Get-VergeNode -Name $Node -Server $Server | Select-Object -First 1
                if ($nodeObj) {
                    $nodeKey = $nodeObj.Key
                }
                else {
                    Write-Warning "Node '$Node' not found"
                    return
                }
            }

            # Determine which endpoints to query based on DeviceType
            $endpoints = @()
            if (-not $DeviceType -or $DeviceType -eq 'PCI') {
                $endpoints += 'node_pci_devices'
            }
            if (-not $DeviceType -or $DeviceType -eq 'USB') {
                $endpoints += 'node_usb_devices'
            }
            if ($DeviceType -eq 'GPU') {
                # GPUs are a subset of PCI devices - use display controllers
                $endpoints = @('node_pci_devices')
            }

            foreach ($endpoint in $endpoints) {
                $queryParams = @{}
                $filters = [System.Collections.Generic.List[string]]::new()

                # Filter by node
                if ($nodeKey) {
                    $filters.Add("node eq $nodeKey")
                }

                # Filter by device class (PCI only)
                if ($DeviceClass -and $endpoint -eq 'node_pci_devices') {
                    $filters.Add("class ct '$DeviceClass'")
                }

                # Filter for GPUs specifically
                if ($DeviceType -eq 'GPU' -and $endpoint -eq 'node_pci_devices') {
                    $filters.Add("device_type eq '03'")  # 03 = Display controller
                }

                # Apply filters
                if ($filters.Count -gt 0) {
                    $queryParams['filter'] = $filters -join ' and '
                }

                # Set fields based on endpoint type
                if ($endpoint -eq 'node_pci_devices') {
                    $queryParams['fields'] = @(
                        '$key'
                        'node'
                        'node#name as node_name'
                        'name'
                        'slot'
                        'class'
                        'class_hex'
                        'device_type'
                        'vendor'
                        'device'
                        'vendor_device_hex'
                        'svendor'
                        'subsystem_device'
                        'physical_slot'
                        'driver'
                        'module'
                        'numa'
                        'iommu_group'
                        'sriov_totalvfs'
                        'sriov_numvfs'
                    ) -join ','
                }
                else {
                    # USB devices
                    $queryParams['fields'] = @(
                        '$key'
                        'node'
                        'node#name as node_name'
                        'bus'
                        'device'
                        'path'
                        'devpath'
                        'vendor'
                        'vendor_id'
                        'model'
                        'model_id'
                        'serial'
                        'usb_version'
                        'speed'
                        'interface_drivers'
                    ) -join ','
                }

                $response = Invoke-VergeAPI -Method GET -Endpoint $endpoint -Query $queryParams -Connection $Server

                # Handle both single object and array responses
                $devices = if ($response -is [array]) { $response } else { @($response) }

                foreach ($device in $devices) {
                    # Skip null entries
                    if (-not $device) {
                        continue
                    }

                    # Determine device type for output
                    $type = if ($endpoint -eq 'node_pci_devices') { 'PCI' } else { 'USB' }

                    # Build common output object
                    $output = [PSCustomObject]@{
                        PSTypeName     = 'Verge.NodeDevice'
                        Key            = [int]$device.'$key'
                        Node           = $device.node_name
                        NodeKey        = $device.node
                        Type           = $type
                    }

                    if ($type -eq 'PCI') {
                        # Add PCI-specific properties
                        $output | Add-Member -MemberType NoteProperty -Name 'Name' -Value $device.name
                        $output | Add-Member -MemberType NoteProperty -Name 'Slot' -Value $device.slot
                        $output | Add-Member -MemberType NoteProperty -Name 'Class' -Value $device.class
                        $output | Add-Member -MemberType NoteProperty -Name 'ClassHex' -Value $device.class_hex
                        $output | Add-Member -MemberType NoteProperty -Name 'DeviceTypeCode' -Value $device.device_type
                        $output | Add-Member -MemberType NoteProperty -Name 'Vendor' -Value $device.vendor
                        $output | Add-Member -MemberType NoteProperty -Name 'Device' -Value $device.device
                        $output | Add-Member -MemberType NoteProperty -Name 'VendorDeviceHex' -Value $device.vendor_device_hex
                        $output | Add-Member -MemberType NoteProperty -Name 'SubsystemVendor' -Value $device.svendor
                        $output | Add-Member -MemberType NoteProperty -Name 'SubsystemDevice' -Value $device.subsystem_device
                        $output | Add-Member -MemberType NoteProperty -Name 'PhysicalSlot' -Value $device.physical_slot
                        $output | Add-Member -MemberType NoteProperty -Name 'Driver' -Value $device.driver
                        $output | Add-Member -MemberType NoteProperty -Name 'Module' -Value $device.module
                        $output | Add-Member -MemberType NoteProperty -Name 'NUMA' -Value $device.numa
                        $output | Add-Member -MemberType NoteProperty -Name 'IOMMUGroup' -Value $device.iommu_group
                        $output | Add-Member -MemberType NoteProperty -Name 'SRIOVTotalVFs' -Value ([int]$device.sriov_totalvfs)
                        $output | Add-Member -MemberType NoteProperty -Name 'SRIOVNumVFs' -Value ([int]$device.sriov_numvfs)
                    }
                    else {
                        # Add USB-specific properties
                        $output | Add-Member -MemberType NoteProperty -Name 'Name' -Value $device.model
                        $output | Add-Member -MemberType NoteProperty -Name 'Bus' -Value $device.bus
                        $output | Add-Member -MemberType NoteProperty -Name 'DeviceNum' -Value $device.device
                        $output | Add-Member -MemberType NoteProperty -Name 'Path' -Value $device.path
                        $output | Add-Member -MemberType NoteProperty -Name 'DevPath' -Value $device.devpath
                        $output | Add-Member -MemberType NoteProperty -Name 'Vendor' -Value $device.vendor
                        $output | Add-Member -MemberType NoteProperty -Name 'VendorID' -Value $device.vendor_id
                        $output | Add-Member -MemberType NoteProperty -Name 'Model' -Value $device.model
                        $output | Add-Member -MemberType NoteProperty -Name 'ModelID' -Value $device.model_id
                        $output | Add-Member -MemberType NoteProperty -Name 'Serial' -Value $device.serial
                        $output | Add-Member -MemberType NoteProperty -Name 'USBVersion' -Value $device.usb_version
                        $output | Add-Member -MemberType NoteProperty -Name 'Speed' -Value $device.speed
                        $output | Add-Member -MemberType NoteProperty -Name 'InterfaceDrivers' -Value $device.interface_drivers
                    }

                    # Add hidden properties for pipeline support
                    $output | Add-Member -MemberType NoteProperty -Name '_Connection' -Value $Server -Force

                    Write-Output $output
                }
            }
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}
