function Import-VergeSharedObject {
    <#
    .SYNOPSIS
        Imports a shared object (VM) into a VergeOS tenant.

    .DESCRIPTION
        Import-VergeSharedObject triggers the import of a shared VM into the tenant.
        This creates a copy of the shared VM within the tenant's environment.
        The import process runs asynchronously.

    .PARAMETER SharedObject
        A shared object from Get-VergeSharedObject. Accepts pipeline input.

    .PARAMETER TenantName
        The name of the tenant. Used with -Name.

    .PARAMETER Name
        The name of the shared object to import. Requires -TenantName.

    .PARAMETER Key
        The unique key (ID) of the shared object to import.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Import-VergeSharedObject -TenantName "Customer01" -Name "Ubuntu-Template"

        Imports the shared object into the tenant.

    .EXAMPLE
        Get-VergeSharedObject -TenantName "Customer01" -Inbox | Import-VergeSharedObject

        Imports all inbox shared objects for the tenant.

    .EXAMPLE
        Import-VergeSharedObject -Key 42

        Imports a shared object by its key.

    .OUTPUTS
        None.

    .NOTES
        The import creates a copy of the VM within the tenant. The original
        shared object remains available for future imports. Import runs
        asynchronously and may take time depending on VM size.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'BySharedObject')]
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
                    fields = '$key,recipient,name,type'
                }
                $response = Invoke-VergeAPI -Method GET -Endpoint 'shared_objects' -Query $queryParams -Connection $Server
                if ($response) {
                    $tenant = Get-VergeTenant -Key $response.recipient -Server $Server
                    [PSCustomObject]@{
                        PSTypeName  = 'Verge.SharedObject'
                        Key         = [int]$response.'$key'
                        TenantKey   = [int]$response.recipient
                        TenantName  = $tenant.Name
                        Name        = $response.name
                        Type        = $response.type
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

            # Build action body
            $body = @{
                shared_object = $obj.Key
                action        = 'import'
            }

            # Confirm action
            $objDesc = if ($obj.TenantName) {
                "$($obj.TenantName)/$($obj.Name)"
            }
            else {
                $obj.Name
            }

            if ($PSCmdlet.ShouldProcess($objDesc, "Import Shared Object")) {
                try {
                    Write-Verbose "Importing shared object '$($obj.Name)' for tenant"
                    $response = Invoke-VergeAPI -Method POST -Endpoint 'shared_object_actions' -Body $body -Connection $Server

                    Write-Verbose "Import initiated for shared object '$($obj.Name)'"
                }
                catch {
                    Write-Error -Message "Failed to import shared object '$($obj.Name)': $($_.Exception.Message)" -ErrorId 'ImportSharedObjectFailed'
                }
            }
        }
    }
}
