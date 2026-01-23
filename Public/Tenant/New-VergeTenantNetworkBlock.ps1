function New-VergeTenantNetworkBlock {
    <#
    .SYNOPSIS
        Assigns a network block (CIDR range) to a VergeOS tenant.

    .DESCRIPTION
        New-VergeTenantNetworkBlock assigns a CIDR network block to a tenant.
        This allows the tenant to have an entire subnet routed to them from
        the parent network. The block must not overlap with existing assignments.

    .PARAMETER Tenant
        A tenant object from Get-VergeTenant. Accepts pipeline input.

    .PARAMETER TenantName
        The name of the tenant to assign the block to.

    .PARAMETER TenantKey
        The unique key (ID) of the tenant to assign the block to.

    .PARAMETER Network
        The network name where the block will be assigned from.

    .PARAMETER NetworkKey
        The unique key (ID) of the network.

    .PARAMETER CIDR
        The network block in CIDR notation (e.g., "192.168.100.0/24").

    .PARAMETER Description
        Optional description for the network block assignment.

    .PARAMETER PassThru
        Return the created network block object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeTenantNetworkBlock -TenantName "Customer01" -Network "External" -CIDR "192.168.100.0/24"

        Assigns the 192.168.100.0/24 network block from "External" network to the tenant.

    .EXAMPLE
        Get-VergeTenant -Name "Customer01" | New-VergeTenantNetworkBlock -NetworkKey 1 -CIDR "10.10.0.0/16" -Description "Customer subnet"

        Assigns a /16 block with description using pipeline input.

    .EXAMPLE
        New-VergeTenantNetworkBlock -TenantName "Customer01" -Network "External" -CIDR "172.16.0.0/24" -PassThru

        Assigns a block and returns the created object.

    .OUTPUTS
        None by default. Verge.TenantNetworkBlock when -PassThru is specified.

    .NOTES
        The CIDR block must not overlap with existing network blocks on the network.
        Use standard CIDR notation: network_address/prefix_length
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
        [ValidatePattern('^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)/(3[0-2]|[1-2][0-9]|[0-9])$')]
        [string]$CIDR,

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
                Write-Error -Message "Cannot assign network block to tenant '$($t.Name)': Tenant is a snapshot." -ErrorId 'CannotModifySnapshot'
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
                cidr  = $CIDR
                owner = "tenants/$($t.Key)"
            }

            # Add optional description
            if ($Description) {
                $body['description'] = $Description
            }

            # Confirm action
            if ($PSCmdlet.ShouldProcess("$($t.Name)", "Assign Network Block '$CIDR'")) {
                try {
                    Write-Verbose "Assigning network block '$CIDR' to tenant '$($t.Name)'"
                    $response = Invoke-VergeAPI -Method POST -Endpoint 'vnet_cidrs' -Body $body -Connection $Server

                    Write-Verbose "Network block '$CIDR' assigned to tenant '$($t.Name)'"

                    if ($PassThru) {
                        # Wait briefly then return the new assignment
                        Start-Sleep -Milliseconds 500
                        Get-VergeTenantNetworkBlock -TenantKey $t.Key -CIDR $CIDR -Server $Server
                    }
                }
                catch {
                    $errorMessage = $_.Exception.Message
                    if ($errorMessage -match 'already exists') {
                        Write-Error -Message "Network block '$CIDR' already exists on the network." -ErrorId 'BlockAlreadyExists'
                    }
                    elseif ($errorMessage -match 'overlap') {
                        Write-Error -Message "Network block '$CIDR' overlaps with an existing block." -ErrorId 'BlockOverlap'
                    }
                    else {
                        Write-Error -Message "Failed to assign network block to tenant '$($t.Name)': $errorMessage" -ErrorId 'NetworkBlockAssignFailed'
                    }
                }
            }
        }
    }
}
