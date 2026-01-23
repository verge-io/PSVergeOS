function Restore-VergeTenantSnapshot {
    <#
    .SYNOPSIS
        Restores a VergeOS tenant from a snapshot.

    .DESCRIPTION
        Restore-VergeTenantSnapshot reverts a tenant to the state captured in a snapshot.
        This is a destructive operation - all changes made after the snapshot will be lost.
        The tenant must be powered off before restoration.

    .PARAMETER Snapshot
        A snapshot object from Get-VergeTenantSnapshot. Accepts pipeline input.

    .PARAMETER SnapshotKey
        The unique key (ID) of the snapshot to restore from.

    .PARAMETER TenantName
        The name of the tenant. Used with -SnapshotName.

    .PARAMETER SnapshotName
        The name of the snapshot to restore from. Requires -TenantName.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Restore-VergeTenantSnapshot -TenantName "Customer01" -SnapshotName "Pre-Upgrade"

        Restores the tenant to the "Pre-Upgrade" snapshot.

    .EXAMPLE
        Get-VergeTenantSnapshot -TenantName "Customer01" -Name "Pre-Upgrade" | Restore-VergeTenantSnapshot

        Restores the tenant using pipeline input.

    .EXAMPLE
        Restore-VergeTenantSnapshot -SnapshotKey 42

        Restores the tenant from snapshot with key 42.

    .OUTPUTS
        None.

    .NOTES
        WARNING: This operation is destructive. All changes made after the snapshot
        was created will be lost. The tenant must be powered off first.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'BySnapshot')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'BySnapshot')]
        [PSTypeName('Verge.TenantSnapshot')]
        [PSCustomObject]$Snapshot,

        [Parameter(Mandatory, ParameterSetName = 'BySnapshotKey')]
        [int]$SnapshotKey,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [string]$TenantName,

        [Parameter(Mandatory, Position = 1, ParameterSetName = 'ByName')]
        [string]$SnapshotName,

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
        # Resolve snapshot based on parameter set
        $targetSnapshot = switch ($PSCmdlet.ParameterSetName) {
            'BySnapshot' {
                $Snapshot
            }
            'BySnapshotKey' {
                # Get the snapshot by querying the API directly
                $queryParams = @{
                    filter = "`$key eq $SnapshotKey"
                    fields = '$key,tenant,name,description,created,expires'
                }
                $response = Invoke-VergeAPI -Method GET -Endpoint 'tenant_snapshots' -Query $queryParams -Connection $Server
                if ($response) {
                    # Get the tenant info
                    $tenant = Get-VergeTenant -Key $response.tenant -Server $Server
                    [PSCustomObject]@{
                        PSTypeName  = 'Verge.TenantSnapshot'
                        Key         = [int]$response.'$key'
                        TenantKey   = [int]$response.tenant
                        TenantName  = $tenant.Name
                        Name        = $response.name
                        Description = $response.description
                        _Connection = $Server
                    }
                }
                else {
                    Write-Error -Message "Snapshot with key $SnapshotKey not found." -ErrorId 'SnapshotNotFound'
                    return
                }
            }
            'ByName' {
                Get-VergeTenantSnapshot -TenantName $TenantName -Name $SnapshotName -Server $Server
            }
        }

        foreach ($snap in $targetSnapshot) {
            if (-not $snap) {
                continue
            }

            # Get the current tenant state
            $tenant = Get-VergeTenant -Key $snap.TenantKey -Server $Server
            if (-not $tenant) {
                Write-Error -Message "Tenant for snapshot '$($snap.Name)' not found." -ErrorId 'TenantNotFound'
                continue
            }

            # Check if tenant is running
            if ($tenant.IsRunning -or $tenant.Status -notin @('Offline', 'Error')) {
                Write-Error -Message "Cannot restore tenant '$($tenant.Name)': Tenant must be powered off first. Use Stop-VergeTenant." -ErrorId 'TenantNotStopped'
                continue
            }

            # Build action body
            $body = @{
                tenant = $snap.TenantKey
                action = 'restore'
                params = @{
                    snapshot = $snap.Key
                }
            }

            # Confirm action
            $warningMessage = "This will restore tenant '$($tenant.Name)' to snapshot '$($snap.Name)'. ALL changes made after the snapshot will be LOST."

            if ($PSCmdlet.ShouldProcess("$($tenant.Name)", "Restore from snapshot '$($snap.Name)' (WARNING: $warningMessage)")) {
                try {
                    Write-Verbose "Restoring tenant '$($tenant.Name)' from snapshot '$($snap.Name)'"
                    $response = Invoke-VergeAPI -Method POST -Endpoint 'tenant_actions' -Body $body -Connection $Server

                    Write-Verbose "Tenant '$($tenant.Name)' restored from snapshot '$($snap.Name)'"
                }
                catch {
                    $errorMessage = $_.Exception.Message
                    if ($errorMessage -match 'running') {
                        Write-Error -Message "Cannot restore tenant '$($tenant.Name)': Tenant must be powered off first." -ErrorId 'TenantRunning'
                    }
                    else {
                        Write-Error -Message "Failed to restore tenant '$($tenant.Name)': $errorMessage" -ErrorId 'TenantRestoreFailed'
                    }
                }
            }
        }
    }
}
