function Remove-VergeSharedObject {
    <#
    .SYNOPSIS
        Removes a shared object from a VergeOS tenant.

    .DESCRIPTION
        Remove-VergeSharedObject removes a VM share from a tenant.
        This does not affect VMs that have already been imported by the tenant.
        Only the share itself is removed.

    .PARAMETER SharedObject
        A shared object from Get-VergeSharedObject. Accepts pipeline input.

    .PARAMETER TenantName
        The name of the tenant. Used with -Name.

    .PARAMETER Name
        The name of the shared object to remove. Requires -TenantName.

    .PARAMETER Key
        The unique key (ID) of the shared object to remove.

    .PARAMETER Force
        Skip confirmation prompts and remove without confirmation.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeSharedObject -TenantName "Customer01" -Name "Old-Template"

        Removes the shared object after confirmation.

    .EXAMPLE
        Get-VergeSharedObject -TenantName "Customer01" | Remove-VergeSharedObject -Force

        Removes all shared objects from the tenant without confirmation.

    .EXAMPLE
        Remove-VergeSharedObject -Key 42 -Force

        Removes a shared object by key without confirmation.

    .OUTPUTS
        None.

    .NOTES
        Removing a shared object does not delete VMs that have already been
        imported by the tenant. Only the share/offer is removed.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'BySharedObject')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'BySharedObject')]
        [PSTypeName('Verge.SharedObject')]
        [PSCustomObject]$SharedObject,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [string]$TenantName,

        [Parameter(Mandatory, Position = 1, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

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
        # Resolve shared object based on parameter set
        $targetObjects = switch ($PSCmdlet.ParameterSetName) {
            'BySharedObject' {
                $SharedObject
            }
            'ByName' {
                Get-VergeSharedObject -TenantName $TenantName -Name $Name -Server $Server
            }
            'ByKey' {
                # Query directly by key
                $queryParams = @{
                    filter = "`$key eq $Key"
                    fields = '$key,recipient,name'
                }
                $response = Invoke-VergeAPI -Method GET -Endpoint 'shared_objects' -Query $queryParams -Connection $Server
                if ($response) {
                    [PSCustomObject]@{
                        PSTypeName  = 'Verge.SharedObject'
                        Key         = [int]$response.'$key'
                        Name        = $response.name
                        _Connection = $Server
                    }
                }
                else {
                    Write-Error -Message "Shared object with key $Key not found." -ErrorId 'SharedObjectNotFound'
                    return
                }
            }
        }

        foreach ($obj in $targetObjects) {
            if (-not $obj) {
                if ($PSCmdlet.ParameterSetName -eq 'ByName') {
                    Write-Error -Message "Shared object '$Name' not found for tenant '$TenantName'." -ErrorId 'SharedObjectNotFound'
                }
                continue
            }

            # Build description for confirmation
            $objDesc = if ($obj.TenantName) {
                "$($obj.TenantName)/$($obj.Name)"
            }
            else {
                $obj.Name
            }

            # Confirm action
            if ($Force) {
                $shouldContinue = $true
            }
            else {
                $shouldContinue = $PSCmdlet.ShouldProcess($objDesc, "Remove Shared Object")
            }

            if ($shouldContinue) {
                try {
                    Write-Verbose "Removing shared object '$($obj.Name)'"
                    $response = Invoke-VergeAPI -Method DELETE -Endpoint "shared_objects/$($obj.Key)" -Connection $Server

                    Write-Verbose "Shared object '$($obj.Name)' removed"
                }
                catch {
                    Write-Error -Message "Failed to remove shared object '$($obj.Name)': $($_.Exception.Message)" -ErrorId 'SharedObjectRemoveFailed'
                }
            }
        }
    }
}
