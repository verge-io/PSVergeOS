function Remove-VergeGroupMember {
    <#
    .SYNOPSIS
        Removes a member from a group in VergeOS.

    .DESCRIPTION
        Remove-VergeGroupMember removes a user or group membership
        from the specified group.

    .PARAMETER Key
        The unique key (ID) of the membership record to remove.

    .PARAMETER GroupMember
        A group member object from Get-VergeGroupMember to remove.

    .PARAMETER Group
        The group to remove the member from.

    .PARAMETER User
        The user to remove from the group.

    .PARAMETER MemberGroup
        The member group to remove from the parent group.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeGroupMember -Key 5

        Removes the membership record with ID 5.

    .EXAMPLE
        Get-VergeGroupMember -Group "Developers" | Remove-VergeGroupMember

        Removes all members from the Developers group.

    .EXAMPLE
        Remove-VergeGroupMember -Group "Administrators" -User "jsmith"

        Removes user jsmith from the Administrators group.

    .OUTPUTS
        None

    .NOTES
        Use Get-VergeGroupMember to find membership records.
        Use Add-VergeGroupMember to add members back.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByKey')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [PSTypeName('Verge.GroupMember')]
        [PSCustomObject]$GroupMember,

        [Parameter(Mandatory, ParameterSetName = 'ByGroupAndUser')]
        [Parameter(Mandatory, ParameterSetName = 'ByGroupAndGroup')]
        [object]$Group,

        [Parameter(Mandatory, ParameterSetName = 'ByGroupAndUser')]
        [object]$User,

        [Parameter(Mandatory, ParameterSetName = 'ByGroupAndGroup')]
        [object]$MemberGroup,

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
        # Resolve membership key
        $membershipKey = $null
        $displayName = $null

        switch ($PSCmdlet.ParameterSetName) {
            'ByKey' {
                $membershipKey = $Key
                $displayName = "Membership $Key"
            }
            'ByObject' {
                $membershipKey = $GroupMember.Key
                $displayName = "$($GroupMember.MemberType) '$($GroupMember.MemberName)' from group '$($GroupMember.GroupName)'"
                if (-not $Server -and $GroupMember._Connection) {
                    $Server = $GroupMember._Connection
                }
            }
            'ByGroupAndUser' {
                # Resolve group
                $resolvedGroupKey = $null
                if ($Group -is [PSCustomObject] -and $Group.PSObject.TypeNames -contains 'Verge.Group') {
                    $resolvedGroupKey = $Group.Key
                }
                elseif ($Group -is [int]) {
                    $resolvedGroupKey = $Group
                }
                elseif ($Group -is [string]) {
                    $existingGroup = Get-VergeGroup -Name $Group -Server $Server -ErrorAction SilentlyContinue
                    if ($existingGroup) { $resolvedGroupKey = $existingGroup.Key }
                }

                # Resolve user
                $resolvedUserKey = $null
                if ($User -is [PSCustomObject] -and $User.PSObject.TypeNames -contains 'Verge.User') {
                    $resolvedUserKey = $User.Key
                }
                elseif ($User -is [int]) {
                    $resolvedUserKey = $User
                }
                elseif ($User -is [string]) {
                    $existingUser = Get-VergeUser -Name $User -Server $Server -ErrorAction SilentlyContinue
                    if ($existingUser) { $resolvedUserKey = $existingUser.Key }
                }

                if ($resolvedGroupKey -and $resolvedUserKey) {
                    # Find the membership record
                    $members = Get-VergeGroupMember -GroupKey $resolvedGroupKey -Server $Server
                    $membership = $members | Where-Object {
                        $_.MemberType -eq 'User' -and $_.MemberKey -eq $resolvedUserKey
                    }
                    if ($membership) {
                        $membershipKey = $membership.Key
                        $displayName = "User '$($membership.MemberName)' from group"
                    }
                }
            }
            'ByGroupAndGroup' {
                # Resolve group
                $resolvedGroupKey = $null
                if ($Group -is [PSCustomObject] -and $Group.PSObject.TypeNames -contains 'Verge.Group') {
                    $resolvedGroupKey = $Group.Key
                }
                elseif ($Group -is [int]) {
                    $resolvedGroupKey = $Group
                }
                elseif ($Group -is [string]) {
                    $existingGroup = Get-VergeGroup -Name $Group -Server $Server -ErrorAction SilentlyContinue
                    if ($existingGroup) { $resolvedGroupKey = $existingGroup.Key }
                }

                # Resolve member group
                $resolvedMemberGroupKey = $null
                if ($MemberGroup -is [PSCustomObject] -and $MemberGroup.PSObject.TypeNames -contains 'Verge.Group') {
                    $resolvedMemberGroupKey = $MemberGroup.Key
                }
                elseif ($MemberGroup -is [int]) {
                    $resolvedMemberGroupKey = $MemberGroup
                }
                elseif ($MemberGroup -is [string]) {
                    $existingMemberGroup = Get-VergeGroup -Name $MemberGroup -Server $Server -ErrorAction SilentlyContinue
                    if ($existingMemberGroup) { $resolvedMemberGroupKey = $existingMemberGroup.Key }
                }

                if ($resolvedGroupKey -and $resolvedMemberGroupKey) {
                    # Find the membership record
                    $members = Get-VergeGroupMember -GroupKey $resolvedGroupKey -Server $Server
                    $membership = $members | Where-Object {
                        $_.MemberType -eq 'Group' -and $_.MemberKey -eq $resolvedMemberGroupKey
                    }
                    if ($membership) {
                        $membershipKey = $membership.Key
                        $displayName = "Group '$($membership.MemberName)' from group"
                    }
                }
            }
        }

        if (-not $membershipKey) {
            Write-Error -Message "Could not resolve membership record" -ErrorId 'MembershipNotFound' -Category ObjectNotFound
            return
        }

        if ($PSCmdlet.ShouldProcess($displayName, 'Remove Group Membership')) {
            try {
                Write-Verbose "Removing membership (Key: $membershipKey)"
                Invoke-VergeAPI -Method DELETE -Endpoint "members/$membershipKey" -Connection $Server | Out-Null

                Write-Verbose "Membership removed successfully"
            }
            catch {
                throw "Failed to remove membership: $($_.Exception.Message)"
            }
        }
    }
}
