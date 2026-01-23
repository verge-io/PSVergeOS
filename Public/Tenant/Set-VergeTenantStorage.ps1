function Set-VergeTenantStorage {
    <#
    .SYNOPSIS
        Modifies a storage tier allocation for a VergeOS tenant.

    .DESCRIPTION
        Set-VergeTenantStorage modifies an existing storage tier allocation for a tenant.
        You can increase or decrease the provisioned amount. Use caution when decreasing
        the allocation below the current used amount.

    .PARAMETER TenantStorage
        A storage allocation object from Get-VergeTenantStorage. Accepts pipeline input.

    .PARAMETER TenantName
        The name of the tenant to modify storage for.

    .PARAMETER Tier
        The storage tier number (0-5) to modify. Required when using -TenantName.

    .PARAMETER ProvisionedGB
        The new provisioned amount in gigabytes.

    .PARAMETER ProvisionedBytes
        The new provisioned amount in bytes. Use for precise control.

    .PARAMETER PassThru
        Return the modified storage allocation object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Set-VergeTenantStorage -TenantName "Customer01" -Tier 1 -ProvisionedGB 200

        Changes the Tier 1 allocation for the tenant to 200 GB.

    .EXAMPLE
        Get-VergeTenantStorage -TenantName "Customer01" -Tier "Tier 1" | Set-VergeTenantStorage -ProvisionedGB 500

        Modifies the storage allocation using pipeline input.

    .EXAMPLE
        Set-VergeTenantStorage -TenantName "Customer01" -Tier 2 -ProvisionedGB 1000 -PassThru

        Sets the allocation to 1 TB and returns the modified object.

    .OUTPUTS
        None by default. Verge.TenantStorage when -PassThru is specified.

    .NOTES
        Decreasing storage below the current used amount may cause issues.
        Always check current usage before reducing allocations.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByTenantNameGB')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByStorageGB')]
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByStorageBytes')]
        [PSTypeName('Verge.TenantStorage')]
        [PSCustomObject]$TenantStorage,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByTenantNameGB')]
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByTenantNameBytes')]
        [string]$TenantName,

        [Parameter(Mandatory, Position = 1, ParameterSetName = 'ByTenantNameGB')]
        [Parameter(Mandatory, Position = 1, ParameterSetName = 'ByTenantNameBytes')]
        [ValidateRange(1, 5)]
        [ValidateScript({
            if ($_ -eq 0) {
                throw "Tier 0 is reserved for system metadata and cannot be used for tenant storage allocations."
            }
            $true
        })]
        [int]$Tier,

        [Parameter(Mandatory, ParameterSetName = 'ByTenantNameGB')]
        [Parameter(Mandatory, ParameterSetName = 'ByStorageGB')]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$ProvisionedGB,

        [Parameter(Mandatory, ParameterSetName = 'ByTenantNameBytes')]
        [Parameter(Mandatory, ParameterSetName = 'ByStorageBytes')]
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
        # Resolve storage allocation based on parameter set
        $targetStorage = switch -Wildcard ($PSCmdlet.ParameterSetName) {
            'ByTenantName*' {
                Get-VergeTenantStorage -TenantName $TenantName -Tier "Tier $Tier" -Server $Server
            }
            'ByStorage*' {
                $TenantStorage
            }
        }

        foreach ($storage in $targetStorage) {
            if (-not $storage) {
                if ($PSCmdlet.ParameterSetName -like 'ByTenantName*') {
                    Write-Error -Message "No Tier $Tier storage allocation found for tenant '$TenantName'. Use New-VergeTenantStorage to create one." -ErrorId 'AllocationNotFound'
                }
                continue
            }

            # Calculate provisioned bytes
            $provBytes = if ($PSBoundParameters.ContainsKey('ProvisionedBytes')) {
                $ProvisionedBytes
            }
            else {
                [long]$ProvisionedGB * 1GB
            }

            # Build request body
            $body = @{
                provisioned = $provBytes
            }

            # Format sizes for display
            $currentSize = if ($storage.Provisioned -ge 1TB) {
                "{0:N2} TB" -f ($storage.Provisioned / 1TB)
            }
            else {
                "{0:N0} GB" -f ($storage.Provisioned / 1GB)
            }

            $newSize = if ($provBytes -ge 1TB) {
                "{0:N2} TB" -f ($provBytes / 1TB)
            }
            else {
                "{0:N0} GB" -f ($provBytes / 1GB)
            }

            # Warn if decreasing below used
            if ($provBytes -lt $storage.Used) {
                Write-Warning "New allocation ($newSize) is less than current usage ($([math]::Round($storage.Used / 1GB, 2)) GB). This may cause issues."
            }

            # Confirm action
            if ($PSCmdlet.ShouldProcess("$($storage.TenantName) $($storage.TierName)", "Change storage allocation from $currentSize to $newSize")) {
                try {
                    Write-Verbose "Modifying $($storage.TierName) storage allocation for tenant '$($storage.TenantName)'"
                    $response = Invoke-VergeAPI -Method PUT -Endpoint "tenant_storage/$($storage.Key)" -Body $body -Connection $Server

                    Write-Verbose "Storage allocation modified for tenant '$($storage.TenantName)'"

                    if ($PassThru) {
                        # Wait briefly then return the updated allocation
                        Start-Sleep -Milliseconds 500
                        Get-VergeTenantStorage -TenantKey $storage.TenantKey -Tier $storage.TierName -Server $Server
                    }
                }
                catch {
                    Write-Error -Message "Failed to modify storage allocation for tenant '$($storage.TenantName)': $($_.Exception.Message)" -ErrorId 'StorageModifyFailed'
                }
            }
        }
    }
}
