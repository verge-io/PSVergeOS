function New-VergeNIC {
    <#
    .SYNOPSIS
        Adds a new network interface to a VergeOS virtual machine.

    .DESCRIPTION
        New-VergeNIC creates a new virtual network interface and attaches it to a VM.
        The NIC can be connected to a virtual network (vnet) and configured with
        various interface types.

    .PARAMETER VM
        A VM object from Get-VergeVM. Accepts pipeline input.

    .PARAMETER VMName
        The name of the VM to add the NIC to.

    .PARAMETER VMKey
        The key (ID) of the VM to add the NIC to.

    .PARAMETER Name
        The name for the new NIC. If not specified, uses auto-generated name.

    .PARAMETER NetworkKey
        The key (ID) of the virtual network to connect to.

    .PARAMETER NetworkName
        The name of the virtual network to connect to.

    .PARAMETER Interface
        The NIC interface type. Default is 'virtio'.
        Valid values: virtio, e1000, e1000e, rtl8139, pcnet, igb, vmxnet3

    .PARAMETER MACAddress
        A specific MAC address to assign. If not specified, one is auto-generated.
        Format: xx:xx:xx:xx:xx:xx

    .PARAMETER IPAddress
        A static IP address to assign to the NIC (requires DHCP reservation).

    .PARAMETER Description
        An optional description for the NIC.

    .PARAMETER Disabled
        Create the NIC in disabled state.

    .PARAMETER PassThru
        Return the created NIC object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeNIC -VMName "WebServer01" -NetworkName "Internal"

        Adds a NIC connected to the "Internal" network.

    .EXAMPLE
        New-VergeNIC -VMName "WebServer01" -NetworkKey 5 -Interface e1000e

        Adds an Intel e1000e NIC connected to network with key 5.

    .EXAMPLE
        Get-VergeVM -Name "Web*" | New-VergeNIC -NetworkName "DMZ" -PassThru

        Adds a NIC to all web servers and returns the created NICs.

    .EXAMPLE
        New-VergeNIC -VMName "LegacyApp" -NetworkName "Internal" -Interface vmxnet3

        Adds a VMware-compatible NIC for migrated workloads.

    .OUTPUTS
        None by default. Verge.NIC when -PassThru is specified.

    .NOTES
        The VM should be powered off when adding NICs for best results,
        though hot-add may be supported depending on configuration.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByVMName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByVMObject')]
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByVMObjectNetKey')]
        [PSTypeName('Verge.VM')]
        [PSCustomObject]$VM,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByVMName')]
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByVMNameNetKey')]
        [string]$VMName,

        [Parameter(Mandatory, ParameterSetName = 'ByVMKey')]
        [Parameter(Mandatory, ParameterSetName = 'ByVMKeyNetKey')]
        [int]$VMKey,

        [Parameter()]
        [ValidateLength(1, 128)]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByVMNameNetKey')]
        [Parameter(Mandatory, ParameterSetName = 'ByVMKeyNetKey')]
        [Parameter(Mandatory, ParameterSetName = 'ByVMObjectNetKey')]
        [int]$NetworkKey,

        [Parameter(ParameterSetName = 'ByVMName')]
        [Parameter(ParameterSetName = 'ByVMKey')]
        [Parameter(ParameterSetName = 'ByVMObject')]
        [string]$NetworkName,

        [Parameter()]
        [ValidateSet('virtio', 'e1000', 'e1000e', 'rtl8139', 'pcnet', 'igb', 'vmxnet3')]
        [string]$Interface = 'virtio',

        [Parameter()]
        [ValidatePattern('^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$')]
        [string]$MACAddress,

        [Parameter()]
        [string]$IPAddress,

        [Parameter()]
        [ValidateLength(0, 2048)]
        [string]$Description,

        [Parameter()]
        [switch]$Disabled,

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

        # Resolve network by name if provided
        $resolvedNetworkKey = $null
        if ($NetworkKey) {
            $resolvedNetworkKey = $NetworkKey
        }
        elseif ($NetworkName) {
            try {
                $networks = Invoke-VergeAPI -Method GET -Endpoint "vnets?name=$NetworkName" -Connection $Server
                if ($networks -and $networks.Count -gt 0) {
                    $net = $networks | Select-Object -First 1
                    $resolvedNetworkKey = $net.'$key' ?? $net.key
                    Write-Verbose "Resolved network '$NetworkName' to key $resolvedNetworkKey"
                }
                else {
                    throw "Network '$NetworkName' not found"
                }
            }
            catch {
                throw "Failed to resolve network '$NetworkName': $($_.Exception.Message)"
            }
        }
    }

    process {
        # Resolve VM based on parameter set
        $targetVMs = switch -Wildcard ($PSCmdlet.ParameterSetName) {
            'ByVMName*' {
                Get-VergeVM -Name $VMName -Server $Server
            }
            'ByVMKey*' {
                Get-VergeVM -Key $VMKey -Server $Server
            }
            'ByVMObject*' {
                $VM
            }
        }

        foreach ($targetVM in $targetVMs) {
            if (-not $targetVM) {
                continue
            }

            # Check if VM is a snapshot
            if ($targetVM.IsSnapshot) {
                Write-Error -Message "Cannot add NIC to '$($targetVM.Name)': VM is a snapshot" -ErrorId 'CannotModifySnapshot'
                continue
            }

            # Build request body
            $body = @{
                machine   = $targetVM.MachineKey
                interface = $Interface
                enabled   = -not $Disabled.IsPresent
            }

            if ($Name) {
                $body['name'] = $Name
            }

            if ($resolvedNetworkKey) {
                $body['vnet'] = $resolvedNetworkKey
            }

            if ($MACAddress) {
                $body['macaddress'] = $MACAddress.ToLower()
            }

            if ($IPAddress) {
                $body['ipaddress'] = $IPAddress
            }

            if ($Description) {
                $body['description'] = $Description
            }

            $nicDesc = if ($Name) { $Name } else { 'NIC' }
            $netDesc = if ($NetworkName) { " on '$NetworkName'" } elseif ($resolvedNetworkKey) { " on network $resolvedNetworkKey" } else { '' }

            if ($PSCmdlet.ShouldProcess($targetVM.Name, "Add $nicDesc ($Interface)$netDesc")) {
                try {
                    Write-Verbose "Adding NIC to VM '$($targetVM.Name)'"
                    $response = Invoke-VergeAPI -Method POST -Endpoint 'machine_nics' -Body $body -Connection $Server

                    if ($response) {
                        Write-Verbose "NIC added successfully with key: $($response.'$key' ?? $response.key ?? 'unknown')"

                        if ($PassThru) {
                            # Return the NIC using Get-VergeNIC
                            $nicKey = $response.'$key' ?? $response.key
                            if ($nicKey) {
                                Get-VergeNIC -VM $targetVM -Server $Server | Where-Object { $_.Key -eq $nicKey }
                            }
                        }
                    }
                }
                catch {
                    Write-Error -Message "Failed to add NIC to VM '$($targetVM.Name)': $($_.Exception.Message)" -ErrorId 'NICAddFailed'
                }
            }
        }
    }
}
