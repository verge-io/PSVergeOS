function Invoke-VergeSiteSync {
    <#
    .SYNOPSIS
        Manually queues a cloud snapshot for sync to a remote site.

    .DESCRIPTION
        Invoke-VergeSiteSync adds a cloud snapshot to the transfer queue for an
        outgoing site sync. This allows manual syncing of specific snapshots
        outside of the automatic schedule.

    .PARAMETER SyncKey
        The key (ID) of the outgoing sync to use.

    .PARAMETER SyncName
        The name of the outgoing sync to use.

    .PARAMETER SiteSync
        A site sync object from Get-VergeSiteSync.

    .PARAMETER SnapshotKey
        The key (ID) of the cloud snapshot to sync.

    .PARAMETER SnapshotName
        The name of the cloud snapshot to sync.

    .PARAMETER CloudSnapshot
        A cloud snapshot object from Get-VergeCloudSnapshot.

    .PARAMETER Retention
        How long to keep the snapshot on the remote site.
        Accepts TimeSpan or seconds as integer. Default is 3 days (259200 seconds).

    .PARAMETER Priority
        The priority for syncing (lower numbers sync first). Default is 0.

    .PARAMETER DoNotExpire
        If set, the snapshot will stay in the queue without expiring until sent.

    .PARAMETER DestinationPrefix
        Prefix to add to the snapshot name on the destination.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Invoke-VergeSiteSync -SyncName "DR-Sync" -SnapshotName "Manual-2024-01-15"

        Queues the specified snapshot for sync with default retention.

    .EXAMPLE
        Get-VergeCloudSnapshot -Name "Pre-Update*" | Invoke-VergeSiteSync -SyncName "DR-Sync" -Retention (New-TimeSpan -Days 30)

        Queues all matching snapshots for sync with 30 day retention.

    .EXAMPLE
        Invoke-VergeSiteSync -SyncKey 1 -SnapshotKey 5 -Priority 1 -DoNotExpire

        Queues a snapshot with high priority that won't expire until synced.

    .OUTPUTS
        PSCustomObject with queue item details

    .NOTES
        The snapshot is added to the sync queue and will be transferred when the
        sync is enabled and the transfer begins.

        Use Get-VergeSiteSyncQueue to see queued snapshots.
        Use Start-VergeSiteSync to enable a disabled sync.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'ByName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [Parameter(Mandatory, ParameterSetName = 'ByKeySnapshot')]
        [Parameter(Mandatory, ParameterSetName = 'ByKeySnapshotObj')]
        [int]$SyncKey,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [Parameter(Mandatory, ParameterSetName = 'ByNameSnapshot')]
        [Parameter(Mandatory, ParameterSetName = 'ByNameSnapshotObj')]
        [string]$SyncName,

        [Parameter(Mandatory, ParameterSetName = 'ByObject')]
        [Parameter(Mandatory, ParameterSetName = 'ByObjectSnapshot')]
        [Parameter(Mandatory, ParameterSetName = 'ByObjectSnapshotObj')]
        [PSTypeName('Verge.SiteSync')]
        [PSCustomObject]$SiteSync,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [Parameter(Mandatory, ParameterSetName = 'ByObject')]
        [int]$SnapshotKey,

        [Parameter(Mandatory, ParameterSetName = 'ByKeySnapshot')]
        [Parameter(Mandatory, ParameterSetName = 'ByNameSnapshot')]
        [Parameter(Mandatory, ParameterSetName = 'ByObjectSnapshot')]
        [string]$SnapshotName,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByKeySnapshotObj')]
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByNameSnapshotObj')]
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObjectSnapshotObj')]
        [PSTypeName('Verge.CloudSnapshot')]
        [PSCustomObject]$CloudSnapshot,

        [Parameter()]
        [object]$Retention = 259200,

        [Parameter()]
        [int]$Priority = 0,

        [Parameter()]
        [switch]$DoNotExpire,

        [Parameter()]
        [ValidatePattern('^[a-zA-Z0-9 :_.,+-]*$')]
        [string]$DestinationPrefix,

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

        # Convert retention to seconds
        $retentionSeconds = if ($Retention -is [TimeSpan]) {
            [int]$Retention.TotalSeconds
        }
        elseif ($Retention -is [int] -or $Retention -is [long]) {
            [int]$Retention
        }
        else {
            throw [System.ArgumentException]::new(
                'Retention must be a TimeSpan or an integer representing seconds.'
            )
        }

        # Resolve sync key (in begin block since it's the same for all pipeline items)
        $targetSyncKey = $null
        $targetSyncName = $null

        if ($SiteSync) {
            $targetSyncKey = $SiteSync.Key
            $targetSyncName = $SiteSync.Name
        }
        elseif ($SyncKey) {
            $targetSyncKey = $SyncKey
            $sync = Get-VergeSiteSync -Key $SyncKey -Server $Server
            if ($sync) {
                $targetSyncName = $sync.Name
            }
        }
        elseif ($SyncName) {
            $sync = Get-VergeSiteSync -Name $SyncName -Server $Server
            if (-not $sync) {
                throw [System.InvalidOperationException]::new(
                    "Site sync not found: $SyncName"
                )
            }
            $targetSyncKey = $sync.Key
            $targetSyncName = $sync.Name
        }
    }

    process {
        # Resolve snapshot key
        $targetSnapshotKey = $null
        $targetSnapshotName = $null

        if ($CloudSnapshot) {
            $targetSnapshotKey = $CloudSnapshot.Key
            $targetSnapshotName = $CloudSnapshot.Name
        }
        elseif ($SnapshotKey) {
            $targetSnapshotKey = $SnapshotKey
            try {
                $snap = Get-VergeCloudSnapshot -Key $SnapshotKey -Server $Server
                if ($snap) {
                    $targetSnapshotName = $snap.Name
                }
            } catch {
                Write-Verbose "Could not retrieve snapshot name"
            }
        }
        elseif ($SnapshotName) {
            $snap = Get-VergeCloudSnapshot -Name $SnapshotName -Server $Server
            if (-not $snap) {
                Write-Error -Message "Cloud snapshot not found: $SnapshotName" -ErrorId 'CloudSnapshotNotFound'
                return
            }
            # Handle multiple matches
            if ($snap -is [array]) {
                Write-Error -Message "Multiple snapshots found matching '$SnapshotName'. Please use -SnapshotKey for a specific snapshot." -ErrorId 'MultipleSnapshotsFound'
                return
            }
            $targetSnapshotKey = $snap.Key
            $targetSnapshotName = $snap.Name
        }

        if (-not $targetSnapshotKey) {
            Write-Error -Message "Could not resolve cloud snapshot" -ErrorId 'SnapshotNotResolved'
            return
        }

        $description = "Snapshot '$targetSnapshotName' to Sync '$targetSyncName'"

        if ($PSCmdlet.ShouldProcess($description, 'Queue for sync')) {
            # Build params for add_to_queue action
            $params = @{
                cloud_snapshot = $targetSnapshotKey
                retention = $retentionSeconds
                priority = $Priority
                do_not_expire = [bool]$DoNotExpire
            }

            if ($DestinationPrefix) {
                $params['destination_prefix'] = $DestinationPrefix
            }

            $body = @{
                site_syncs_outgoing = $targetSyncKey
                action = 'add_to_queue'
                params = $params
            }

            try {
                Write-Verbose "Queueing snapshot $targetSnapshotKey for sync $targetSyncKey"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'site_syncs_outgoing_actions' -Body $body -Connection $Server

                Write-Verbose "Snapshot queued successfully"

                # Return queue information
                [PSCustomObject]@{
                    PSTypeName      = 'Verge.SiteSyncQueueItem'
                    SyncKey         = $targetSyncKey
                    SyncName        = $targetSyncName
                    SnapshotKey     = $targetSnapshotKey
                    SnapshotName    = $targetSnapshotName
                    Retention       = [TimeSpan]::FromSeconds($retentionSeconds)
                    Priority        = $Priority
                    DoNotExpire     = [bool]$DoNotExpire
                    Status          = 'Queued'
                }
            }
            catch {
                Write-Error -Message "Failed to queue snapshot for sync: $($_.Exception.Message)" -ErrorId 'QueueSnapshotFailed'
            }
        }
    }
}
