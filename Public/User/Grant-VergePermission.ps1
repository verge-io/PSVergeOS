function Grant-VergePermission {
    <#
    .SYNOPSIS
        Grants permissions to a user or group in VergeOS.

    .DESCRIPTION
        Grant-VergePermission assigns access permissions to a user or group
        for a specific resource table (e.g., vms, vnets, volumes).

    .PARAMETER User
        The user name, key, or object to grant permissions to.

    .PARAMETER Group
        The group name, key, or object to grant permissions to.

    .PARAMETER Table
        The resource table to grant access to (e.g., 'vms', 'vnets', 'volumes').

    .PARAMETER RowKey
        The specific row key to grant access to. If not specified, grants
        access to all rows in the table.

    .PARAMETER List
        Grant permission to list/see items. Default is $true.

    .PARAMETER Read
        Grant permission to read item details.

    .PARAMETER Create
        Grant permission to create new items.

    .PARAMETER Modify
        Grant permission to modify existing items.

    .PARAMETER Delete
        Grant permission to delete items.

    .PARAMETER FullControl
        Grant all permissions (List, Read, Create, Modify, Delete).

    .PARAMETER PassThru
        Return the created permission object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Grant-VergePermission -User "jsmith" -Table "vms" -Read -List

        Grants user jsmith read-only access to VMs.

    .EXAMPLE
        Grant-VergePermission -Group "Developers" -Table "vms" -FullControl

        Grants the Developers group full control over VMs.

    .EXAMPLE
        Grant-VergePermission -User "jsmith" -Table "/" -List -Read

        Grants user jsmith read access to the root (all resources).

    .OUTPUTS
        None by default. Verge.Permission when -PassThru is specified.

    .NOTES
        Use Get-VergePermission to view permissions.
        Use Revoke-VergePermission to remove permissions.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByUser')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByUser')]
        [object]$User,

        [Parameter(Mandatory, ParameterSetName = 'ByGroup')]
        [object]$Group,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Table,

        [Parameter()]
        [int]$RowKey = 0,

        [Parameter()]
        [bool]$List = $true,

        [Parameter()]
        [switch]$Read,

        [Parameter()]
        [switch]$Create,

        [Parameter()]
        [switch]$Modify,

        [Parameter()]
        [switch]$Delete,

        [Parameter()]
        [switch]$FullControl,

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
        # Resolve identity
        $identityKey = $null
        $identityName = $null

        switch ($PSCmdlet.ParameterSetName) {
            'ByUser' {
                if ($User -is [PSCustomObject] -and $User.PSObject.TypeNames -contains 'Verge.User') {
                    $identityKey = $User.Identity
                    $identityName = $User.Name
                }
                elseif ($User -is [int]) {
                    $existingUser = Get-VergeUser -Key $User -Server $Server -ErrorAction SilentlyContinue
                    if ($existingUser) {
                        $identityKey = $existingUser.Identity
                        $identityName = $existingUser.Name
                    }
                }
                elseif ($User -is [string]) {
                    $existingUser = Get-VergeUser -Name $User -Server $Server -ErrorAction SilentlyContinue
                    if ($existingUser) {
                        $identityKey = $existingUser.Identity
                        $identityName = $existingUser.Name
                    }
                }

                if (-not $identityKey) {
                    Write-Error -Message "User not found: $User" -ErrorId 'UserNotFound' -Category ObjectNotFound
                    return
                }
            }
            'ByGroup' {
                if ($Group -is [PSCustomObject] -and $Group.PSObject.TypeNames -contains 'Verge.Group') {
                    $identityKey = $Group.Identity
                    $identityName = $Group.Name
                }
                elseif ($Group -is [int]) {
                    $existingGroup = Get-VergeGroup -Key $Group -Server $Server -ErrorAction SilentlyContinue
                    if ($existingGroup) {
                        $identityKey = $existingGroup.Identity
                        $identityName = $existingGroup.Name
                    }
                }
                elseif ($Group -is [string]) {
                    $existingGroup = Get-VergeGroup -Name $Group -Server $Server -ErrorAction SilentlyContinue
                    if ($existingGroup) {
                        $identityKey = $existingGroup.Identity
                        $identityName = $existingGroup.Name
                    }
                }

                if (-not $identityKey) {
                    Write-Error -Message "Group not found: $Group" -ErrorId 'GroupNotFound' -Category ObjectNotFound
                    return
                }
            }
        }

        # Build request body
        $body = @{
            identity = $identityKey
            table    = $Table
            row      = $RowKey
        }

        # Set permissions
        if ($FullControl) {
            $body['list'] = $true
            $body['read'] = $true
            $body['create'] = $true
            $body['modify'] = $true
            $body['delete'] = $true
        }
        else {
            $body['list'] = $List
            $body['read'] = [bool]$Read
            $body['create'] = [bool]$Create
            $body['modify'] = [bool]$Modify
            $body['delete'] = [bool]$Delete
        }

        # Build description for ShouldProcess
        $permDesc = @()
        if ($body['list']) { $permDesc += 'List' }
        if ($body['read']) { $permDesc += 'Read' }
        if ($body['create']) { $permDesc += 'Create' }
        if ($body['modify']) { $permDesc += 'Modify' }
        if ($body['delete']) { $permDesc += 'Delete' }
        $permString = if ($permDesc.Count -gt 0) { $permDesc -join ', ' } else { 'None' }

        $targetDesc = if ($RowKey -gt 0) {
            "'$identityName' on $Table (Row $RowKey)"
        }
        else {
            "'$identityName' on $Table (all)"
        }

        if ($PSCmdlet.ShouldProcess($targetDesc, "Grant Permission ($permString)")) {
            try {
                Write-Verbose "Granting permissions to '$identityName' on table '$Table'"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'permissions' -Body $body -Connection $Server

                $permKey = $response.'$key'
                Write-Verbose "Permission granted (Key: $permKey)"

                if ($PassThru -and $permKey) {
                    # Return the permission record
                    [PSCustomObject]@{
                        PSTypeName    = 'Verge.Permission'
                        Key           = [int]$permKey
                        IdentityKey   = $identityKey
                        IdentityName  = $identityName
                        Table         = $Table
                        RowKey        = $RowKey
                        IsTableLevel  = ($RowKey -eq 0)
                        CanList       = [bool]$body['list']
                        CanRead       = [bool]$body['read']
                        CanCreate     = [bool]$body['create']
                        CanModify     = [bool]$body['modify']
                        CanDelete     = [bool]$body['delete']
                    }
                }
            }
            catch {
                $errorMessage = $_.Exception.Message
                if ($errorMessage -match 'already exists' -or $errorMessage -match 'duplicate') {
                    Write-Warning "Permission already exists for '$identityName' on '$Table'"
                }
                else {
                    throw "Failed to grant permission: $errorMessage"
                }
            }
        }
    }
}
