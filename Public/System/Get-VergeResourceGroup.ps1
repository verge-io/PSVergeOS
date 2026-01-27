function Get-VergeResourceGroup {
    <#
    .SYNOPSIS
        Retrieves resource groups from VergeOS.

    .DESCRIPTION
        Get-VergeResourceGroup retrieves resource groups that define collections of
        hardware devices (GPU, PCI, USB, SR-IOV NIC, vGPU) that can be assigned to VMs.

    .PARAMETER Name
        The name of the resource group to retrieve. Supports wildcards (* and ?).
        If not specified, all resource groups are returned.

    .PARAMETER Key
        The unique key (ID) of the resource group to retrieve.

    .PARAMETER UUID
        The UUID of the resource group to retrieve.

    .PARAMETER Type
        Filter resource groups by device type:
        - PCI: PCI passthrough devices
        - SRIOVNIC: SR-IOV network interface devices
        - USB: USB devices
        - HostGPU: Host GPU passthrough
        - NVIDIAvGPU: NVIDIA virtual GPU devices

    .PARAMETER Class
        Filter resource groups by device class:
        - GPU, vGPU, Storage, HID, USB, Network, Media, Audio, FPGA, PCI, Unknown

    .PARAMETER Enabled
        Filter to show only enabled or disabled resource groups.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeResourceGroup

        Retrieves all resource groups from the connected VergeOS system.

    .EXAMPLE
        Get-VergeResourceGroup -Name "GPU Pool"

        Retrieves a specific resource group by name.

    .EXAMPLE
        Get-VergeResourceGroup -Type HostGPU

        Retrieves all host GPU passthrough resource groups.

    .EXAMPLE
        Get-VergeResourceGroup -Class GPU -Enabled $true

        Retrieves all enabled GPU class resource groups.

    .EXAMPLE
        Get-VergeResourceGroup -Name "*nvidia*"

        Retrieves resource groups with "nvidia" in the name.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.ResourceGroup'

    .NOTES
        Resource groups are read-only in this module. They are typically configured
        through the VergeOS UI and associate physical devices with virtual machines.

        Device Types:
        - PCI: General PCI passthrough (network cards, storage controllers, etc.)
        - SRIOVNIC: SR-IOV enabled NICs for direct network virtualization
        - USB: USB device passthrough
        - HostGPU: Full GPU passthrough to a single VM
        - NVIDIAvGPU: NVIDIA vGPU for GPU sharing across multiple VMs
    #>
    [CmdletBinding(DefaultParameterSetName = 'Filter')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ParameterSetName = 'Filter')]
        [SupportsWildcards()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey', ValueFromPipelineByPropertyName)]
        [Alias('Id', '$key')]
        [int]$Key,

        [Parameter(Mandatory, ParameterSetName = 'ByUUID')]
        [ValidatePattern('^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$')]
        [string]$UUID,

        [Parameter(ParameterSetName = 'Filter')]
        [ValidateSet('PCI', 'SRIOVNIC', 'USB', 'HostGPU', 'NVIDIAvGPU')]
        [string]$Type,

        [Parameter(ParameterSetName = 'Filter')]
        [ValidateSet('GPU', 'vGPU', 'Storage', 'HID', 'USB', 'Network', 'Media', 'Audio', 'FPGA', 'PCI', 'Unknown')]
        [string]$Class,

        [Parameter(ParameterSetName = 'Filter')]
        [bool]$Enabled,

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

        # Map friendly type names to API values
        $typeMapping = @{
            'PCI'        = 'node_pci_devices'
            'SRIOVNIC'   = 'node_sriov_nic_devices'
            'USB'        = 'node_usb_devices'
            'HostGPU'    = 'node_host_gpu_devices'
            'NVIDIAvGPU' = 'node_nvidia_vgpu_devices'
        }

        # Map API type values to friendly names
        $typeDisplayMapping = @{
            'node_pci_devices'         = 'PCI'
            'node_sriov_nic_devices'   = 'SR-IOV NIC'
            'node_usb_devices'         = 'USB'
            'node_host_gpu_devices'    = 'Host GPU'
            'node_nvidia_vgpu_devices' = 'NVIDIA vGPU'
        }

        # Map friendly class names to API values
        $classMapping = @{
            'GPU'     = 'gpu'
            'vGPU'    = 'vgpu'
            'Storage' = 'storage'
            'HID'     = 'hid'
            'USB'     = 'usb'
            'Network' = 'network'
            'Media'   = 'media'
            'Audio'   = 'audio'
            'FPGA'    = 'fpga'
            'PCI'     = 'pci'
            'Unknown' = 'unknown'
        }

        # Map API class values to friendly names
        $classDisplayMapping = @{
            'gpu'     = 'GPU'
            'vgpu'    = 'vGPU'
            'storage' = 'Storage'
            'hid'     = 'Human Input Device'
            'usb'     = 'USB'
            'network' = 'Network'
            'media'   = 'Media'
            'audio'   = 'Audio'
            'fpga'    = 'FPGA'
            'pci'     = 'PCI'
            'unknown' = 'Unknown'
        }
    }

    process {
        try {
            Write-Verbose "Querying resource groups from $($Server.Server)"

            # Build query parameters
            $queryParams = @{}
            $filters = [System.Collections.Generic.List[string]]::new()

            switch ($PSCmdlet.ParameterSetName) {
                'ByKey' {
                    $filters.Add("`$key eq $Key")
                }
                'ByUUID' {
                    $filters.Add("uuid eq '$($UUID.ToLower())'")
                }
                'Filter' {
                    # Filter by name
                    if ($Name) {
                        if ($Name -match '[\*\?]') {
                            # Wildcard search
                            $searchTerm = $Name -replace '[\*\?]', ''
                            if ($searchTerm) {
                                $filters.Add("name ct '$searchTerm'")
                            }
                        }
                        else {
                            $filters.Add("name eq '$Name'")
                        }
                    }

                    # Filter by type
                    if ($Type) {
                        $apiType = $typeMapping[$Type]
                        $filters.Add("type eq '$apiType'")
                    }

                    # Filter by class
                    if ($Class) {
                        $apiClass = $classMapping[$Class]
                        $filters.Add("class eq '$apiClass'")
                    }

                    # Filter by enabled status
                    if ($PSBoundParameters.ContainsKey('Enabled')) {
                        $filters.Add("enabled eq $($Enabled.ToString().ToLower())")
                    }
                }
            }

            # Apply filters
            if ($filters.Count -gt 0) {
                $queryParams['filter'] = $filters -join ' and '
            }

            # Request fields
            $queryParams['fields'] = '$key,uuid,name,description,type,class,enabled,created,modified'

            $response = Invoke-VergeAPI -Method GET -Endpoint 'resource_groups' -Query $queryParams -Connection $Server

            # Handle both single object and array responses
            $groups = if ($response -is [array]) { $response } else { @($response) }

            foreach ($group in $groups) {
                # Skip null entries
                if (-not $group -or (-not $group.'$key' -and -not $group.uuid)) {
                    continue
                }

                # Apply wildcard filtering for client-side matching
                if ($Name -and ($Name -match '[\*\?]')) {
                    if ($group.name -notlike $Name) {
                        continue
                    }
                }

                # Get type display name
                $typeDisplay = $typeDisplayMapping[$group.type]
                if (-not $typeDisplay) {
                    $typeDisplay = $group.type
                }

                # Get class display name
                $classDisplay = $classDisplayMapping[$group.class]
                if (-not $classDisplay) {
                    $classDisplay = $group.class
                }

                # Create output object
                $output = [PSCustomObject]@{
                    PSTypeName   = 'Verge.ResourceGroup'
                    Key          = if ($group.'$key') { [int]$group.'$key' } else { $null }
                    UUID         = $group.uuid
                    Name         = $group.name
                    Description  = $group.description
                    Type         = $typeDisplay
                    TypeValue    = $group.type
                    Class        = $classDisplay
                    ClassValue   = $group.class
                    Enabled      = [bool]$group.enabled
                    Created      = if ($group.created) { [DateTimeOffset]::FromUnixTimeSeconds($group.created).LocalDateTime } else { $null }
                    Modified     = if ($group.modified) { [DateTimeOffset]::FromUnixTimeSeconds($group.modified).LocalDateTime } else { $null }
                }

                # Add hidden properties for pipeline support
                $output | Add-Member -MemberType NoteProperty -Name '_Connection' -Value $Server -Force

                Write-Output $output
            }
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}
