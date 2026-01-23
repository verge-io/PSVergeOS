function Get-VergeNetworkDiagnostics {
    <#
    .SYNOPSIS
        Retrieves diagnostic information for a VergeOS virtual network.

    .DESCRIPTION
        Get-VergeNetworkDiagnostics returns diagnostic information including
        DHCP leases (dynamic addresses) and address table entries.

    .PARAMETER Network
        The name or key of the network to get diagnostics for.

    .PARAMETER NetworkObject
        A network object from Get-VergeNetwork. Accepts pipeline input.

    .PARAMETER Type
        Type of diagnostics to retrieve: DHCPLeases, Addresses, or All.
        Default is All.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeNetworkDiagnostics -Network "Internal"

        Gets all diagnostic information for the Internal network.

    .EXAMPLE
        Get-VergeNetworkDiagnostics -Network "Internal" -Type DHCPLeases

        Gets only DHCP lease information.

    .EXAMPLE
        Get-VergeNetwork -Name "Internal" | Get-VergeNetworkDiagnostics -Type Addresses

        Gets address table entries using pipeline input.

    .OUTPUTS
        Verge.NetworkDiagnostics

    .NOTES
        DHCP leases show active dynamic IP assignments.
        Address entries show all IP addresses associated with the network.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByNetworkName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByNetworkName')]
        [string]$Network,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByNetworkObject')]
        [PSTypeName('Verge.Network')]
        [PSCustomObject]$NetworkObject,

        [Parameter()]
        [ValidateSet('DHCPLeases', 'Addresses', 'All')]
        [string]$Type = 'All',

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

        # Type mapping
        $addressTypeMap = @{
            'dynamic' = 'DHCP Lease'
            'static'  = 'Static'
            'ipalias' = 'IP Alias'
            'proxy'   = 'Proxy ARP'
            'virtual' = 'Virtual IP'
        }
    }

    process {
        # Resolve network
        $targetNetwork = $null
        if ($PSCmdlet.ParameterSetName -eq 'ByNetworkObject') {
            $targetNetwork = $NetworkObject
        }
        else {
            if ($Network -match '^\d+$') {
                $targetNetwork = Get-VergeNetwork -Key ([int]$Network) -Server $Server
            }
            else {
                $targetNetwork = Get-VergeNetwork -Name $Network -Server $Server
            }
        }

        if (-not $targetNetwork) {
            Write-Error -Message "Network '$Network' not found" -ErrorId 'NetworkNotFound'
            return
        }

        Write-Verbose "Querying diagnostics for network '$($targetNetwork.Name)'"

        # Create output object
        $output = [PSCustomObject]@{
            PSTypeName  = 'Verge.NetworkDiagnostics'
            NetworkKey  = $targetNetwork.Key
            NetworkName = $targetNetwork.Name
            PowerState  = $targetNetwork.PowerState
            DHCPEnabled = $targetNetwork.DHCPEnabled
        }

        try {
            # Get DHCP leases (dynamic addresses)
            if ($Type -in @('DHCPLeases', 'All')) {
                $leaseQuery = @{
                    filter = "vnet eq $($targetNetwork.Key) and type eq 'dynamic'"
                    fields = '$key,ip,mac,hostname,expiration,vendor'
                    sort   = 'ip'
                }

                $leaseResponse = Invoke-VergeAPI -Method GET -Endpoint 'vnet_addresses' -Query $leaseQuery -Connection $Server

                $leases = if ($null -eq $leaseResponse) {
                    @()
                }
                elseif ($leaseResponse -is [array]) {
                    $leaseResponse
                }
                elseif ($leaseResponse.'$key') {
                    @($leaseResponse)
                }
                else {
                    @()
                }

                $leaseObjects = foreach ($lease in $leases) {
                    $expiration = if ($lease.expiration -gt 0) {
                        [DateTimeOffset]::FromUnixTimeSeconds($lease.expiration).LocalDateTime
                    }
                    else {
                        $null
                    }

                    [PSCustomObject]@{
                        IP         = $lease.ip
                        MAC        = $lease.mac
                        Hostname   = $lease.hostname
                        Vendor     = $lease.vendor
                        Expiration = $expiration
                        Key        = $lease.'$key'
                    }
                }

                $output | Add-Member -MemberType NoteProperty -Name 'DHCPLeases' -Value $leaseObjects
                $output | Add-Member -MemberType NoteProperty -Name 'DHCPLeaseCount' -Value $leaseObjects.Count
            }

            # Get all addresses (ARP-like table)
            if ($Type -in @('Addresses', 'All')) {
                $addressQuery = @{
                    filter = "vnet eq $($targetNetwork.Key)"
                    fields = '$key,ip,mac,hostname,type,expiration,vendor,description'
                    sort   = 'ip'
                }

                $addressResponse = Invoke-VergeAPI -Method GET -Endpoint 'vnet_addresses' -Query $addressQuery -Connection $Server

                $addresses = if ($null -eq $addressResponse) {
                    @()
                }
                elseif ($addressResponse -is [array]) {
                    $addressResponse
                }
                elseif ($addressResponse.'$key') {
                    @($addressResponse)
                }
                else {
                    @()
                }

                $addressObjects = foreach ($addr in $addresses) {
                    $expiration = if ($addr.expiration -gt 0) {
                        [DateTimeOffset]::FromUnixTimeSeconds($addr.expiration).LocalDateTime
                    }
                    else {
                        $null
                    }

                    [PSCustomObject]@{
                        IP          = $addr.ip
                        MAC         = $addr.mac
                        Hostname    = $addr.hostname
                        Type        = if ($addressTypeMap[$addr.type]) { $addressTypeMap[$addr.type] } else { $addr.type }
                        Vendor      = $addr.vendor
                        Description = $addr.description
                        Expiration  = $expiration
                        Key         = $addr.'$key'
                    }
                }

                $output | Add-Member -MemberType NoteProperty -Name 'Addresses' -Value $addressObjects
                $output | Add-Member -MemberType NoteProperty -Name 'AddressCount' -Value $addressObjects.Count
            }

            Write-Output $output
        }
        catch {
            Write-Error -Message "Failed to query network diagnostics: $($_.Exception.Message)" -ErrorId 'DiagnosticsQueryFailed'
        }
    }
}
