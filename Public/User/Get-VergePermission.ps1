function Get-VergePermission {
    <#
    .SYNOPSIS
        Retrieves permissions in VergeOS.

    .DESCRIPTION
        Get-VergePermission retrieves permissions assigned to users or groups.
        Permissions control access to specific resources (tables) in VergeOS.

    .PARAMETER User
        The user name, key, or object to get permissions for.

    .PARAMETER Group
        The group name, key, or object to get permissions for.

    .PARAMETER IdentityKey
        The identity key to get permissions for directly.

    .PARAMETER Table
        Filter permissions by table/resource name (e.g., 'vms', 'vnets').

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergePermission -User "jsmith"

        Retrieves all permissions for user jsmith.

    .EXAMPLE
        Get-VergePermission -Group "Developers"

        Retrieves all permissions for the Developers group.

    .EXAMPLE
        Get-VergePermission -User "jsmith" -Table "vms"

        Retrieves VM-related permissions for user jsmith.

    .EXAMPLE
        Get-VergeUser -Name "jsmith" | Get-VergePermission

        Retrieves permissions via pipeline.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.Permission'

    .NOTES
        Use Grant-VergePermission to add permissions.
        Use Revoke-VergePermission to remove permissions.
    #>
    [CmdletBinding(DefaultParameterSetName = 'All')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByUser', ValueFromPipeline)]
        [object]$User,

        [Parameter(Mandatory, ParameterSetName = 'ByGroup')]
        [object]$Group,

        [Parameter(Mandatory, ParameterSetName = 'ByIdentity')]
        [int]$IdentityKey,

        [Parameter()]
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
        # Build filter parts
        $filterParts = @()

        # Resolve identity based on parameter set
        switch ($PSCmdlet.ParameterSetName) {
            'ByUser' {
                $identityKey = $null
                if ($User -is [PSCustomObject] -and $User.PSObject.TypeNames -contains 'Verge.User') {
                    $identityKey = $User.Identity
                }
                elseif ($User -is [int]) {
                    $existingUser = Get-VergeUser -Key $User -Server $Server -ErrorAction SilentlyContinue
                    if ($existingUser) {
                        $identityKey = $existingUser.Identity
                    }
                }
                elseif ($User -is [string]) {
                    $existingUser = Get-VergeUser -Name $User -Server $Server -ErrorAction SilentlyContinue
                    if ($existingUser) {
                        $identityKey = $existingUser.Identity
                    }
                }

                if (-not $identityKey) {
                    Write-Error -Message "User not found: $User" -ErrorId 'UserNotFound' -Category ObjectNotFound
                    return
                }
                $filterParts += "identity eq $identityKey"
            }
            'ByGroup' {
                $identityKey = $null
                if ($Group -is [PSCustomObject] -and $Group.PSObject.TypeNames -contains 'Verge.Group') {
                    $identityKey = $Group.Identity
                }
                elseif ($Group -is [int]) {
                    $existingGroup = Get-VergeGroup -Key $Group -Server $Server -ErrorAction SilentlyContinue
                    if ($existingGroup) {
                        $identityKey = $existingGroup.Identity
                    }
                }
                elseif ($Group -is [string]) {
                    $existingGroup = Get-VergeGroup -Name $Group -Server $Server -ErrorAction SilentlyContinue
                    if ($existingGroup) {
                        $identityKey = $existingGroup.Identity
                    }
                }

                if (-not $identityKey) {
                    Write-Error -Message "Group not found: $Group" -ErrorId 'GroupNotFound' -Category ObjectNotFound
                    return
                }
                $filterParts += "identity eq $identityKey"
            }
            'ByIdentity' {
                $filterParts += "identity eq $IdentityKey"
            }
        }

        # Add table filter if specified
        if ($Table) {
            $filterParts += "table eq '$Table'"
        }

        # Build query parameters
        $queryParams = @{
            fields = '$key,identity,identity#owner#$display as identity_display,table,rowdisplay,row,list,read,create,modify,delete'
        }

        if ($filterParts.Count -gt 0) {
            $queryParams['filter'] = $filterParts -join ' and '
        }

        try {
            Write-Verbose "Querying permissions"
            $response = Invoke-VergeAPI -Method GET -Endpoint 'permissions' -Query $queryParams -Connection $Server

            # Handle both single object and array responses
            $permissions = if ($response -is [array]) { $response } else { @($response) }

            foreach ($permission in $permissions) {
                # Skip null entries
                if (-not $permission -or -not $permission.'$key') {
                    continue
                }

                # Create output object
                $output = [PSCustomObject]@{
                    PSTypeName       = 'Verge.Permission'
                    Key              = [int]$permission.'$key'
                    IdentityKey      = [int]$permission.identity
                    IdentityName     = $permission.identity_display
                    Table            = $permission.table
                    RowKey           = if ($permission.row) { [int]$permission.row } else { 0 }
                    RowDisplay       = $permission.rowdisplay
                    IsTableLevel     = ($permission.row -eq 0)
                    CanList          = [bool]$permission.list
                    CanRead          = [bool]$permission.read
                    CanCreate        = [bool]$permission.create
                    CanModify        = [bool]$permission.modify
                    CanDelete        = [bool]$permission.delete
                }

                # Add hidden properties for pipeline support
                $output | Add-Member -MemberType NoteProperty -Name '_Connection' -Value $Server -Force

                Write-Output $output
            }
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}
