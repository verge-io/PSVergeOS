function Set-VergeNASNFSShare {
    <#
    .SYNOPSIS
        Modifies an existing NFS share in VergeOS.

    .DESCRIPTION
        Set-VergeNASNFSShare updates the configuration of an existing NFS share.
        Only the specified parameters will be modified.

    .PARAMETER Share
        An NFS share object from Get-VergeNASNFSShare.

    .PARAMETER Volume
        The name or object of the volume containing the share.

    .PARAMETER Name
        The name of the share to modify.

    .PARAMETER Key
        The unique key (ID) of the share to modify.

    .PARAMETER Description
        New description for the share.

    .PARAMETER AllowedHosts
        Comma-delimited list of allowed hosts.

    .PARAMETER AllowAll
        Allow connections from any host.

    .PARAMETER DataAccess
        Data access mode: ReadOnly or ReadWrite.

    .PARAMETER Squash
        User/group ID mapping: SquashRoot, SquashAll, or NoSquash.

    .PARAMETER AnonymousUID
        User ID for anonymous/squashed users.

    .PARAMETER AnonymousGID
        Group ID for anonymous/squashed users.

    .PARAMETER Async
        Enable or disable asynchronous mode.

    .PARAMETER Insecure
        Allow or disallow connections from ports above 1024.

    .PARAMETER NoACL
        Enable or disable ACL support.

    .PARAMETER FilesystemID
        Filesystem ID for the export.

    .PARAMETER Enabled
        Enable or disable the share.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Set-VergeNASNFSShare -Volume "FileShare" -Name "exports" -DataAccess ReadWrite

        Changes the share to read-write access.

    .EXAMPLE
        Get-VergeNASNFSShare -Volume "FileShare" -Name "public" | Set-VergeNASNFSShare -AllowedHosts "192.168.1.0/24,10.0.0.0/8"

        Updates the allowed hosts via pipeline.

    .EXAMPLE
        Set-VergeNASNFSShare -Volume "FileShare" -Name "secure" -Squash NoSquash -DataAccess ReadWrite

        Updates squash settings and data access.

    .OUTPUTS
        Verge.NASNFSShare object representing the modified share.

    .NOTES
        Use Get-VergeNASNFSShare to find shares to modify.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByVolumeAndName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [PSTypeName('Verge.NASNFSShare')]
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
        [AllowEmptyString()]
        [string]$AllowedHosts,

        [Parameter()]
        [bool]$AllowAll,

        [Parameter()]
        [ValidateSet('ReadOnly', 'ReadWrite')]
        [string]$DataAccess,

        [Parameter()]
        [ValidateSet('SquashRoot', 'SquashAll', 'NoSquash')]
        [string]$Squash,

        [Parameter()]
        [AllowEmptyString()]
        [string]$AnonymousUID,

        [Parameter()]
        [AllowEmptyString()]
        [string]$AnonymousGID,

        [Parameter()]
        [bool]$Async,

        [Parameter()]
        [bool]$Insecure,

        [Parameter()]
        [bool]$NoACL,

        [Parameter()]
        [AllowEmptyString()]
        [string]$FilesystemID,

        [Parameter()]
        [bool]$Enabled,

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

        # Map friendly names to API values
        $dataAccessMap = @{
            'ReadOnly'  = 'ro'
            'ReadWrite' = 'rw'
        }

        $squashMap = @{
            'SquashRoot' = 'root_squash'
            'SquashAll'  = 'all_squash'
            'NoSquash'   = 'no_root_squash'
        }
    }

    process {
        try {
            # Resolve share
            $targetShare = $null

            switch ($PSCmdlet.ParameterSetName) {
                'ByKey' {
                    $targetShare = Get-VergeNASNFSShare -Key $Key -Server $Server
                    if (-not $targetShare) {
                        throw "NFS share with key '$Key' not found"
                    }
                }
                'ByVolumeAndName' {
                    $targetShare = Get-VergeNASNFSShare -Volume $Volume -Name $Name -Server $Server
                    if (-not $targetShare) {
                        throw "NFS share '$Name' not found on volume '$Volume'"
                    }
                }
                'ByObject' {
                    $targetShare = $Share
                    if (-not $Server -and $Share._Connection) {
                        $Server = $Share._Connection
                    }
                }
            }

            if (-not $targetShare) {
                throw "Could not resolve NFS share"
            }

            $shareKey = $targetShare.Key ?? $targetShare.Id
            $shareName = $targetShare.Name

            # Build request body with only changed properties
            $body = @{}

            if ($PSBoundParameters.ContainsKey('Description')) {
                $body['description'] = $Description
            }

            if ($PSBoundParameters.ContainsKey('AllowedHosts')) {
                $body['allowed_hosts'] = $AllowedHosts
            }

            if ($PSBoundParameters.ContainsKey('AllowAll')) {
                $body['allow_all'] = $AllowAll
            }

            if ($PSBoundParameters.ContainsKey('DataAccess')) {
                $body['data_access'] = $dataAccessMap[$DataAccess]
            }

            if ($PSBoundParameters.ContainsKey('Squash')) {
                $body['squash'] = $squashMap[$Squash]
            }

            if ($PSBoundParameters.ContainsKey('AnonymousUID')) {
                $body['anonuid'] = $AnonymousUID
            }

            if ($PSBoundParameters.ContainsKey('AnonymousGID')) {
                $body['anongid'] = $AnonymousGID
            }

            if ($PSBoundParameters.ContainsKey('Async')) {
                $body['async'] = $Async
            }

            if ($PSBoundParameters.ContainsKey('Insecure')) {
                $body['insecure'] = $Insecure
            }

            if ($PSBoundParameters.ContainsKey('NoACL')) {
                $body['no_acl'] = $NoACL
            }

            if ($PSBoundParameters.ContainsKey('FilesystemID')) {
                $body['fsid'] = $FilesystemID
            }

            if ($PSBoundParameters.ContainsKey('Enabled')) {
                $body['enabled'] = $Enabled
            }

            if ($body.Count -eq 0) {
                Write-Warning "No changes specified for NFS share '$shareName'"
                return
            }

            # Build description of changes
            $changes = ($body.Keys | ForEach-Object {
                switch ($_) {
                    'allowed_hosts' { 'allowed hosts' }
                    'allow_all' { 'allow all' }
                    'data_access' { 'data access' }
                    'anonuid' { 'anonymous UID' }
                    'anongid' { 'anonymous GID' }
                    'no_acl' { 'ACL' }
                    'fsid' { 'filesystem ID' }
                    default { $_ }
                }
            }) -join ', '

            if ($PSCmdlet.ShouldProcess("NFS share '$shareName'", "Modify ($changes)")) {
                Write-Verbose "Modifying NFS share '$shareName' (key: $shareKey)"
                $null = Invoke-VergeAPI -Method PUT -Endpoint "volume_nfs_shares/$shareKey" -Body $body -Connection $Server

                # Return the updated share
                Get-VergeNASNFSShare -Key $shareKey -Server $Server
            }
        }
        catch {
            $displayName = $shareName ?? $shareKey ?? 'unknown'
            Write-Error -Message "Failed to modify NFS share '$displayName': $($_.Exception.Message)" -ErrorId 'SetNFSShareFailed'
        }
    }
}
