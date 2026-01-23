function Set-VergeNASCIFSShare {
    <#
    .SYNOPSIS
        Modifies an existing CIFS/SMB share in VergeOS.

    .DESCRIPTION
        Set-VergeNASCIFSShare updates the configuration of an existing CIFS (SMB) share.
        Only the specified parameters will be modified.

    .PARAMETER Share
        A CIFS share object from Get-VergeNASCIFSShare.

    .PARAMETER Volume
        The name or object of the volume containing the share.

    .PARAMETER Name
        The name of the share to modify.

    .PARAMETER Key
        The unique key (ID) of the share to modify.

    .PARAMETER Description
        New description for the share.

    .PARAMETER Comment
        Short comment about the share (visible to clients).

    .PARAMETER Enabled
        Enable or disable the share.

    .PARAMETER ReadOnly
        Set the share to read-only or read-write.

    .PARAMETER GuestOK
        Allow or disallow guest access.

    .PARAMETER GuestOnly
        Restrict the share to guest-only access.

    .PARAMETER Browseable
        Make the share visible or hidden in network browsing.

    .PARAMETER ValidUsers
        Array of usernames allowed to connect. Pass empty array to clear.

    .PARAMETER ValidGroups
        Array of group names allowed to connect. Pass empty array to clear.

    .PARAMETER AdminUsers
        Array of users with admin privileges on the share.

    .PARAMETER AdminGroups
        Array of groups with admin privileges on the share.

    .PARAMETER AllowedHosts
        Array of allowed hosts (IPs, hostnames, subnets).

    .PARAMETER DeniedHosts
        Array of denied hosts.

    .PARAMETER ForceUser
        All file operations performed as this user.

    .PARAMETER ForceGroup
        Default primary group for all connecting users.

    .PARAMETER ShadowCopy
        Enable or disable shadow copy (Previous Versions) support.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Set-VergeNASCIFSShare -Volume "FileShare" -Name "shared" -ReadOnly $true

        Makes the share read-only.

    .EXAMPLE
        Get-VergeNASCIFSShare -Volume "FileShare" -Name "public" | Set-VergeNASCIFSShare -GuestOK $false

        Disables guest access via pipeline.

    .EXAMPLE
        Set-VergeNASCIFSShare -Volume "FileShare" -Name "secure" -ValidUsers @("admin", "manager", "backup")

        Updates the list of valid users.

    .EXAMPLE
        Set-VergeNASCIFSShare -Key "abc123" -Enabled $false

        Disables a share by key.

    .OUTPUTS
        Verge.NASCIFSShare object representing the modified share.

    .NOTES
        Use Get-VergeNASCIFSShare to find shares to modify.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByVolumeAndName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [PSTypeName('Verge.NASCIFSShare')]
        [PSCustomObject]$Share,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByVolumeAndName')]
        [object]$Volume,

        [Parameter(Mandatory, Position = 1, ParameterSetName = 'ByVolumeAndName')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [string]$Key,

        [Parameter()]
        [ValidateLength(0, 2048)]
        [string]$Description,

        [Parameter()]
        [ValidateLength(0, 64)]
        [string]$Comment,

        [Parameter()]
        [bool]$Enabled,

        [Parameter()]
        [bool]$ReadOnly,

        [Parameter()]
        [bool]$GuestOK,

        [Parameter()]
        [bool]$GuestOnly,

        [Parameter()]
        [bool]$Browseable,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$ValidUsers,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$ValidGroups,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$AdminUsers,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$AdminGroups,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$AllowedHosts,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$DeniedHosts,

        [Parameter()]
        [AllowEmptyString()]
        [string]$ForceUser,

        [Parameter()]
        [AllowEmptyString()]
        [string]$ForceGroup,

        [Parameter()]
        [bool]$ShadowCopy,

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
        try {
            # Resolve share
            $targetShare = $null

            switch ($PSCmdlet.ParameterSetName) {
                'ByKey' {
                    $targetShare = Get-VergeNASCIFSShare -Key $Key -Server $Server
                    if (-not $targetShare) {
                        throw "CIFS share with key '$Key' not found"
                    }
                }
                'ByVolumeAndName' {
                    $targetShare = Get-VergeNASCIFSShare -Volume $Volume -Name $Name -Server $Server
                    if (-not $targetShare) {
                        throw "CIFS share '$Name' not found on volume '$Volume'"
                    }
                }
                'ByObject' {
                    $targetShare = $Share
                }
            }

            if (-not $targetShare) {
                throw "Could not resolve CIFS share"
            }

            $shareKey = $targetShare.Key ?? $targetShare.Id
            $shareName = $targetShare.Name

            # Build request body with only changed properties
            $body = @{}

            if ($PSBoundParameters.ContainsKey('Description')) {
                $body['description'] = $Description
            }

            if ($PSBoundParameters.ContainsKey('Comment')) {
                $body['comment'] = $Comment
            }

            if ($PSBoundParameters.ContainsKey('Enabled')) {
                $body['enabled'] = $Enabled
            }

            if ($PSBoundParameters.ContainsKey('ReadOnly')) {
                $body['read_only'] = $ReadOnly
            }

            if ($PSBoundParameters.ContainsKey('GuestOK')) {
                $body['guest_ok'] = $GuestOK
            }

            if ($PSBoundParameters.ContainsKey('GuestOnly')) {
                $body['guest_only'] = $GuestOnly
            }

            if ($PSBoundParameters.ContainsKey('Browseable')) {
                $body['browseable'] = $Browseable
            }

            if ($PSBoundParameters.ContainsKey('ValidUsers')) {
                $body['valid_users'] = if ($ValidUsers -and $ValidUsers.Count -gt 0) {
                    $ValidUsers -join "`n"
                } else { '' }
            }

            if ($PSBoundParameters.ContainsKey('ValidGroups')) {
                $body['valid_groups'] = if ($ValidGroups -and $ValidGroups.Count -gt 0) {
                    $ValidGroups -join "`n"
                } else { '' }
            }

            if ($PSBoundParameters.ContainsKey('AdminUsers')) {
                $body['admin_users'] = if ($AdminUsers -and $AdminUsers.Count -gt 0) {
                    $AdminUsers -join "`n"
                } else { '' }
            }

            if ($PSBoundParameters.ContainsKey('AdminGroups')) {
                $body['admin_groups'] = if ($AdminGroups -and $AdminGroups.Count -gt 0) {
                    $AdminGroups -join "`n"
                } else { '' }
            }

            if ($PSBoundParameters.ContainsKey('AllowedHosts')) {
                $body['host_allow'] = if ($AllowedHosts -and $AllowedHosts.Count -gt 0) {
                    $AllowedHosts -join "`n"
                } else { '' }
            }

            if ($PSBoundParameters.ContainsKey('DeniedHosts')) {
                $body['host_deny'] = if ($DeniedHosts -and $DeniedHosts.Count -gt 0) {
                    $DeniedHosts -join "`n"
                } else { '' }
            }

            if ($PSBoundParameters.ContainsKey('ForceUser')) {
                $body['force_user'] = $ForceUser
            }

            if ($PSBoundParameters.ContainsKey('ForceGroup')) {
                $body['force_group'] = $ForceGroup
            }

            if ($PSBoundParameters.ContainsKey('ShadowCopy')) {
                $body['vfs_shadow_copy2'] = $ShadowCopy
            }

            if ($body.Count -eq 0) {
                Write-Warning "No changes specified for CIFS share '$shareName'"
                return
            }

            # Build description of changes
            $changes = ($body.Keys | ForEach-Object {
                switch ($_) {
                    'valid_users' { 'valid users' }
                    'valid_groups' { 'valid groups' }
                    'admin_users' { 'admin users' }
                    'admin_groups' { 'admin groups' }
                    'host_allow' { 'allowed hosts' }
                    'host_deny' { 'denied hosts' }
                    'force_user' { 'force user' }
                    'force_group' { 'force group' }
                    'read_only' { 'read-only' }
                    'guest_ok' { 'guest access' }
                    'guest_only' { 'guest-only' }
                    'vfs_shadow_copy2' { 'shadow copy' }
                    default { $_ }
                }
            }) -join ', '

            if ($PSCmdlet.ShouldProcess("CIFS share '$shareName'", "Modify ($changes)")) {
                Write-Verbose "Modifying CIFS share '$shareName' (key: $shareKey)"
                $null = Invoke-VergeAPI -Method PUT -Endpoint "volume_cifs_shares/$shareKey" -Body $body -Connection $Server

                # Return the updated share
                Get-VergeNASCIFSShare -Key $shareKey -Server $Server
            }
        }
        catch {
            $displayName = $shareName ?? $shareKey ?? 'unknown'
            Write-Error -Message "Failed to modify CIFS share '$displayName': $($_.Exception.Message)" -ErrorId 'SetCIFSShareFailed'
        }
    }
}
