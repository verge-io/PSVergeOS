function Remove-VergeSiteSyncSchedule {
    <#
    .SYNOPSIS
        Removes an auto sync schedule from an outgoing site sync in VergeOS.

    .DESCRIPTION
        Remove-VergeSiteSyncSchedule removes a link between a snapshot profile period
        and an outgoing site sync, stopping automatic syncing of those snapshots.

    .PARAMETER Key
        The key (ID) of the schedule to remove.

    .PARAMETER Schedule
        A schedule object from Get-VergeSiteSyncSchedule. Accepts pipeline input.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeSiteSyncSchedule -Key 1

        Removes the auto sync schedule with key 1.

    .EXAMPLE
        Get-VergeSiteSyncSchedule -SyncName "DR-Sync" | Remove-VergeSiteSyncSchedule

        Removes all auto sync schedules for the specified sync.

    .EXAMPLE
        Get-VergeSiteSyncSchedule -Key 1 | Remove-VergeSiteSyncSchedule -Confirm:$false

        Removes the schedule without confirmation prompt.

    .NOTES
        Removing a schedule only stops future automatic syncing. Snapshots already
        queued or synced are not affected.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [PSTypeName('Verge.SiteSyncSchedule')]
        [PSCustomObject]$Schedule,

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
        # Resolve the schedule key
        $targetKey = if ($Schedule) { $Schedule.Key } else { $Key }
        $description = if ($Schedule) {
            "Schedule Key $targetKey (Sync: $($Schedule.SyncName), Period: $($Schedule.ProfilePeriodName))"
        } else {
            "Schedule Key $targetKey"
        }

        if ($PSCmdlet.ShouldProcess($description, 'Remove')) {
            try {
                Write-Verbose "Removing auto sync schedule with key $targetKey"
                $null = Invoke-VergeAPI -Method DELETE -Endpoint "site_syncs_outgoing_profile_periods/$targetKey" -Connection $Server
                Write-Verbose "Auto sync schedule removed successfully"
            }
            catch {
                Write-Error -Message "Failed to remove auto sync schedule: $($_.Exception.Message)" -ErrorId 'RemoveSiteSyncScheduleFailed'
            }
        }
    }
}
