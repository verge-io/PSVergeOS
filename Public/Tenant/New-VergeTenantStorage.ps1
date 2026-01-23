function New-VergeTenantStorage {
    <#
    .SYNOPSIS
        Adds a storage tier allocation to a VergeOS tenant.

    .DESCRIPTION
        New-VergeTenantStorage allocates storage from a specified tier to a tenant.
        Each tenant can have allocations from multiple storage tiers.
        The provisioned amount is the maximum storage the tenant can use from that tier.

    .PARAMETER Tenant
        A tenant object from Get-VergeTenant. Accepts pipeline input.

    .PARAMETER TenantName
        The name of the tenant to add storage to.

    .PARAMETER TenantKey
        The unique key (ID) of the tenant to add storage to.

    .PARAMETER Tier
        The storage tier number (0-5) to allocate from.

    .PARAMETER ProvisionedGB
        The amount of storage to provision in gigabytes.

    .PARAMETER ProvisionedBytes
        The amount of storage to provision in bytes. Use for precise control.

    .PARAMETER PassThru
        Return the created storage allocation object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeTenantStorage -TenantName "Customer01" -Tier 1 -ProvisionedGB 100

        Allocates 100 GB from Tier 1 to the tenant.

    .EXAMPLE
        Get-VergeTenant -Name "Customer01" | New-VergeTenantStorage -Tier 2 -ProvisionedGB 500 -PassThru

        Allocates 500 GB from Tier 2 and returns the allocation object.

    .EXAMPLE
        New-VergeTenantStorage -TenantName "Customer01" -Tier 0 -ProvisionedBytes 107374182400

        Allocates exactly 100 GB (in bytes) from Tier 0.

    .OUTPUTS
        None by default. Verge.TenantStorage when -PassThru is specified.

    .NOTES
        A tenant can only have one allocation per tier. Use Set-VergeTenantStorage
        to modify an existing allocation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByTenantNameGB')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByTenantGB')]
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByTenantBytes')]
        [PSTypeName('Verge.Tenant')]
        [PSCustomObject]$Tenant,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByTenantNameGB')]
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByTenantNameBytes')]
        [string]$TenantName,

        [Parameter(Mandatory, ParameterSetName = 'ByTenantKeyGB')]
        [Parameter(Mandatory, ParameterSetName = 'ByTenantKeyBytes')]
        [int]$TenantKey,

        [Parameter(Mandatory, Position = 1)]
        [ValidateRange(1, 5)]
        [ValidateScript({
            if ($_ -eq 0) {
                throw "Tier 0 is reserved for system metadata and cannot be used for tenant storage allocations."
            }
            $true
        })]
        [int]$Tier,

        [Parameter(Mandatory, ParameterSetName = 'ByTenantNameGB')]
        [Parameter(Mandatory, ParameterSetName = 'ByTenantKeyGB')]
        [Parameter(Mandatory, ParameterSetName = 'ByTenantGB')]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$ProvisionedGB,

        [Parameter(Mandatory, ParameterSetName = 'ByTenantNameBytes')]
        [Parameter(Mandatory, ParameterSetName = 'ByTenantKeyBytes')]
        [Parameter(Mandatory, ParameterSetName = 'ByTenantBytes')]
        [ValidateRange(1073741824, [long]::MaxValue)]
        [long]$ProvisionedBytes,

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
                Write-Error -Message "Cannot add storage to tenant '$($t.Name)': Tenant is a snapshot." -ErrorId 'CannotModifySnapshot'
                continue
            }

            # Get storage tier key
            $tierQueryParams = @{
                filter = "tier eq $Tier"
                fields = '$key,tier,description'
            }
            $tierResponse = Invoke-VergeAPI -Method GET -Endpoint 'storage_tiers' -Query $tierQueryParams -Connection $Server
            if (-not $tierResponse) {
                Write-Error -Message "Storage tier $Tier not found." -ErrorId 'TierNotFound'
                continue
            }
            $tierKey = $tierResponse.'$key'

            # Calculate provisioned bytes
            $provBytes = if ($PSBoundParameters.ContainsKey('ProvisionedBytes')) {
                $ProvisionedBytes
            }
            else {
                [long]$ProvisionedGB * 1GB
            }

            # Build request body
            $body = @{
                tenant      = $t.Key
                tier        = $tierKey
                provisioned = $provBytes
            }

            # Format size for display
            $sizeDisplay = if ($provBytes -ge 1TB) {
                "{0:N2} TB" -f ($provBytes / 1TB)
            }
            else {
                "{0:N0} GB" -f ($provBytes / 1GB)
            }

            # Confirm action
            if ($PSCmdlet.ShouldProcess("$($t.Name)", "Add Tier $Tier storage allocation ($sizeDisplay)")) {
                try {
                    Write-Verbose "Adding Tier $Tier storage allocation ($sizeDisplay) to tenant '$($t.Name)'"
                    $response = Invoke-VergeAPI -Method POST -Endpoint 'tenant_storage' -Body $body -Connection $Server

                    Write-Verbose "Storage allocation added to tenant '$($t.Name)'"

                    if ($PassThru) {
                        # Wait briefly then return the new allocation
                        Start-Sleep -Milliseconds 500
                        Get-VergeTenantStorage -TenantKey $t.Key -Tier "Tier $Tier" -Server $Server
                    }
                }
                catch {
                    $errorMessage = $_.Exception.Message
                    if ($errorMessage -match 'already exists' -or $errorMessage -match 'unique') {
                        Write-Error -Message "Tenant '$($t.Name)' already has a Tier $Tier storage allocation. Use Set-VergeTenantStorage to modify it." -ErrorId 'AllocationExists'
                    }
                    else {
                        Write-Error -Message "Failed to add storage allocation to tenant '$($t.Name)': $errorMessage" -ErrorId 'StorageAllocationFailed'
                    }
                }
            }
        }
    }
}
