function Restore-VergeTenantFromCloudSnapshot {
    <#
    .SYNOPSIS
        Restores a tenant from a cloud (system) snapshot in VergeOS.

    .DESCRIPTION
        Restore-VergeTenantFromCloudSnapshot recovers a tenant from a cloud snapshot.
        This creates a new tenant from the snapshot data, it does not overwrite
        any existing tenant.

        Use Get-VergeCloudSnapshot -IncludeTenants to see available tenants in a snapshot.

    .PARAMETER CloudSnapshot
        A cloud snapshot object from Get-VergeCloudSnapshot. Accepts pipeline input.

    .PARAMETER CloudSnapshotKey
        The key (ID) of the cloud snapshot containing the tenant.

    .PARAMETER CloudSnapshotName
        The name of the cloud snapshot containing the tenant.

    .PARAMETER TenantName
        The name of the tenant within the cloud snapshot to restore.

    .PARAMETER TenantKey
        The key of the tenant within the cloud snapshot (from cloud_snapshot_tenants).

    .PARAMETER NewName
        Optional new name for the restored tenant. If not specified, the original name
        is used (which may conflict with an existing tenant).

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Restore-VergeTenantFromCloudSnapshot -CloudSnapshotName "Daily_20260123" -TenantName "CustomerA"

        Restores the tenant "CustomerA" from the specified cloud snapshot.

    .EXAMPLE
        Get-VergeCloudSnapshot -Name "Midnight*" | Restore-VergeTenantFromCloudSnapshot -TenantName "Production" -NewName "Production-DR"

        Restores the tenant with a new name from the first matching cloud snapshot.

    .OUTPUTS
        PSCustomObject with recovery status information.

    .NOTES
        The recovered tenant will be created as a new tenant. If a tenant with the same name
        already exists, you should specify -NewName to avoid conflicts.

        This operation may take significant time depending on tenant size and complexity.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'BySnapshotName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [PSTypeName('Verge.CloudSnapshot')]
        [PSCustomObject]$CloudSnapshot,

        [Parameter(Mandatory, ParameterSetName = 'BySnapshotKey')]
        [int]$CloudSnapshotKey,

        [Parameter(Mandatory, ParameterSetName = 'BySnapshotName')]
        [string]$CloudSnapshotName,

        [Parameter(ParameterSetName = 'ByObject')]
        [Parameter(ParameterSetName = 'BySnapshotKey')]
        [Parameter(ParameterSetName = 'BySnapshotName')]
        [string]$TenantName,

        [Parameter()]
        [int]$TenantKey,

        [Parameter()]
        [string]$NewName,

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
        # Resolve the cloud snapshot
        $targetSnapshot = switch ($PSCmdlet.ParameterSetName) {
            'ByObject' { $CloudSnapshot }
            'BySnapshotKey' { Get-VergeCloudSnapshot -Key $CloudSnapshotKey -IncludeExpired -Server $Server }
            'BySnapshotName' { Get-VergeCloudSnapshot -Name $CloudSnapshotName -IncludeExpired -Server $Server | Select-Object -First 1 }
        }

        if (-not $targetSnapshot) {
            $identifier = if ($CloudSnapshotKey) { "Key: $CloudSnapshotKey" } else { "Name: $CloudSnapshotName" }
            Write-Error -Message "Cloud snapshot not found ($identifier)" -ErrorId 'CloudSnapshotNotFound'
            return
        }

        $snapshotKey = $targetSnapshot.Key
        $snapshotName = $targetSnapshot.Name

        # Find the tenant within the snapshot
        if (-not $TenantKey -and -not $TenantName) {
            Write-Error -Message "Either -TenantName or -TenantKey must be specified" -ErrorId 'TenantNotSpecified'
            return
        }

        # Query cloud_snapshot_tenants to find the tenant
        $tenantParams = @{
            'fields' = @(
                '$key'
                'name'
                'description'
                'original_key'
                'status'
            ) -join ','
            'filter' = "cloud_snapshot eq $snapshotKey"
        }

        if ($TenantKey) {
            $tenantParams['filter'] += " and `$key eq $TenantKey"
        }
        elseif ($TenantName) {
            $tenantParams['filter'] += " and name eq '$TenantName'"
        }

        try {
            $tenantResponse = Invoke-VergeAPI -Method GET -Endpoint 'cloud_snapshot_tenants' -Query $tenantParams -Connection $Server
            $snapshotTenants = if ($tenantResponse -is [array]) { $tenantResponse } elseif ($tenantResponse) { @($tenantResponse) } else { @() }

            if ($snapshotTenants.Count -eq 0) {
                $tenantIdentifier = if ($TenantKey) { "Key: $TenantKey" } else { "Name: $TenantName" }
                Write-Error -Message "Tenant not found in cloud snapshot '$snapshotName' ($tenantIdentifier)" -ErrorId 'TenantNotFoundInSnapshot'
                return
            }

            foreach ($tenant in $snapshotTenants) {
                $tenantDisplayName = $tenant.name
                $tenantSnapshotKey = $tenant.'$key'

                $restoreName = if ($NewName) { $NewName } else { $tenantDisplayName }

                if ($PSCmdlet.ShouldProcess("Tenant '$tenantDisplayName' from Cloud Snapshot '$snapshotName'", 'Restore')) {
                    Write-Verbose "Restoring tenant '$tenantDisplayName' from cloud snapshot '$snapshotName' (Tenant Snapshot Key: $tenantSnapshotKey)"

                    # Build the recover action
                    $body = @{
                        action = 'recover'
                        params = @{
                            rows = @($tenantSnapshotKey)
                        }
                    }

                    if ($NewName) {
                        $body['params']['name'] = $NewName
                    }

                    try {
                        $response = Invoke-VergeAPI -Method POST -Endpoint 'cloud_snapshot_tenant_actions' -Body $body -Connection $Server

                        # Create output object
                        $output = [PSCustomObject]@{
                            PSTypeName           = 'Verge.CloudSnapshotTenantRestore'
                            CloudSnapshotKey     = $snapshotKey
                            CloudSnapshotName    = $snapshotName
                            TenantSnapshotKey    = $tenantSnapshotKey
                            TenantName           = $tenantDisplayName
                            RestoredAs           = $restoreName
                            Status               = 'Initiated'
                            Response             = $response
                        }

                        if ($response -and $response.task) {
                            $output | Add-Member -MemberType NoteProperty -Name 'TaskKey' -Value $response.task -Force
                        }

                        Write-Output $output
                        Write-Verbose "Tenant restore initiated for '$tenantDisplayName'"
                    }
                    catch {
                        Write-Error -Message "Failed to restore tenant '$tenantDisplayName' from cloud snapshot: $($_.Exception.Message)" -ErrorId 'RestoreTenantFailed'
                    }
                }
            }
        }
        catch {
            Write-Error -Message "Failed to query tenants in cloud snapshot '$snapshotName': $($_.Exception.Message)" -ErrorId 'QuerySnapshotTenantsFailed'
        }
    }
}
