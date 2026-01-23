function Get-VergeSnapshotProfile {
    <#
    .SYNOPSIS
        Retrieves snapshot profiles from VergeOS.

    .DESCRIPTION
        Get-VergeSnapshotProfile retrieves snapshot profile information from a VergeOS system.
        Snapshot profiles define automated snapshot schedules for VMs, volumes, and cloud snapshots.

    .PARAMETER Name
        Filter by snapshot profile name. Supports wildcards (* and ?).

    .PARAMETER Key
        Get a specific snapshot profile by its key (ID).

    .PARAMETER IncludePeriods
        Include the snapshot schedule periods in the output.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeSnapshotProfile

        Gets all snapshot profiles.

    .EXAMPLE
        Get-VergeSnapshotProfile -Name "Daily*"

        Gets snapshot profiles with names starting with "Daily".

    .EXAMPLE
        Get-VergeSnapshotProfile -Name "Production" -IncludePeriods

        Gets the "Production" snapshot profile including its schedule periods.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.SnapshotProfile'

    .NOTES
        Snapshot profiles are used to automate snapshot creation for:
        - Virtual machines (machine_snapshots)
        - NAS volumes (volume_snapshots)
        - Cloud/System snapshots (cloud_snapshots)
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ParameterSetName = 'List')]
        [SupportsWildcards()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter()]
        [switch]$IncludePeriods,

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
        # Build query parameters
        $queryParams = @{}
        $queryParams['fields'] = @(
            '$key'
            'name'
            'description'
            'ignore_warnings'
        ) -join ','

        # Handle specific key lookup
        if ($PSCmdlet.ParameterSetName -eq 'ByKey') {
            $queryParams['filter'] = "`$key eq $Key"
        }
        elseif ($Name -and $Name -notmatch '[\*\?]') {
            # Exact name match
            $queryParams['filter'] = "name eq '$Name'"
        }

        $queryParams['sort'] = '+name'

        try {
            Write-Verbose "Querying snapshot profiles from VergeOS"
            $response = Invoke-VergeAPI -Method GET -Endpoint 'snapshot_profiles' -Query $queryParams -Connection $Server

            # Handle both single object and array responses
            $profiles = if ($response -is [array]) { $response } elseif ($response) { @($response) } else { @() }

            foreach ($profile in $profiles) {
                if (-not $profile -or -not $profile.name) {
                    continue
                }

                # Apply wildcard filter if specified
                if ($Name -and $Name -match '[\*\?]') {
                    if ($profile.name -notlike $Name) {
                        continue
                    }
                }

                # Get periods if requested
                $periods = @()
                if ($IncludePeriods) {
                    try {
                        $periodParams = @{
                            'fields' = @(
                                '$key'
                                'name'
                                'frequency'
                                'minute'
                                'hour'
                                'day_of_week'
                                'day_of_month'
                                'month'
                                'retention'
                                'skip_missed'
                                'max_tier'
                                'quiesce'
                                'min_snapshots'
                                'immutable'
                            ) -join ','
                            'filter' = "profile eq $($profile.'$key')"
                            'sort' = '+name'
                        }
                        $periodResponse = Invoke-VergeAPI -Method GET -Endpoint 'snapshot_profile_periods' -Query $periodParams -Connection $Server
                        $periodList = if ($periodResponse -is [array]) { $periodResponse } elseif ($periodResponse) { @($periodResponse) } else { @() }

                        foreach ($period in $periodList) {
                            if (-not $period) { continue }

                            # Convert retention seconds to timespan
                            $retentionSpan = if ($period.retention) {
                                [TimeSpan]::FromSeconds($period.retention)
                            } else { $null }

                            $periodObj = [PSCustomObject]@{
                                PSTypeName   = 'Verge.SnapshotProfilePeriod'
                                Key          = [int]$period.'$key'
                                Name         = $period.name
                                Frequency    = $period.frequency
                                Minute       = $period.minute
                                Hour         = $period.hour
                                DayOfWeek    = $period.day_of_week
                                DayOfMonth   = $period.day_of_month
                                Month        = $period.month
                                Retention    = $retentionSpan
                                RetentionSeconds = $period.retention
                                SkipMissed   = [bool]$period.skip_missed
                                MaxTier      = $period.max_tier
                                Quiesce      = [bool]$period.quiesce
                                MinSnapshots = $period.min_snapshots
                                Immutable    = [bool]$period.immutable
                            }
                            $periods += $periodObj
                        }
                    }
                    catch {
                        Write-Warning "Failed to retrieve periods for profile '$($profile.name)': $($_.Exception.Message)"
                    }
                }

                # Create output object
                $output = [PSCustomObject]@{
                    PSTypeName     = 'Verge.SnapshotProfile'
                    Key            = [int]$profile.'$key'
                    Name           = $profile.name
                    Description    = $profile.description
                    IgnoreWarnings = [bool]$profile.ignore_warnings
                }

                if ($IncludePeriods) {
                    $output | Add-Member -MemberType NoteProperty -Name 'Periods' -Value $periods -Force
                }

                # Add hidden property for pipeline support
                $output | Add-Member -MemberType NoteProperty -Name '_Connection' -Value $Server -Force

                Write-Output $output
            }
        }
        catch {
            Write-Error -Message "Failed to get snapshot profiles: $($_.Exception.Message)" -ErrorId 'GetSnapshotProfilesFailed'
        }
    }
}
