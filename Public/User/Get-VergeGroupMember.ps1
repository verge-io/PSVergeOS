function Get-VergeGroupMember {
    <#
    .SYNOPSIS
        Retrieves members of a group in VergeOS.

    .DESCRIPTION
        Get-VergeGroupMember retrieves the users and groups that are members
        of a specified group.

    .PARAMETER Group
        The group name, key, or object to get members for.

    .PARAMETER GroupKey
        The unique key (ID) of the group to get members for.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeGroupMember -Group "Administrators"

        Retrieves all members of the Administrators group.

    .EXAMPLE
        Get-VergeGroup -Name "Developers" | Get-VergeGroupMember

        Retrieves members of the Developers group via pipeline.

    .EXAMPLE
        Get-VergeGroupMember -GroupKey 5

        Retrieves members of the group with ID 5.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.GroupMember'

    .NOTES
        Use Add-VergeGroupMember to add members to a group.
        Use Remove-VergeGroupMember to remove members from a group.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByGroup')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByGroup', ValueFromPipeline)]
        [object]$Group,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$GroupKey,

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

        if ($Group) {
            if ($Group -is [PSCustomObject] -and $Group.PSObject.TypeNames -contains 'Verge.Group') {
                $resolvedGroupKey = $Group.Key
                $groupName = $Group.Name
            }
            elseif ($Group -is [int]) {
                $resolvedGroupKey = $Group
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
        }
        elseif ($GroupKey) {
            $resolvedGroupKey = $GroupKey
        }

        if (-not $resolvedGroupKey) {
            Write-Error -Message "Could not resolve group" -ErrorId 'GroupNotFound' -Category ObjectNotFound
            return
        }

        # Build query parameters
        $queryParams = @{
            filter = "parent_group eq $resolvedGroupKey"
            fields = '$key,parent_group,member,member#$display as member_display,creator'
        }

        try {
            Write-Verbose "Querying members for group $resolvedGroupKey"
            $response = Invoke-VergeAPI -Method GET -Endpoint 'members' -Query $queryParams -Connection $Server

            # Handle both single object and array responses
            $members = if ($response -is [array]) { $response } else { @($response) }

            foreach ($member in $members) {
                # Skip null entries
                if (-not $member -or -not $member.member) {
                    continue
                }

                # Parse member reference to get type and key
                # Format is like "/v4/users/1" or "/v4/groups/2"
                $memberRef = $member.member
                $memberType = 'Unknown'
                $memberKey = $null

                if ($memberRef -match '/v4/users/(\d+)') {
                    $memberType = 'User'
                    $memberKey = [int]$Matches[1]
                }
                elseif ($memberRef -match '/v4/groups/(\d+)') {
                    $memberType = 'Group'
                    $memberKey = [int]$Matches[1]
                }

                # Create output object
                $output = [PSCustomObject]@{
                    PSTypeName    = 'Verge.GroupMember'
                    Key           = [int]$member.'$key'
                    GroupKey      = $resolvedGroupKey
                    GroupName     = $groupName
                    MemberType    = $memberType
                    MemberKey     = $memberKey
                    MemberName    = $member.member_display
                    MemberRef     = $memberRef
                    Creator       = $member.creator
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
