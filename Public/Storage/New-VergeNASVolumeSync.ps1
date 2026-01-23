function New-VergeNASVolumeSync {
    <#
    .SYNOPSIS
        Creates a new volume sync job in VergeOS.

    .DESCRIPTION
        New-VergeNASVolumeSync creates a volume synchronization job that copies data
        between NAS volumes. Syncs can run on a schedule or be triggered manually.

    .PARAMETER NASService
        The NAS service name or object to create the sync job on.

    .PARAMETER Name
        The name for the new sync job.

    .PARAMETER SourceVolume
        The source volume name or object to sync from.

    .PARAMETER DestinationVolume
        The destination volume name or object to sync to.

    .PARAMETER SourcePath
        Starting directory in the source volume. A trailing slash copies only contents.

    .PARAMETER DestinationPath
        Destination directory path to sync to.

    .PARAMETER Description
        Optional description for the sync job.

    .PARAMETER Include
        Array of file/directory patterns to include.

    .PARAMETER Exclude
        Array of file/directory patterns to exclude.

    .PARAMETER SyncMethod
        Sync method: Rsync or VergeSync. Default is VergeSync.

    .PARAMETER DestinationDelete
        How to handle deleted files: Never, Delete, DeleteBefore, DeleteDuring, DeleteDelay, DeleteAfter.

    .PARAMETER Workers
        Number of simultaneous workers (1-128). Default is 4.

    .PARAMETER PreserveACLs
        Preserve access control lists. Default is true.

    .PARAMETER PreservePermissions
        Preserve file permissions. Default is true.

    .PARAMETER PreserveOwner
        Preserve file owner. Default is true.

    .PARAMETER PreserveGroups
        Preserve file groups. Default is true.

    .PARAMETER PreserveModTime
        Preserve modification time. Default is true.

    .PARAMETER PreserveXattrs
        Preserve extended attributes. Default is true.

    .PARAMETER CopySymlinks
        Copy symbolic links. Default is true.

    .PARAMETER FreezeFilesystem
        Freeze filesystem before snapshot. Default is false.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeNASVolumeSync -NASService "MyNAS" -Name "DailyBackup" -SourceVolume "Data" -DestinationVolume "Backup"

        Creates a basic sync job from Data to Backup volume.

    .EXAMPLE
        New-VergeNASVolumeSync -NASService "MyNAS" -Name "SelectiveSync" -SourceVolume "Data" -DestinationVolume "Archive" -Include @("*.docx", "*.xlsx") -Exclude @("temp/*")

        Creates a sync job with include/exclude patterns.

    .OUTPUTS
        Verge.NASVolumeSync object representing the created sync job.

    .NOTES
        Use Start-VergeNASVolumeSync to manually trigger the sync.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('Service')]
        [object]$NASService,

        [Parameter(Mandatory, Position = 1)]
        [ValidateLength(1, 128)]
        [string]$Name,

        [Parameter(Mandatory, Position = 2)]
        [object]$SourceVolume,

        [Parameter(Mandatory, Position = 3)]
        [object]$DestinationVolume,

        [Parameter()]
        [string]$SourcePath,

        [Parameter()]
        [string]$DestinationPath,

        [Parameter()]
        [ValidateLength(0, 2048)]
        [string]$Description,

        [Parameter()]
        [string[]]$Include,

        [Parameter()]
        [string[]]$Exclude,

        [Parameter()]
        [ValidateSet('Rsync', 'VergeSync')]
        [string]$SyncMethod = 'VergeSync',

        [Parameter()]
        [ValidateSet('Never', 'Delete', 'DeleteBefore', 'DeleteDuring', 'DeleteDelay', 'DeleteAfter')]
        [string]$DestinationDelete = 'Never',

        [Parameter()]
        [ValidateRange(1, 128)]
        [int]$Workers = 4,

        [Parameter()]
        [bool]$PreserveACLs = $true,

        [Parameter()]
        [bool]$PreservePermissions = $true,

        [Parameter()]
        [bool]$PreserveOwner = $true,

        [Parameter()]
        [bool]$PreserveGroups = $true,

        [Parameter()]
        [bool]$PreserveModTime = $true,

        [Parameter()]
        [bool]$PreserveXattrs = $true,

        [Parameter()]
        [bool]$CopySymlinks = $true,

        [Parameter()]
        [switch]$FreezeFilesystem,

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
            # Resolve NAS service
            $serviceKey = $null
            $serviceName = $null

            if ($NASService -is [string]) {
                $serviceName = $NASService
                $serviceData = Get-VergeNASService -Name $NASService -Server $Server
                if (-not $serviceData) {
                    throw "NAS service '$NASService' not found"
                }
                $serviceKey = $serviceData.Key
                $serviceName = $serviceData.Name
            }
            elseif ($NASService.Key) {
                $serviceKey = $NASService.Key
                $serviceName = $NASService.Name
            }
            elseif ($NASService -is [int]) {
                $serviceKey = $NASService
            }

            if (-not $serviceKey) {
                throw "Could not resolve NAS service key"
            }

            # Resolve source volume
            $sourceVolumeKey = $null
            $sourceVolumeName = $null

            if ($SourceVolume -is [string]) {
                $sourceVolumeName = $SourceVolume
                $volumeData = Get-VergeNASVolume -Name $SourceVolume -Server $Server
                if (-not $volumeData) {
                    throw "Source volume '$SourceVolume' not found"
                }
                $sourceVolumeKey = $volumeData.Key
                $sourceVolumeName = $volumeData.Name
            }
            elseif ($SourceVolume.Key) {
                $sourceVolumeKey = $SourceVolume.Key
                $sourceVolumeName = $SourceVolume.Name
            }

            if (-not $sourceVolumeKey) {
                throw "Could not resolve source volume key"
            }

            # Resolve destination volume
            $destVolumeKey = $null
            $destVolumeName = $null

            if ($DestinationVolume -is [string]) {
                $destVolumeName = $DestinationVolume
                $volumeData = Get-VergeNASVolume -Name $DestinationVolume -Server $Server
                if (-not $volumeData) {
                    throw "Destination volume '$DestinationVolume' not found"
                }
                $destVolumeKey = $volumeData.Key
                $destVolumeName = $volumeData.Name
            }
            elseif ($DestinationVolume.Key) {
                $destVolumeKey = $DestinationVolume.Key
                $destVolumeName = $DestinationVolume.Name
            }

            if (-not $destVolumeKey) {
                throw "Could not resolve destination volume key"
            }

            # Build request body
            $body = @{
                service              = $serviceKey
                name                 = $Name
                type                 = 'volsync'
                source_volume        = $sourceVolumeKey
                destination_volume   = $destVolumeKey
                enabled              = $true
                sync_method          = $syncMethodMap[$SyncMethod]
                destination_delete   = $deleteMap[$DestinationDelete]
                workers              = $Workers
                preserve_ACLs        = $PreserveACLs
                preserve_permissions = $PreservePermissions
                preserve_owner       = $PreserveOwner
                preserve_groups      = $PreserveGroups
                preserve_mod_time    = $PreserveModTime
                preserve_xattrs      = $PreserveXattrs
                copy_symlinks        = $CopySymlinks
                fsfreeze             = [bool]$FreezeFilesystem
            }

            if ($SourcePath) {
                $body['source_path'] = $SourcePath
            }

            if ($DestinationPath) {
                $body['destination_path'] = $DestinationPath
            }

            if ($Description) {
                $body['description'] = $Description
            }

            if ($Include -and $Include.Count -gt 0) {
                $body['include'] = $Include -join "`n"
            }

            if ($Exclude -and $Exclude.Count -gt 0) {
                $body['exclude'] = $Exclude -join "`n"
            }

            $displaySource = $sourceVolumeName ?? $sourceVolumeKey
            $displayDest = $destVolumeName ?? $destVolumeKey

            if ($PSCmdlet.ShouldProcess("NAS '$serviceName'", "Create volume sync '$Name' ($displaySource -> $displayDest)")) {
                Write-Verbose "Creating volume sync '$Name' on NAS '$serviceName'"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'volume_syncs' -Body $body -Connection $Server

                # Return the created sync
                if ($response.'$key' -or $response.id) {
                    $syncKey = $response.'$key' ?? $response.id
                    Get-VergeNASVolumeSync -Key $syncKey -Server $Server
                }
                else {
                    Get-VergeNASVolumeSync -NASService $serviceKey -Name $Name -Server $Server
                }
            }
        }
        catch {
            $displayName = $serviceName ?? $serviceKey ?? 'unknown'
            Write-Error -Message "Failed to create volume sync on NAS '$displayName': $($_.Exception.Message)" -ErrorId 'NewVolumeSyncFailed'
        }
    }
}
