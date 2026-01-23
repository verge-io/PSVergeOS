function New-VergeTenantLayer2Network {
    <#
    .SYNOPSIS
        Assigns a Layer 2 network to a VergeOS tenant.

    .DESCRIPTION
        New-VergeTenantLayer2Network assigns a Layer 2 network to a tenant,
        providing bridged connectivity between the parent and tenant networks.
        Only certain network types can be assigned: internal, external, bgp,
        vpn, or bridged physical networks.

    .PARAMETER Tenant
        A tenant object from Get-VergeTenant. Accepts pipeline input.

    .PARAMETER TenantName
        The name of the tenant to assign the network to.

    .PARAMETER TenantKey
        The unique key (ID) of the tenant to assign the network to.

    .PARAMETER Network
        A network object from Get-VergeNetwork. Accepts pipeline input.

    .PARAMETER NetworkName
        The name of the network to assign.

    .PARAMETER NetworkKey
        The unique key (ID) of the network to assign.

    .PARAMETER Enabled
        Whether the Layer 2 network assignment should be enabled. Default is true.

    .PARAMETER PassThru
        Return the created Layer 2 network assignment object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeTenantLayer2Network -TenantName "Customer01" -NetworkName "VLAN100"

        Assigns the VLAN100 network to the tenant.

    .EXAMPLE
        Get-VergeTenant -Name "Customer01" | New-VergeTenantLayer2Network -NetworkName "DMZ" -PassThru

        Assigns the DMZ network and returns the assignment object.

    .EXAMPLE
        New-VergeTenantLayer2Network -TenantName "Customer01" -NetworkKey 42 -Enabled:$false

        Assigns the network but leaves it disabled initially.

    .OUTPUTS
        None by default. Verge.TenantLayer2Network when -PassThru is specified.

    .NOTES
        Only internal, external, bgp, vpn, or bridged physical networks can be
        assigned as Layer 2 networks. A maximum of 28 Layer 2 networks can be
        assigned per tenant.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByTenantNameAndNetworkName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByTenantAndNetworkName')]
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByTenantAndNetworkKey')]
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByTenantAndNetwork')]
        [PSTypeName('Verge.Tenant')]
        [PSCustomObject]$Tenant,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByTenantNameAndNetworkName')]
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByTenantNameAndNetworkKey')]
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByTenantNameAndNetwork')]
        [string]$TenantName,

        [Parameter(Mandatory, ParameterSetName = 'ByTenantKeyAndNetworkName')]
        [Parameter(Mandatory, ParameterSetName = 'ByTenantKeyAndNetworkKey')]
        [Parameter(Mandatory, ParameterSetName = 'ByTenantKeyAndNetwork')]
        [int]$TenantKey,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByTenantNameAndNetwork')]
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByTenantKeyAndNetwork')]
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByTenantAndNetwork')]
        [PSTypeName('Verge.Network')]
        [PSCustomObject]$Network,

        [Parameter(Mandatory, Position = 1, ParameterSetName = 'ByTenantNameAndNetworkName')]
        [Parameter(Mandatory, Position = 1, ParameterSetName = 'ByTenantKeyAndNetworkName')]
        [Parameter(Mandatory, Position = 1, ParameterSetName = 'ByTenantAndNetworkName')]
        [string]$NetworkName,

        [Parameter(Mandatory, ParameterSetName = 'ByTenantNameAndNetworkKey')]
        [Parameter(Mandatory, ParameterSetName = 'ByTenantKeyAndNetworkKey')]
        [Parameter(Mandatory, ParameterSetName = 'ByTenantAndNetworkKey')]
        [int]$NetworkKey,

        [Parameter()]
        [bool]$Enabled = $true,

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

        # Resolve network based on parameter set
        $targetNetwork = switch -Wildcard ($PSCmdlet.ParameterSetName) {
            '*NetworkName' {
                Get-VergeNetwork -Name $NetworkName -Server $Server
            }
            '*NetworkKey' {
                Get-VergeNetwork -Key $NetworkKey -Server $Server
            }
            '*Network' {
                $Network
            }
        }

        foreach ($t in $targetTenant) {
            if (-not $t) {
                continue
            }

            # Check if tenant is a snapshot
            if ($t.IsSnapshot) {
                Write-Error -Message "Cannot assign Layer 2 network to tenant '$($t.Name)': Tenant is a snapshot." -ErrorId 'CannotModifySnapshot'
                continue
            }

            foreach ($n in $targetNetwork) {
                if (-not $n) {
                    if ($PSCmdlet.ParameterSetName -like '*NetworkName') {
                        Write-Error -Message "Network '$NetworkName' not found." -ErrorId 'NetworkNotFound'
                    }
                    continue
                }

                # Confirm action
                if ($PSCmdlet.ShouldProcess("$($t.Name)", "Assign Layer 2 network '$($n.Name)'")) {
                    try {
                        Write-Verbose "Assigning Layer 2 network '$($n.Name)' to tenant '$($t.Name)'"

                        $body = @{
                            tenant  = $t.Key
                            vnet    = $n.Key
                            enabled = $Enabled
                        }

                        $response = Invoke-VergeAPI -Method POST -Endpoint 'tenant_layer2_vnets' -Body $body -Connection $Server

                        Write-Verbose "Layer 2 network '$($n.Name)' assigned to tenant '$($t.Name)'"

                        if ($PassThru -and $response.'$key') {
                            Get-VergeTenantLayer2Network -Key $response.'$key' -Server $Server
                        }
                    }
                    catch {
                        $errorMessage = $_.Exception.Message
                        if ($errorMessage -match 'unique') {
                            Write-Error -Message "Layer 2 network '$($n.Name)' is already assigned to tenant '$($t.Name)'." -ErrorId 'Layer2NetworkAlreadyAssigned'
                        }
                        elseif ($errorMessage -match 'maxrows|limit') {
                            Write-Error -Message "Cannot assign more Layer 2 networks to tenant '$($t.Name)': Maximum limit reached (28)." -ErrorId 'Layer2NetworkLimitReached'
                        }
                        else {
                            Write-Error -Message "Failed to assign Layer 2 network '$($n.Name)' to tenant '$($t.Name)': $errorMessage" -ErrorId 'Layer2NetworkAssignFailed'
                        }
                    }
                }
            }
        }
    }
}
