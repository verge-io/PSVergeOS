function Remove-VergeTenantStorage {
    <#
    .SYNOPSIS
        Removes a storage tier allocation from a VergeOS tenant.

    .DESCRIPTION
        Remove-VergeTenantStorage removes an existing storage tier allocation from a tenant.
        This is a destructive operation - the tenant will lose access to that storage tier.
        The allocation should be empty (0 bytes used) before removal.

    .PARAMETER TenantStorage
        A storage allocation object from Get-VergeTenantStorage. Accepts pipeline input.

    .PARAMETER TenantName
        The name of the tenant to remove storage from.

    .PARAMETER Tier
        The storage tier number (0-5) to remove. Required when using -TenantName.

    .PARAMETER Force
        Skip confirmation prompts and remove without confirmation.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeTenantStorage -TenantName "Customer01" -Tier 2

        Removes the Tier 2 storage allocation from the tenant after confirmation.

    .EXAMPLE
        Get-VergeTenantStorage -TenantName "Customer01" -Tier "Tier 2" | Remove-VergeTenantStorage

        Removes the storage allocation using pipeline input.

    .EXAMPLE
        Remove-VergeTenantStorage -TenantName "Customer01" -Tier 1 -Force

        Removes the allocation without confirmation.

    .OUTPUTS
        None.

    .NOTES
        WARNING: Removing a storage allocation with data may cause data loss.
        Ensure the allocation is empty or data is migrated before removal.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByTenantName')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByStorage')]
        [PSTypeName('Verge.TenantStorage')]
        [PSCustomObject]$TenantStorage,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByTenantName')]
        [string]$TenantName,

        [Parameter(Mandatory, Position = 1, ParameterSetName = 'ByTenantName')]
        [ValidateRange(1, 5)]
        [ValidateScript({
            if ($_ -eq 0) {
                throw "Tier 0 is reserved for system metadata and cannot be used for tenant storage allocations."
            }
            $true
        })]
        [int]$Tier,

        [Parameter()]
        [switch]$Force,

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
        $targetStorage = switch ($PSCmdlet.ParameterSetName) {
            'ByTenantName' {
                Get-VergeTenantStorage -TenantName $TenantName -Tier "Tier $Tier" -Server $Server
            }
            'ByStorage' {
                $TenantStorage
            }
        }

        foreach ($storage in $targetStorage) {
            if (-not $storage) {
                if ($PSCmdlet.ParameterSetName -eq 'ByTenantName') {
                    Write-Error -Message "No Tier $Tier storage allocation found for tenant '$TenantName'." -ErrorId 'AllocationNotFound'
                }
                continue
            }

            # Warn if storage has data
            if ($storage.Used -gt 0) {
                $usedDisplay = if ($storage.Used -ge 1TB) {
                    "{0:N2} TB" -f ($storage.Used / 1TB)
                }
                else {
                    "{0:N2} GB" -f ($storage.Used / 1GB)
                }
                Write-Warning "Storage allocation has $usedDisplay of data. Removing this allocation may cause data loss."
            }

            # Build description for confirmation
            $allocDisplay = if ($storage.Provisioned -ge 1TB) {
                "{0:N2} TB" -f ($storage.Provisioned / 1TB)
            }
            else {
                "{0:N0} GB" -f ($storage.Provisioned / 1GB)
            }

            $warningMessage = "This will remove the $($storage.TierName) storage allocation ($allocDisplay) from tenant '$($storage.TenantName)'."

            # Confirm action
            if ($Force) {
                $shouldContinue = $true
            }
            else {
                $shouldContinue = $PSCmdlet.ShouldProcess("$($storage.TenantName) $($storage.TierName)", "Remove storage allocation (WARNING: $warningMessage)")
            }

            if ($shouldContinue) {
                try {
                    Write-Verbose "Removing $($storage.TierName) storage allocation from tenant '$($storage.TenantName)'"
                    $response = Invoke-VergeAPI -Method DELETE -Endpoint "tenant_storage/$($storage.Key)" -Connection $Server

                    Write-Verbose "Storage allocation removed from tenant '$($storage.TenantName)'"
                }
                catch {
                    $errorMessage = $_.Exception.Message
                    if ($errorMessage -match 'in use' -or $errorMessage -match 'not empty') {
                        Write-Error -Message "Cannot remove storage allocation: Storage tier is still in use by tenant '$($storage.TenantName)'." -ErrorId 'StorageInUse'
                    }
                    else {
                        Write-Error -Message "Failed to remove storage allocation from tenant '$($storage.TenantName)': $errorMessage" -ErrorId 'StorageRemoveFailed'
                    }
                }
            }
        }
    }
}
