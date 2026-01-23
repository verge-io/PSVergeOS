function Get-VergeSiteSyncSchedule {
    <#
    .SYNOPSIS
        Retrieves auto sync schedules for outgoing site syncs in VergeOS.

    .DESCRIPTION
        Get-VergeSiteSyncSchedule retrieves the automatic sync schedule configurations
        that link snapshot profile periods to outgoing site syncs. These schedules
        determine which snapshots are automatically synced to remote sites.

    .PARAMETER Key
        Get a specific schedule by its key (ID).

    .PARAMETER SyncKey
        Filter schedules by outgoing sync key.

    .PARAMETER SyncName
        Filter schedules by outgoing sync name.

    .PARAMETER SiteSync
        A site sync object from Get-VergeSiteSync.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeSiteSyncSchedule

        Gets all auto sync schedules.

    .EXAMPLE
        Get-VergeSiteSync -Name "DR-Sync" | Get-VergeSiteSyncSchedule

        Gets all auto sync schedules for the specified sync.

    .EXAMPLE
        Get-VergeSiteSyncSchedule -SyncName "DR-Sync"

        Gets all auto sync schedules for the sync named "DR-Sync".

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.SiteSyncSchedule'

    .NOTES
        Auto sync schedules link snapshot profile periods to outgoing syncs.
        When a scheduled snapshot is taken, it is automatically queued for sync
        based on these configurations.

        Use New-VergeSiteSyncSchedule to add new auto sync configurations.
        Use Remove-VergeSiteSyncSchedule to remove them.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(ParameterSetName = 'List')]
        [int]$SyncKey,

        [Parameter(ParameterSetName = 'List')]
        [string]$SyncName,

        [Parameter(ValueFromPipeline, ParameterSetName = 'ByObject')]
        [PSTypeName('Verge.SiteSync')]
        [PSCustomObject]$SiteSync,

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
        # Resolve sync key from various inputs
        if ($SiteSync) {
            $SyncKey = $SiteSync.Key
        }
        elseif ($SyncName) {
            $sync = Get-VergeSiteSync -Name $SyncName -Server $Server
            if (-not $sync) {
                Write-Error -Message "Site sync not found: $SyncName" -ErrorId 'SiteSyncNotFound'
                return
            }
            $SyncKey = $sync.Key
        }

        # Build query parameters
        $queryParams = @{}
        $queryParams['fields'] = @(
            '$key'
            'site_syncs_outgoing'
            'profile_period'
            'schedule_task'
            'task'
            'retention'
            'priority'
            'do_not_expire'
            'destination_prefix'
        ) -join ','

        # Build filters
        $filters = @()

        if ($PSCmdlet.ParameterSetName -eq 'ByKey') {
            $filters += "`$key eq $Key"
        }
        elseif ($SyncKey) {
            $filters += "site_syncs_outgoing eq $SyncKey"
        }

        if ($filters.Count -gt 0) {
            $queryParams['filter'] = $filters -join ' and '
        }

        $queryParams['sort'] = '+priority'

        try {
            Write-Verbose "Querying site sync schedules from VergeOS"
            $response = Invoke-VergeAPI -Method GET -Endpoint 'site_syncs_outgoing_profile_periods' -Query $queryParams -Connection $Server

            # Handle both single object and array responses
            $schedules = if ($response -is [array]) { $response } elseif ($response) { @($response) } else { @() }

            foreach ($schedule in $schedules) {
                if (-not $schedule) {
                    continue
                }

                # Get sync name
                $syncName = $null
                if ($schedule.site_syncs_outgoing) {
                    try {
                        $syncObj = Get-VergeSiteSync -Key $schedule.site_syncs_outgoing -Server $Server
                        $syncName = $syncObj.Name
                    } catch {
                        Write-Verbose "Could not retrieve sync name: $($_.Exception.Message)"
                    }
                }

                # Get profile period details
                $profilePeriodName = $null
                $profilePeriodFrequency = $null
                if ($schedule.profile_period) {
                    try {
                        $periodQuery = @{
                            fields = 'name,frequency'
                            filter = "`$key eq $($schedule.profile_period)"
                        }
                        $periodResponse = Invoke-VergeAPI -Method GET -Endpoint 'snapshot_profile_periods' -Query $periodQuery -Connection $Server
                        if ($periodResponse) {
                            $profilePeriodName = $periodResponse.name
                            $profilePeriodFrequency = $periodResponse.frequency
                        }
                    } catch {
                        Write-Verbose "Could not retrieve profile period details: $($_.Exception.Message)"
                    }
                }

                # Convert retention from seconds to timespan
                $retentionTimeSpan = if ($schedule.retention) {
                    [TimeSpan]::FromSeconds($schedule.retention)
                } else { $null }

                # Create output object
                $output = [PSCustomObject]@{
                    PSTypeName          = 'Verge.SiteSyncSchedule'
                    Key                 = [int]$schedule.'$key'
                    SyncKey             = $schedule.site_syncs_outgoing
                    SyncName            = $syncName
                    ProfilePeriodKey    = $schedule.profile_period
                    ProfilePeriodName   = $profilePeriodName
                    Frequency           = $profilePeriodFrequency
                    RetentionSeconds    = $schedule.retention
                    Retention           = $retentionTimeSpan
                    Priority            = $schedule.priority
                    DoNotExpire         = [bool]$schedule.do_not_expire
                    DestinationPrefix   = $schedule.destination_prefix
                }

                # Add hidden property for pipeline support
                $output | Add-Member -MemberType NoteProperty -Name '_Connection' -Value $Server -Force

                Write-Output $output
            }
        }
        catch {
            Write-Error -Message "Failed to get site sync schedules: $($_.Exception.Message)" -ErrorId 'GetSiteSyncSchedulesFailed'
        }
    }
}
