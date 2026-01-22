function Get-VergeNIC {
    <#
    .SYNOPSIS
        Retrieves network interfaces attached to a VergeOS virtual machine.

    .DESCRIPTION
        Get-VergeNIC retrieves network interface information for one or more VMs,
        including MAC address, IP address, connected network, and interface type.

    .PARAMETER VM
        A VM object from Get-VergeVM. Accepts pipeline input.

    .PARAMETER VMName
        The name of the VM to get NICs for.

    .PARAMETER VMKey
        The key (ID) of the VM to get NICs for.

    .PARAMETER Name
        Filter NICs by name. Supports wildcards (* and ?).

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeNIC -VMName "WebServer01"

        Gets all network interfaces attached to the VM named "WebServer01".

    .EXAMPLE
        Get-VergeVM -Name "WebServer01" | Get-VergeNIC

        Gets NICs for the VM using pipeline input.

    .EXAMPLE
        Get-VergeVM -Name "Prod-*" | Get-VergeNIC | Select-Object VMName, Name, Network, IPAddress, MACAddress

        Gets NIC details for all production VMs.

    .EXAMPLE
        Get-VergeVM | Get-VergeNIC | Where-Object { $_.Network -eq 'Internal' }

        Gets all NICs connected to the 'Internal' network.

    .EXAMPLE
        Get-VergeVM | Get-VergeNIC | Format-Table VMName, Name, Interface, Network, IPAddress, MACAddress -AutoSize

        Lists all NICs across all VMs in a table format.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.NIC'

    .NOTES
        Use New-VergeNIC and Remove-VergeNIC to manage VM network interfaces.
        Use Set-VergeNIC to modify NIC settings or change network assignment.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByVMObject')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByVMObject')]
        [PSTypeName('Verge.VM')]
        [PSCustomObject]$VM,

        [Parameter(Mandatory, ParameterSetName = 'ByVMName')]
        [string]$VMName,

        [Parameter(Mandatory, ParameterSetName = 'ByVMKey')]
        [int]$VMKey,

        [Parameter()]
        [SupportsWildcards()]
        [string]$Name,

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

        # Map API interface values to friendly names
        $interfaceDisplayMap = @{
            'virtio'   = 'Virtio'
            'e1000'    = 'Intel e1000'
            'e1000e'   = 'Intel e1000e'
            'rtl8139'  = 'Realtek 8139'
            'pcnet'    = 'AMD PCnet'
            'igb'      = 'Intel 82576'
            'vmxnet3'  = 'VMware Paravirt v3'
            'direct'   = 'Direct'
        }
    }

    process {
        # Resolve VM based on parameter set
        $targetVMs = switch ($PSCmdlet.ParameterSetName) {
            'ByVMName' {
                Get-VergeVM -Name $VMName -Server $Server
            }
            'ByVMKey' {
                Get-VergeVM -Key $VMKey -Server $Server
            }
            'ByVMObject' {
                $VM
            }
        }

        foreach ($targetVM in $targetVMs) {
            if (-not $targetVM -or -not $targetVM.MachineKey) {
                continue
            }

            # Build query for NICs
            $queryParams = @{}

            # Filter by machine (VM's internal machine key)
            $queryParams['filter'] = "machine eq $($targetVM.MachineKey)"

            # Request NIC fields including related data
            $queryParams['fields'] = @(
                '$key'
                'name'
                'orderid'
                'interface'
                'description'
                'enabled'
                'macaddress'
                'ipaddress'
                'vnet'
                'machine'
                'status#status as status'
                'status#display(status) as status_display'
                'status#speed as speed'
                'vnet#$key as vnet_key'
                'vnet#name as vnet_name'
                'vnet#machine#status#status as vnet_status'
                'stats#rx_bytes as rx_bytes'
                'stats#tx_bytes as tx_bytes'
                'stats#rxbps as rxbps'
                'stats#txbps as txbps'
            ) -join ','

            $queryParams['sort'] = '+orderid'

            try {
                Write-Verbose "Querying NICs for VM '$($targetVM.Name)' (Machine: $($targetVM.MachineKey))"
                $response = Invoke-VergeAPI -Method GET -Endpoint 'machine_nics' -Query $queryParams -Connection $Server

                # Handle both single object and array responses
                $nics = if ($response -is [array]) { $response } elseif ($response) { @($response) } else { @() }

                foreach ($nic in $nics) {
                    if (-not $nic -or -not $nic.name) {
                        continue
                    }

                    # Apply name filter if specified (with wildcard support)
                    if ($Name) {
                        if ($Name -match '[\*\?]') {
                            if ($nic.name -notlike $Name) {
                                continue
                            }
                        }
                        elseif ($nic.name -ne $Name) {
                            continue
                        }
                    }

                    # Get interface display name
                    $interfaceDisplay = if ($interfaceDisplayMap.ContainsKey($nic.interface)) {
                        $interfaceDisplayMap[$nic.interface]
                    } else {
                        $nic.interface
                    }

                    # Format speed for display
                    $speedDisplay = if ($nic.speed) {
                        if ($nic.speed -ge 1000) {
                            "$([math]::Round($nic.speed / 1000, 1)) Gbps"
                        } else {
                            "$($nic.speed) Mbps"
                        }
                    } else {
                        $null
                    }

                    # Create output object
                    $output = [PSCustomObject]@{
                        PSTypeName       = 'Verge.NIC'
                        Key              = [int]$nic.'$key'
                        Name             = $nic.name
                        OrderId          = [int]$nic.orderid
                        Interface        = $nic.interface
                        InterfaceDisplay = $interfaceDisplay
                        Description      = $nic.description
                        Enabled          = [bool]$nic.enabled
                        MACAddress       = $nic.macaddress
                        IPAddress        = $nic.ipaddress
                        NetworkKey       = $nic.vnet_key
                        Network          = $nic.vnet_name
                        NetworkStatus    = $nic.vnet_status
                        Speed            = $nic.speed
                        SpeedDisplay     = $speedDisplay
                        Status           = $nic.status
                        StatusDisplay    = $nic.status_display
                        RxBytes          = [long]$nic.rx_bytes
                        TxBytes          = [long]$nic.tx_bytes
                        RxBps            = [long]$nic.rxbps
                        TxBps            = [long]$nic.txbps
                        VMKey            = $targetVM.Key
                        VMName           = $targetVM.Name
                        MachineKey       = $targetVM.MachineKey
                    }

                    # Add hidden properties for pipeline support
                    $output | Add-Member -MemberType NoteProperty -Name '_Connection' -Value $Server -Force
                    $output | Add-Member -MemberType NoteProperty -Name '_VM' -Value $targetVM -Force

                    Write-Output $output
                }
            }
            catch {
                Write-Error -Message "Failed to get NICs for VM '$($targetVM.Name)': $($_.Exception.Message)" -ErrorId 'GetNICsFailed'
            }
        }
    }
}
