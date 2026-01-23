function Add-VergeGroupMember {
    <#
    .SYNOPSIS
        Adds a user or group as a member of a group in VergeOS.

    .DESCRIPTION
        Add-VergeGroupMember adds a user or another group as a member
        of the specified group.

    .PARAMETER Group
        The group name, key, or object to add the member to.

    .PARAMETER GroupKey
        The unique key (ID) of the group to add the member to.

    .PARAMETER User
        The user name, key, or object to add as a member.

    .PARAMETER MemberGroup
        The group name, key, or object to add as a member (for nested groups).

    .PARAMETER PassThru
        Return the created membership object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Add-VergeGroupMember -Group "Developers" -User "jsmith"

        Adds user jsmith to the Developers group.

    .EXAMPLE
        Get-VergeUser -Name "jsmith" | Add-VergeGroupMember -Group "Administrators"

        Adds a user to a group via pipeline.

    .EXAMPLE
        Add-VergeGroupMember -Group "AllUsers" -MemberGroup "Developers"

        Adds the Developers group as a member of AllUsers (nested group).

    .OUTPUTS
        None by default. Verge.GroupMember when -PassThru is specified.

    .NOTES
        Use Get-VergeGroupMember to list members.
        Use Remove-VergeGroupMember to remove members.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'UserByName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [object]$Group,

        [Parameter(Mandatory, ParameterSetName = 'UserByName', ValueFromPipeline)]
        [Parameter(Mandatory, ParameterSetName = 'UserByKey')]
        [object]$User,

        [Parameter(Mandatory, ParameterSetName = 'GroupMember')]
        [object]$MemberGroup,

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
        # Resolve group key
        $resolvedGroupKey = $null
        $groupName = $null

        if ($Group -is [PSCustomObject] -and $Group.PSObject.TypeNames -contains 'Verge.Group') {
            $resolvedGroupKey = $Group.Key
            $groupName = $Group.Name
        }
        elseif ($Group -is [int]) {
            $resolvedGroupKey = $Group
            $existingGroup = Get-VergeGroup -Key $Group -Server $Server -ErrorAction SilentlyContinue
            $groupName = if ($existingGroup) { $existingGroup.Name } else { "Group $Group" }
        }
        elseif ($Group -is [string]) {
            $existingGroup = Get-VergeGroup -Name $Group -Server $Server -ErrorAction SilentlyContinue
            if ($existingGroup) {
                $resolvedGroupKey = $existingGroup.Key
                $groupName = $existingGroup.Name
            }
            else {
                Write-Error -Message "Group not found: $Group" -ErrorId 'GroupNotFound' -Category ObjectNotFound
                return
            }
        }

        if (-not $resolvedGroupKey) {
            Write-Error -Message "Could not resolve target group" -ErrorId 'GroupNotFound' -Category ObjectNotFound
            return
        }

        # Resolve member (user or group)
        $memberRef = $null
        $memberName = $null
        $memberType = $null

        if ($User) {
            $memberType = 'User'
            if ($User -is [PSCustomObject] -and $User.PSObject.TypeNames -contains 'Verge.User') {
                $memberRef = "/v4/users/$($User.Key)"
                $memberName = $User.Name
            }
            elseif ($User -is [int]) {
                $memberRef = "/v4/users/$User"
                $existingUser = Get-VergeUser -Key $User -Server $Server -ErrorAction SilentlyContinue
                $memberName = if ($existingUser) { $existingUser.Name } else { "User $User" }
            }
            elseif ($User -is [string]) {
                $existingUser = Get-VergeUser -Name $User -Server $Server -ErrorAction SilentlyContinue
                if ($existingUser) {
                    $memberRef = "/v4/users/$($existingUser.Key)"
                    $memberName = $existingUser.Name
                }
                else {
                    Write-Error -Message "User not found: $User" -ErrorId 'UserNotFound' -Category ObjectNotFound
                    return
                }
            }
        }
        elseif ($MemberGroup) {
            $memberType = 'Group'
            if ($MemberGroup -is [PSCustomObject] -and $MemberGroup.PSObject.TypeNames -contains 'Verge.Group') {
                $memberRef = "/v4/groups/$($MemberGroup.Key)"
                $memberName = $MemberGroup.Name
            }
            elseif ($MemberGroup -is [int]) {
                $memberRef = "/v4/groups/$MemberGroup"
                $existingMemberGroup = Get-VergeGroup -Key $MemberGroup -Server $Server -ErrorAction SilentlyContinue
                $memberName = if ($existingMemberGroup) { $existingMemberGroup.Name } else { "Group $MemberGroup" }
            }
            elseif ($MemberGroup -is [string]) {
                $existingMemberGroup = Get-VergeGroup -Name $MemberGroup -Server $Server -ErrorAction SilentlyContinue
                if ($existingMemberGroup) {
                    $memberRef = "/v4/groups/$($existingMemberGroup.Key)"
                    $memberName = $existingMemberGroup.Name
                }
                else {
                    Write-Error -Message "Member group not found: $MemberGroup" -ErrorId 'GroupNotFound' -Category ObjectNotFound
                    return
                }
            }
        }

        if (-not $memberRef) {
            Write-Error -Message "Could not resolve member" -ErrorId 'MemberNotFound' -Category ObjectNotFound
            return
        }

        # Build request body
        $body = @{
            parent_group = $resolvedGroupKey
            member       = $memberRef
        }

        if ($PSCmdlet.ShouldProcess("$memberType '$memberName'", "Add to Group '$groupName'")) {
            try {
                Write-Verbose "Adding $memberType '$memberName' to group '$groupName'"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'members' -Body $body -Connection $Server

                $membershipKey = $response.'$key'
                Write-Verbose "$memberType '$memberName' added to group '$groupName' (Membership Key: $membershipKey)"

                if ($PassThru -and $membershipKey) {
                    # Return the membership record
                    [PSCustomObject]@{
                        PSTypeName    = 'Verge.GroupMember'
                        Key           = [int]$membershipKey
                        GroupKey      = $resolvedGroupKey
                        GroupName     = $groupName
                        MemberType    = $memberType
                        MemberName    = $memberName
                        MemberRef     = $memberRef
                    }
                }
            }
            catch {
                $errorMessage = $_.Exception.Message
                if ($errorMessage -match 'already') {
                    Write-Warning "$memberType '$memberName' is already a member of group '$groupName'"
                }
                else {
                    throw "Failed to add $memberType to group: $errorMessage"
                }
            }
        }
    }
}
