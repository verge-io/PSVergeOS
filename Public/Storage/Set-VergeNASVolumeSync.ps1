function Set-VergeNASVolumeSync {
    <#
    .SYNOPSIS
        Modifies an existing volume sync job in VergeOS.

    .DESCRIPTION
        Set-VergeNASVolumeSync updates the configuration of an existing volume sync job.
        Only the specified parameters will be modified.

    .PARAMETER Sync
        A volume sync object from Get-VergeNASVolumeSync.

    .PARAMETER NASService
        The NAS service name or object containing the sync job.

    .PARAMETER Name
        The name of the sync job to modify.

    .PARAMETER Key
        The unique key (ID) of the sync job to modify.

    .PARAMETER Description
        New description for the sync job.

    .PARAMETER SourcePath
        Starting directory in the source volume.

    .PARAMETER DestinationPath
        Destination directory path.

    .PARAMETER Include
        Array of file/directory patterns to include.

    .PARAMETER Exclude
        Array of file/directory patterns to exclude.

    .PARAMETER SyncMethod
        Sync method: Rsync or VergeSync.

    .PARAMETER DestinationDelete
        How to handle deleted files.

    .PARAMETER Workers
        Number of simultaneous workers (1-128).

    .PARAMETER PreserveACLs
        Preserve access control lists.

    .PARAMETER PreservePermissions
        Preserve file permissions.

    .PARAMETER PreserveOwner
        Preserve file owner.

    .PARAMETER PreserveGroups
        Preserve file groups.

    .PARAMETER PreserveModTime
        Preserve modification time.

    .PARAMETER PreserveXattrs
        Preserve extended attributes.

    .PARAMETER CopySymlinks
        Copy symbolic links.

    .PARAMETER FreezeFilesystem
        Freeze filesystem before snapshot.

    .PARAMETER Enabled
        Enable or disable the sync job.

    .PARAMETER Server
        The VergeOS connection to use.

    .EXAMPLE
        Set-VergeNASVolumeSync -NASService "MyNAS" -Name "DailyBackup" -Workers 8

        Changes the number of workers to 8.

    .EXAMPLE
        Get-VergeNASVolumeSync -Name "DailyBackup" | Set-VergeNASVolumeSync -Enabled $false

        Disables a sync job via pipeline.

    .OUTPUTS
        Verge.NASVolumeSync object representing the modified sync job.

    .NOTES
        Use Get-VergeNASVolumeSync to find sync jobs to modify.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByNASAndName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [PSTypeName('Verge.NASVolumeSync')]
        [PSCustomObject]$Sync,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByNASAndName')]
        [object]$NASService,

        [Parameter(Mandatory, Position = 1, ParameterSetName = 'ByNASAndName')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [string]$Key,

        [Parameter()]
        [ValidateLength(0, 2048)]
        [string]$Description,

        [Parameter()]
        [AllowEmptyString()]
        [string]$SourcePath,

        [Parameter()]
        [AllowEmptyString()]
        [string]$DestinationPath,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$Include,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$Exclude,

        [Parameter()]
        [ValidateSet('Rsync', 'VergeSync')]
        [string]$SyncMethod,

        [Parameter()]
        [ValidateSet('Never', 'Delete', 'DeleteBefore', 'DeleteDuring', 'DeleteDelay', 'DeleteAfter')]
        [string]$DestinationDelete,

        [Parameter()]
        [ValidateRange(1, 128)]
        [int]$Workers,

        [Parameter()]
        [bool]$PreserveACLs,

        [Parameter()]
        [bool]$PreservePermissions,

        [Parameter()]
        [bool]$PreserveOwner,

        [Parameter()]
        [bool]$PreserveGroups,

        [Parameter()]
        [bool]$PreserveModTime,

        [Parameter()]
        [bool]$PreserveXattrs,

        [Parameter()]
        [bool]$CopySymlinks,

        [Parameter()]
        [bool]$FreezeFilesystem,

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
        $syncMethodMap = @{
            'Rsync'     = 'rsync'
            'VergeSync' = 'ysync'
        }

        $deleteMap = @{
            'Never'        = 'never'
            'Delete'       = 'delete'
            'DeleteBefore' = 'delete-before'
            'DeleteDuring' = 'delete-during'
            'DeleteDelay'  = 'delete-delay'
            'DeleteAfter'  = 'delete-after'
        }
    }

    process {
        try {
            # Resolve sync job
            $targetSync = $null

            switch ($PSCmdlet.ParameterSetName) {
                'ByKey' {
                    $targetSync = Get-VergeNASVolumeSync -Key $Key -Server $Server
                    if (-not $targetSync) {
                        throw "Volume sync with key '$Key' not found"
                    }
                }
                'ByNASAndName' {
                    $targetSync = Get-VergeNASVolumeSync -NASService $NASService -Name $Name -Server $Server
                    if (-not $targetSync) {
                        throw "Volume sync '$Name' not found on NAS '$NASService'"
                    }
                }
                'ByObject' {
                    $targetSync = $Sync
                    if (-not $Server -and $Sync._Connection) {
                        $Server = $Sync._Connection
                    }
                }
            }

            if (-not $targetSync) {
                throw "Could not resolve volume sync job"
            }

            $syncKey = $targetSync.Key ?? $targetSync.Id
            $syncName = $targetSync.Name

            # Build request body with only changed properties
            $body = @{}

            if ($PSBoundParameters.ContainsKey('Description')) {
                $body['description'] = $Description
            }

            if ($PSBoundParameters.ContainsKey('SourcePath')) {
                $body['source_path'] = $SourcePath
            }

            if ($PSBoundParameters.ContainsKey('DestinationPath')) {
                $body['destination_path'] = $DestinationPath
            }

            if ($PSBoundParameters.ContainsKey('Include')) {
                $body['include'] = if ($Include -and $Include.Count -gt 0) {
                    $Include -join "`n"
                } else { '' }
            }

            if ($PSBoundParameters.ContainsKey('Exclude')) {
                $body['exclude'] = if ($Exclude -and $Exclude.Count -gt 0) {
                    $Exclude -join "`n"
                } else { '' }
            }

            if ($PSBoundParameters.ContainsKey('SyncMethod')) {
                $body['sync_method'] = $syncMethodMap[$SyncMethod]
            }

            if ($PSBoundParameters.ContainsKey('DestinationDelete')) {
                $body['destination_delete'] = $deleteMap[$DestinationDelete]
            }

            if ($PSBoundParameters.ContainsKey('Workers')) {
                $body['workers'] = $Workers
            }

            if ($PSBoundParameters.ContainsKey('PreserveACLs')) {
                $body['preserve_ACLs'] = $PreserveACLs
            }

            if ($PSBoundParameters.ContainsKey('PreservePermissions')) {
                $body['preserve_permissions'] = $PreservePermissions
            }

            if ($PSBoundParameters.ContainsKey('PreserveOwner')) {
                $body['preserve_owner'] = $PreserveOwner
            }

            if ($PSBoundParameters.ContainsKey('PreserveGroups')) {
                $body['preserve_groups'] = $PreserveGroups
            }

            if ($PSBoundParameters.ContainsKey('PreserveModTime')) {
                $body['preserve_mod_time'] = $PreserveModTime
            }

            if ($PSBoundParameters.ContainsKey('PreserveXattrs')) {
                $body['preserve_xattrs'] = $PreserveXattrs
            }

            if ($PSBoundParameters.ContainsKey('CopySymlinks')) {
                $body['copy_symlinks'] = $CopySymlinks
            }

            if ($PSBoundParameters.ContainsKey('FreezeFilesystem')) {
                $body['fsfreeze'] = $FreezeFilesystem
            }

            if ($PSBoundParameters.ContainsKey('Enabled')) {
                $body['enabled'] = $Enabled
            }

            if ($body.Count -eq 0) {
                Write-Warning "No changes specified for volume sync '$syncName'"
                return
            }

            # Build description of changes
            $changes = ($body.Keys | ForEach-Object {
                switch ($_) {
                    'source_path' { 'source path' }
                    'destination_path' { 'destination path' }
                    'sync_method' { 'sync method' }
                    'destination_delete' { 'destination delete' }
                    'preserve_ACLs' { 'preserve ACLs' }
                    'preserve_permissions' { 'preserve permissions' }
                    'preserve_owner' { 'preserve owner' }
                    'preserve_groups' { 'preserve groups' }
                    'preserve_mod_time' { 'preserve mod time' }
                    'preserve_xattrs' { 'preserve xattrs' }
                    'copy_symlinks' { 'copy symlinks' }
                    'fsfreeze' { 'freeze filesystem' }
                    default { $_ }
                }
            }) -join ', '

            if ($PSCmdlet.ShouldProcess("Volume sync '$syncName'", "Modify ($changes)")) {
                Write-Verbose "Modifying volume sync '$syncName' (key: $syncKey)"
                $null = Invoke-VergeAPI -Method PUT -Endpoint "volume_syncs/$syncKey" -Body $body -Connection $Server

                # Return the updated sync
                Get-VergeNASVolumeSync -Key $syncKey -Server $Server
            }
        }
        catch {
            $displayName = $syncName ?? $syncKey ?? 'unknown'
            Write-Error -Message "Failed to modify volume sync '$displayName': $($_.Exception.Message)" -ErrorId 'SetVolumeSyncFailed'
        }
    }
}
