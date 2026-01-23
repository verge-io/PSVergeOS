function New-VergeTenantExternalIP {
    <#
    .SYNOPSIS
        Assigns an external IP address to a VergeOS tenant.

    .DESCRIPTION
        New-VergeTenantExternalIP creates a Virtual IP address assignment for a tenant.
        This allows the tenant to have a routable IP address from the parent network.
        The IP must be available on the specified network.

    .PARAMETER Tenant
        A tenant object from Get-VergeTenant. Accepts pipeline input.

    .PARAMETER TenantName
        The name of the tenant to assign the IP to.

    .PARAMETER TenantKey
        The unique key (ID) of the tenant to assign the IP to.

    .PARAMETER Network
        The network name or key where the IP will be assigned from.

    .PARAMETER NetworkKey
        The unique key (ID) of the network.

    .PARAMETER IPAddress
        The IP address to assign. Must be valid and available on the network.

    .PARAMETER Hostname
        Optional hostname to associate with the IP.

    .PARAMETER Description
        Optional description for the IP assignment.

    .PARAMETER PassThru
        Return the created external IP object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeTenantExternalIP -TenantName "Customer01" -Network "External" -IPAddress "10.0.0.100"

        Assigns IP 10.0.0.100 from the "External" network to the tenant.

    .EXAMPLE
        Get-VergeTenant -Name "Customer01" | New-VergeTenantExternalIP -NetworkKey 1 -IPAddress "10.0.0.101" -Hostname "customer01-web"

        Assigns an IP with hostname using pipeline input.

    .EXAMPLE
        New-VergeTenantExternalIP -TenantName "Customer01" -Network "External" -IPAddress "10.0.0.102" -PassThru

        Assigns an IP and returns the created object.

    .OUTPUTS
        None by default. Verge.TenantExternalIP when -PassThru is specified.

    .NOTES
        The IP address must be available (not already in use) on the specified network.
        Virtual IPs allow tenants to receive traffic from the parent network.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByTenantNameNetwork')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByTenantNetwork')]
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByTenantNetworkKey')]
        [PSTypeName('Verge.Tenant')]
        [PSCustomObject]$Tenant,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByTenantNameNetwork')]
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByTenantNameNetworkKey')]
        [string]$TenantName,

        [Parameter(Mandatory, ParameterSetName = 'ByTenantKeyNetwork')]
        [Parameter(Mandatory, ParameterSetName = 'ByTenantKeyNetworkKey')]
        [int]$TenantKey,

        [Parameter(Mandatory, ParameterSetName = 'ByTenantNameNetwork')]
        [Parameter(Mandatory, ParameterSetName = 'ByTenantKeyNetwork')]
        [Parameter(Mandatory, ParameterSetName = 'ByTenantNetwork')]
        [string]$Network,

        [Parameter(Mandatory, ParameterSetName = 'ByTenantNameNetworkKey')]
        [Parameter(Mandatory, ParameterSetName = 'ByTenantKeyNetworkKey')]
        [Parameter(Mandatory, ParameterSetName = 'ByTenantNetworkKey')]
        [int]$NetworkKey,

        [Parameter(Mandatory)]
        [ValidatePattern('^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$')]
        [string]$IPAddress,

        [Parameter()]
        [string]$Hostname,

        [Parameter()]
        [ValidateLength(0, 2048)]
        [string]$Description,

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
    }

    process {
        # Resolve tenant based on parameter set
        $targetTenant = switch -Wildcard ($PSCmdlet.ParameterSetName) {
            'ByTenantName*' {
                Get-VergeTenant -Name $TenantName -Server $Server
            }
            'ByTenantKey*' {
                Get-VergeTenant -Key $TenantKey -Server $Server
            }
            'ByTenant*' {
                $Tenant
            }
        }

        foreach ($t in $targetTenant) {
            if (-not $t) {
                continue
            }

            # Check if tenant is a snapshot
            if ($t.IsSnapshot) {
                Write-Error -Message "Cannot assign external IP to tenant '$($t.Name)': Tenant is a snapshot." -ErrorId 'CannotModifySnapshot'
                continue
            }

            # Resolve network
            $netKey = if ($PSBoundParameters.ContainsKey('NetworkKey')) {
                $NetworkKey
            }
            else {
                $net = Get-VergeNetwork -Name $Network -Server $Server
                if (-not $net) {
                    Write-Error -Message "Network '$Network' not found." -ErrorId 'NetworkNotFound'
                    continue
                }
                $net.Key
            }

            # Build request body
            $body = @{
                vnet  = $netKey
                ip    = $IPAddress
                type  = 'virtual'
                owner = "tenants/$($t.Key)"
            }

            # Add optional parameters
            if ($Hostname) {
                $body['hostname'] = $Hostname.ToLower()
            }

            if ($Description) {
                $body['description'] = $Description
            }

            # Confirm action
            if ($PSCmdlet.ShouldProcess("$($t.Name)", "Assign External IP '$IPAddress'")) {
                try {
                    Write-Verbose "Assigning external IP '$IPAddress' to tenant '$($t.Name)'"
                    $response = Invoke-VergeAPI -Method POST -Endpoint 'vnet_addresses' -Body $body -Connection $Server

                    Write-Verbose "External IP '$IPAddress' assigned to tenant '$($t.Name)'"

                    if ($PassThru) {
                        # Wait briefly then return the new assignment
                        Start-Sleep -Milliseconds 500
                        Get-VergeTenantExternalIP -TenantKey $t.Key -IPAddress $IPAddress -Server $Server
                    }
                }
                catch {
                    $errorMessage = $_.Exception.Message
                    if ($errorMessage -match 'already exists') {
                        Write-Error -Message "IP address '$IPAddress' is already in use on the network." -ErrorId 'IPAlreadyExists'
                    }
                    else {
                        Write-Error -Message "Failed to assign external IP to tenant '$($t.Name)': $errorMessage" -ErrorId 'ExternalIPAssignFailed'
                    }
                }
            }
        }
    }
}
