function Set-VergeNIC {
    <#
    .SYNOPSIS
        Modifies a VergeOS virtual machine network interface configuration.

    .DESCRIPTION
        Set-VergeNIC updates the configuration of an existing VM NIC.
        Can change network, interface type, MAC address, and other settings.

    .PARAMETER NIC
        A NIC object from Get-VergeNIC. Accepts pipeline input.

    .PARAMETER Key
        The key (ID) of the NIC to modify.

    .PARAMETER Name
        The new name for the NIC.

    .PARAMETER NetworkKey
        The key (ID) of the virtual network to connect to.

    .PARAMETER NetworkName
        The name of the virtual network to connect to.

    .PARAMETER Interface
        The NIC interface type.
        Valid values: virtio, e1000, e1000e, rtl8139, pcnet, igb, vmxnet3

    .PARAMETER MACAddress
        A new MAC address to assign. Format: xx:xx:xx:xx:xx:xx

    .PARAMETER IPAddress
        A static IP address to assign (requires DHCP reservation).

    .PARAMETER Description
        The description for the NIC.

    .PARAMETER Enabled
        Enable or disable the NIC.

    .PARAMETER PassThru
        Return the modified NIC object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeNIC -VMName "WebServer01" -Name "nic_0" | Set-VergeNIC -NetworkName "DMZ"

        Moves the NIC to the DMZ network.

    .EXAMPLE
        Set-VergeNIC -Key 123 -Interface e1000e -PassThru

        Changes the interface type to e1000e and returns the updated object.

    .EXAMPLE
        Get-VergeNIC -VMName "WebServer01" | Set-VergeNIC -Enabled $false

        Disables all NICs on the VM.

    .EXAMPLE
        Set-VergeNIC -Key 456 -IPAddress "10.0.0.100"

        Assigns a static IP address to the NIC.

    .OUTPUTS
        None by default. Verge.NIC when -PassThru is specified.

    .NOTES
        Some changes may require the VM to be powered off.
        Changing MAC addresses may affect DHCP reservations.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByNIC')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByNIC')]
        [PSTypeName('Verge.NIC')]
        [PSCustomObject]$NIC,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter()]
        [ValidateLength(1, 128)]
        [string]$Name,

        [Parameter()]
        [int]$NetworkKey,

        [Parameter()]
        [string]$NetworkName,

        [Parameter()]
        [ValidateSet('virtio', 'e1000', 'e1000e', 'rtl8139', 'pcnet', 'igb', 'vmxnet3')]
        [string]$Interface,

        [Parameter()]
        [ValidatePattern('^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$')]
        [string]$MACAddress,

        [Parameter()]
        [string]$IPAddress,

        [Parameter()]
        [ValidateLength(0, 2048)]
        [string]$Description,

        [Parameter()]
        [Nullable[bool]]$Enabled,

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
        # Resolve NIC key
        $nicKey = switch ($PSCmdlet.ParameterSetName) {
            'ByNIC' { $NIC.Key }
            'ByKey' { $Key }
        }

        $nicName = if ($NIC) { $NIC.Name } else { "Key $nicKey" }
        $vmName = if ($NIC -and $NIC.VMName) { $NIC.VMName } else { 'Unknown' }

        # Build update body with only changed properties
        $body = @{}

        if ($PSBoundParameters.ContainsKey('Name')) {
            $body['name'] = $Name
        }

        if ($resolvedNetworkKey) {
            $body['vnet'] = $resolvedNetworkKey
        }

        if ($PSBoundParameters.ContainsKey('Interface')) {
            $body['interface'] = $Interface
        }

        if ($PSBoundParameters.ContainsKey('MACAddress')) {
            $body['macaddress'] = $MACAddress.ToLower()
        }

        if ($PSBoundParameters.ContainsKey('IPAddress')) {
            $body['ipaddress'] = $IPAddress
        }

        if ($PSBoundParameters.ContainsKey('Description')) {
            $body['description'] = $Description
        }

        if ($PSBoundParameters.ContainsKey('Enabled')) {
            $body['enabled'] = $Enabled
        }

        if ($body.Count -eq 0) {
            Write-Warning "No changes specified for NIC '$nicName'"
            return
        }

        $changes = ($body.Keys | ForEach-Object { $_ }) -join ', '

        if ($PSCmdlet.ShouldProcess("$nicName (VM: $vmName)", "Modify NIC ($changes)")) {
            try {
                Write-Verbose "Modifying NIC '$nicName' (Key: $nicKey)"
                $response = Invoke-VergeAPI -Method PUT -Endpoint "machine_nics/$nicKey" -Body $body -Connection $Server

                Write-Verbose "NIC '$nicName' modified successfully"

                if ($PassThru) {
                    # Return updated NIC
                    $nicResponse = Invoke-VergeAPI -Method GET -Endpoint "machine_nics/$nicKey" -Connection $Server
                    if ($nicResponse) {
                        [PSCustomObject]@{
                            PSTypeName   = 'Verge.NIC'
                            Key          = $nicResponse.'$key' ?? $nicKey
                            Name         = $nicResponse.name
                            Interface    = $nicResponse.interface
                            MACAddress   = $nicResponse.macaddress
                            IPAddress    = $nicResponse.ipaddress
                            NetworkKey   = $nicResponse.vnet
                            Enabled      = $nicResponse.enabled
                            Description  = $nicResponse.description
                            MachineKey   = $nicResponse.machine
                            OrderId      = $nicResponse.orderid
                        }
                    }
                }
            }
            catch {
                Write-Error -Message "Failed to modify NIC '$nicName': $($_.Exception.Message)" -ErrorId 'NICModifyFailed'
            }
        }
    }
}
