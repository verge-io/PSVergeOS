function Remove-VergeTenantSnapshot {
    <#
    .SYNOPSIS
        Removes a snapshot from a VergeOS tenant.

    .DESCRIPTION
        Remove-VergeTenantSnapshot deletes a tenant snapshot.
        This is a destructive operation and cannot be undone.

    .PARAMETER Snapshot
        A snapshot object from Get-VergeTenantSnapshot. Accepts pipeline input.

    .PARAMETER SnapshotKey
        The unique key (ID) of the snapshot to remove.

    .PARAMETER TenantName
        The name of the tenant. Used with -SnapshotName.

    .PARAMETER SnapshotName
        The name of the snapshot to remove. Requires -TenantName.

    .PARAMETER Force
        Skip confirmation prompts and remove without confirmation.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeTenantSnapshot -TenantName "Customer01" -SnapshotName "Old-Backup"

        Removes the snapshot after confirmation.

    .EXAMPLE
        Get-VergeTenantSnapshot -TenantName "Customer01" -Name "Test*" | Remove-VergeTenantSnapshot -Force

        Removes all snapshots matching "Test*" without confirmation.

    .EXAMPLE
        Remove-VergeTenantSnapshot -SnapshotKey 42 -Force

        Removes snapshot with key 42 without confirmation.

    .OUTPUTS
        None.

    .NOTES
        Removing a snapshot is permanent. Ensure you no longer need the snapshot
        before deletion.
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
        # Resolve snapshot based on parameter set
        $targetSnapshots = switch ($PSCmdlet.ParameterSetName) {
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

        foreach ($snap in $targetSnapshots) {
            if (-not $snap) {
                continue
            }

            # Confirm action
            if ($Force) {
                $shouldContinue = $true
            }
            else {
                $shouldContinue = $PSCmdlet.ShouldProcess("$($snap.TenantName)/$($snap.Name)", "Remove Tenant Snapshot")
            }

            if ($shouldContinue) {
                try {
                    Write-Verbose "Removing snapshot '$($snap.Name)' from tenant '$($snap.TenantName)'"
                    $response = Invoke-VergeAPI -Method DELETE -Endpoint "tenant_snapshots/$($snap.Key)" -Connection $Server

                    Write-Verbose "Snapshot '$($snap.Name)' removed from tenant '$($snap.TenantName)'"
                }
                catch {
                    Write-Error -Message "Failed to remove snapshot '$($snap.Name)': $($_.Exception.Message)" -ErrorId 'SnapshotRemoveFailed'
                }
            }
        }
    }
}
