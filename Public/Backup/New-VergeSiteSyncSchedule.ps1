function New-VergeSiteSyncSchedule {
    <#
    .SYNOPSIS
        Creates an auto sync schedule for an outgoing site sync in VergeOS.

    .DESCRIPTION
        New-VergeSiteSyncSchedule links a snapshot profile period to an outgoing site sync,
        enabling automatic syncing of snapshots taken by that profile period to the remote site.

    .PARAMETER SyncKey
        The key (ID) of the outgoing sync to add the schedule to.

    .PARAMETER SyncName
        The name of the outgoing sync to add the schedule to.

    .PARAMETER SiteSync
        A site sync object from Get-VergeSiteSync.

    .PARAMETER ProfilePeriodKey
        The key (ID) of the snapshot profile period to sync.

    .PARAMETER ProfilePeriodName
        The name of the snapshot profile period to sync.
        Format: "ProfileName/PeriodName" (e.g., "Default/Daily")

    .PARAMETER Retention
        How long to keep synced snapshots on the remote site.
        Accepts TimeSpan or seconds as integer.

    .PARAMETER Priority
        The priority for syncing (lower numbers sync first). Default is auto-assigned.

    .PARAMETER DoNotExpire
        If set, the source snapshot will not expire until it has been synced.

    .PARAMETER DestinationPrefix
        Prefix to add to the snapshot name on the destination. Default is "remote".

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeSiteSyncSchedule -SyncName "DR-Sync" -ProfilePeriodKey 1 -Retention (New-TimeSpan -Days 7)

        Adds an auto sync schedule for profile period 1 with 7 day retention.

    .EXAMPLE
        Get-VergeSiteSync -Name "DR-Sync" | New-VergeSiteSyncSchedule -ProfilePeriodKey 2 -Retention 604800

        Adds an auto sync schedule with retention specified in seconds (7 days).

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.SiteSyncSchedule'

    .NOTES
        After creating a schedule, snapshots taken by the linked profile period will
        automatically be queued for sync to the remote site.

        Use Get-VergeSnapshotProfile to see available snapshot profiles and their periods.
        Use Remove-VergeSiteSyncSchedule to remove a schedule.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [Parameter(Mandatory, ParameterSetName = 'ByKeyPeriodName')]
        [int]$SyncKey,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [Parameter(Mandatory, ParameterSetName = 'ByNamePeriodName')]
        [string]$SyncName,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObjectPeriodName')]
        [PSTypeName('Verge.SiteSync')]
        [PSCustomObject]$SiteSync,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [Parameter(Mandatory, ParameterSetName = 'ByObject')]
        [int]$ProfilePeriodKey,

        [Parameter(Mandatory, ParameterSetName = 'ByKeyPeriodName')]
        [Parameter(Mandatory, ParameterSetName = 'ByNamePeriodName')]
        [Parameter(Mandatory, ParameterSetName = 'ByObjectPeriodName')]
        [string]$ProfilePeriodName,

        [Parameter(Mandatory)]
        [object]$Retention,

        [Parameter()]
        [int]$Priority,

        [Parameter()]
        [switch]$DoNotExpire,

        [Parameter()]
        [ValidatePattern('^[a-zA-Z0-9 :_.,+-]*$')]
        [string]$DestinationPrefix = 'remote',

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
    }

    process {
        # Resolve sync key
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
                Write-Error -Message "Site sync not found: $SyncName" -ErrorId 'SiteSyncNotFound'
                return
            }
            $targetSyncKey = $sync.Key
            $targetSyncName = $sync.Name
        }

        if (-not $targetSyncKey) {
            Write-Error -Message "Could not resolve site sync" -ErrorId 'SiteSyncNotResolved'
            return
        }

        # Resolve profile period key
        $targetPeriodKey = $null
        $targetPeriodName = $null

        if ($ProfilePeriodKey) {
            $targetPeriodKey = $ProfilePeriodKey
            # Try to get period name
            try {
                $periodQuery = @{
                    fields = 'name'
                    filter = "`$key eq $ProfilePeriodKey"
                }
                $periodResponse = Invoke-VergeAPI -Method GET -Endpoint 'snapshot_profile_periods' -Query $periodQuery -Connection $Server
                if ($periodResponse) {
                    $targetPeriodName = $periodResponse.name
                }
            } catch {
                Write-Verbose "Could not retrieve profile period name"
            }
        }
        elseif ($ProfilePeriodName) {
            # Parse "ProfileName/PeriodName" format or just period name
            $parts = $ProfilePeriodName -split '/', 2
            $periodNameFilter = if ($parts.Count -eq 2) {
                "name eq '$($parts[1])'"
            } else {
                "name eq '$ProfilePeriodName'"
            }

            try {
                $periodQuery = @{
                    fields = '$key,name'
                    filter = $periodNameFilter
                }
                $periodResponse = Invoke-VergeAPI -Method GET -Endpoint 'snapshot_profile_periods' -Query $periodQuery -Connection $Server
                if ($periodResponse) {
                    $period = if ($periodResponse -is [array]) { $periodResponse[0] } else { $periodResponse }
                    $targetPeriodKey = $period.'$key'
                    $targetPeriodName = $period.name
                } else {
                    Write-Error -Message "Snapshot profile period not found: $ProfilePeriodName" -ErrorId 'ProfilePeriodNotFound'
                    return
                }
            } catch {
                Write-Error -Message "Failed to find profile period '$ProfilePeriodName': $($_.Exception.Message)" -ErrorId 'ProfilePeriodLookupFailed'
                return
            }
        }

        if (-not $targetPeriodKey) {
            Write-Error -Message "Could not resolve profile period" -ErrorId 'ProfilePeriodNotResolved'
            return
        }

        $description = "Sync '$targetSyncName' + Period '$targetPeriodName'"

        if ($PSCmdlet.ShouldProcess($description, 'Create auto sync schedule')) {
            # Build request body
            $body = @{
                site_syncs_outgoing = $targetSyncKey
                profile_period = $targetPeriodKey
                retention = $retentionSeconds
                do_not_expire = [bool]$DoNotExpire
                destination_prefix = $DestinationPrefix
            }

            if ($PSBoundParameters.ContainsKey('Priority')) {
                $body['priority'] = $Priority
            }

            try {
                Write-Verbose "Creating auto sync schedule for sync $targetSyncKey with period $targetPeriodKey"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'site_syncs_outgoing_profile_periods' -Body $body -Connection $Server

                if ($response -and $response.'$key') {
                    Write-Verbose "Schedule created with key $($response.'$key')"

                    # Retrieve the full schedule details
                    Get-VergeSiteSyncSchedule -Key $response.'$key' -Server $Server
                }
                else {
                    Write-Warning "Schedule creation returned unexpected response"
                    Write-Output $response
                }
            }
            catch {
                Write-Error -Message "Failed to create auto sync schedule: $($_.Exception.Message)" -ErrorId 'CreateSiteSyncScheduleFailed'
            }
        }
    }
}
