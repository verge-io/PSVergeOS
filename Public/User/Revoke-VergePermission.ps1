function Revoke-VergePermission {
    <#
    .SYNOPSIS
        Revokes permissions from a user or group in VergeOS.

    .DESCRIPTION
        Revoke-VergePermission removes access permissions from a user or group
        for a specific resource.

    .PARAMETER Key
        The unique key (ID) of the permission record to revoke.

    .PARAMETER Permission
        A permission object from Get-VergePermission to revoke.

    .PARAMETER User
        The user name, key, or object to revoke permissions from.
        Must be combined with -Table parameter.

    .PARAMETER Group
        The group name, key, or object to revoke permissions from.
        Must be combined with -Table parameter.

    .PARAMETER Table
        The resource table to revoke access from. Required when using
        -User or -Group parameter.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Revoke-VergePermission -Key 5

        Revokes the permission with ID 5.

    .EXAMPLE
        Get-VergePermission -User "jsmith" | Revoke-VergePermission

        Revokes all permissions for user jsmith.

    .EXAMPLE
        Revoke-VergePermission -User "jsmith" -Table "vms"

        Revokes user jsmith's permissions on the vms table.

    .OUTPUTS
        None

    .NOTES
        Use Get-VergePermission to find permission records.
        Use Grant-VergePermission to add permissions.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByKey')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [PSTypeName('Verge.Permission')]
        [PSCustomObject]$Permission,

        [Parameter(Mandatory, ParameterSetName = 'ByUserAndTable')]
        [object]$User,

        [Parameter(Mandatory, ParameterSetName = 'ByGroupAndTable')]
        [object]$Group,

        [Parameter(Mandatory, ParameterSetName = 'ByUserAndTable')]
        [Parameter(Mandatory, ParameterSetName = 'ByGroupAndTable')]
        [string]$Table,

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
        # Resolve permission key based on parameter set
        $permKey = $null
        $displayName = $null

        switch ($PSCmdlet.ParameterSetName) {
            'ByKey' {
                $permKey = $Key
                $displayName = "Permission $Key"
            }
            'ByObject' {
                $permKey = $Permission.Key
                $displayName = "Permission for '$($Permission.IdentityName)' on '$($Permission.Table)'"
                if (-not $Server -and $Permission._Connection) {
                    $Server = $Permission._Connection
                }
            }
            'ByUserAndTable' {
                # Find the permission by user and table
                $permissions = Get-VergePermission -User $User -Table $Table -Server $Server
                if (-not $permissions) {
                    Write-Error -Message "No permission found for user '$User' on table '$Table'" -ErrorId 'PermissionNotFound' -Category ObjectNotFound
                    return
                }
                # Handle multiple matches by revoking all
                foreach ($perm in $permissions) {
                    $permKey = $perm.Key
                    $displayName = "Permission for '$($perm.IdentityName)' on '$($perm.Table)'"

                    if ($PSCmdlet.ShouldProcess($displayName, 'Revoke Permission')) {
                        try {
                            Write-Verbose "Revoking permission (Key: $permKey)"
                            Invoke-VergeAPI -Method DELETE -Endpoint "permissions/$permKey" -Connection $Server | Out-Null
                            Write-Verbose "Permission revoked successfully"
                        }
                        catch {
                            throw "Failed to revoke permission: $($_.Exception.Message)"
                        }
                    }
                }
                return
            }
            'ByGroupAndTable' {
                # Find the permission by group and table
                $permissions = Get-VergePermission -Group $Group -Table $Table -Server $Server
                if (-not $permissions) {
                    Write-Error -Message "No permission found for group '$Group' on table '$Table'" -ErrorId 'PermissionNotFound' -Category ObjectNotFound
                    return
                }
                # Handle multiple matches by revoking all
                foreach ($perm in $permissions) {
                    $permKey = $perm.Key
                    $displayName = "Permission for '$($perm.IdentityName)' on '$($perm.Table)'"

                    if ($PSCmdlet.ShouldProcess($displayName, 'Revoke Permission')) {
                        try {
                            Write-Verbose "Revoking permission (Key: $permKey)"
                            Invoke-VergeAPI -Method DELETE -Endpoint "permissions/$permKey" -Connection $Server | Out-Null
                            Write-Verbose "Permission revoked successfully"
                        }
                        catch {
                            throw "Failed to revoke permission: $($_.Exception.Message)"
                        }
                    }
                }
                return
            }
        }

        if (-not $permKey) {
            Write-Error -Message "Could not resolve permission" -ErrorId 'PermissionNotFound' -Category ObjectNotFound
            return
        }

        if ($PSCmdlet.ShouldProcess($displayName, 'Revoke Permission')) {
            try {
                Write-Verbose "Revoking permission (Key: $permKey)"
                Invoke-VergeAPI -Method DELETE -Endpoint "permissions/$permKey" -Connection $Server | Out-Null
                Write-Verbose "Permission revoked successfully"
            }
            catch {
                throw "Failed to revoke permission: $($_.Exception.Message)"
            }
        }
    }
}
