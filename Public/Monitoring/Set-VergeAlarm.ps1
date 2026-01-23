function Set-VergeAlarm {
    <#
    .SYNOPSIS
        Modifies a VergeOS alarm by snoozing or resolving it.

    .DESCRIPTION
        Set-VergeAlarm allows you to snooze alarms for a specified duration or
        resolve them if they are resolvable. Snoozing an alarm temporarily hides
        it from the active alarm list.

    .PARAMETER Alarm
        An alarm object from Get-VergeAlarm. Accepts pipeline input.

    .PARAMETER Key
        The unique key (ID) of the alarm to modify.

    .PARAMETER Snooze
        Snooze the alarm. Use with -SnoozeHours or -SnoozeUntil to specify duration.

    .PARAMETER SnoozeHours
        Number of hours to snooze the alarm. Default is 24 hours.

    .PARAMETER SnoozeUntil
        Snooze the alarm until this specific date/time.

    .PARAMETER Unsnooze
        Remove the snooze from an alarm, making it active again.

    .PARAMETER Resolve
        Attempt to resolve the alarm. Only works for resolvable alarms.

    .PARAMETER PassThru
        Return the alarm object after modification.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeAlarm | Where-Object Level -eq 'Warning' | Set-VergeAlarm -Snooze

        Snooze all warning alarms for 24 hours (default).

    .EXAMPLE
        Set-VergeAlarm -Key 5 -Snooze -SnoozeHours 48

        Snooze alarm with key 5 for 48 hours.

    .EXAMPLE
        Set-VergeAlarm -Key 5 -Snooze -SnoozeUntil (Get-Date).AddDays(7)

        Snooze alarm with key 5 for one week.

    .EXAMPLE
        Get-VergeAlarm -Key 5 | Set-VergeAlarm -Unsnooze

        Remove snooze from alarm, making it active again.

    .EXAMPLE
        Get-VergeAlarm | Where-Object Resolvable | Set-VergeAlarm -Resolve

        Resolve all resolvable alarms.

    .OUTPUTS
        None by default. Verge.Alarm when -PassThru is specified.

    .NOTES
        Use Get-VergeAlarm to list alarms and their status.
        Snoozing hides the alarm temporarily but does not fix the underlying issue.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByAlarm')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByAlarm')]
        [PSTypeName('Verge.Alarm')]
        [PSCustomObject]$Alarm,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter()]
        [switch]$Snooze,

        [Parameter()]
        [ValidateRange(1, 8760)] # Max 1 year
        [int]$SnoozeHours = 24,

        [Parameter()]
        [datetime]$SnoozeUntil,

        [Parameter()]
        [switch]$Unsnooze,

        [Parameter()]
        [switch]$Resolve,

        [Parameter()]
        [switch]$PassThru,

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

        # Validate action parameters
        $actionCount = 0
        if ($Snooze) { $actionCount++ }
        if ($Unsnooze) { $actionCount++ }
        if ($Resolve) { $actionCount++ }

        if ($actionCount -eq 0) {
            throw "You must specify one of: -Snooze, -Unsnooze, or -Resolve"
        }
        if ($actionCount -gt 1) {
            throw "You can only specify one action: -Snooze, -Unsnooze, or -Resolve"
        }
    }

    process {
        # Get the alarm based on parameter set
        $targetAlarm = if ($PSCmdlet.ParameterSetName -eq 'ByAlarm') {
            $Alarm
        }
        else {
            Get-VergeAlarm -Key $Key -Server $Server
        }

        if (-not $targetAlarm) {
            Write-Error -Message "Alarm not found" -ErrorId 'AlarmNotFound'
            return
        }

        $alarmKey = $targetAlarm.Key
        $alarmStatus = $targetAlarm.Status

        # Handle Resolve action
        if ($Resolve) {
            if (-not $targetAlarm.Resolvable) {
                Write-Error -Message "Alarm '$alarmStatus' (Key: $alarmKey) is not resolvable" -ErrorId 'AlarmNotResolvable'
                return
            }

            if ($PSCmdlet.ShouldProcess("Alarm: $alarmStatus", 'Resolve')) {
                try {
                    Write-Verbose "Resolving alarm '$alarmStatus' (Key: $alarmKey)"

                    # Use row action endpoint: POST /alarms/{key}/resolve
                    $null = Invoke-VergeAPI -Method POST -Endpoint "alarms/$alarmKey/resolve" -Connection $Server

                    Write-Verbose "Alarm '$alarmStatus' has been resolved"

                    if ($PassThru) {
                        # Alarm may no longer exist after resolve, so handle gracefully
                        $resolvedAlarm = Get-VergeAlarm -Key $alarmKey -Server $Server
                        if ($resolvedAlarm) {
                            Write-Output $resolvedAlarm
                        }
                    }
                }
                catch {
                    Write-Error -Message "Failed to resolve alarm '$alarmStatus': $($_.Exception.Message)" -ErrorId 'AlarmResolveFailed'
                }
            }
            return
        }

        # Handle Unsnooze action
        if ($Unsnooze) {
            if (-not $targetAlarm.IsSnoozed) {
                Write-Warning "Alarm '$alarmStatus' (Key: $alarmKey) is not currently snoozed."
                if ($PassThru) {
                    Write-Output $targetAlarm
                }
                return
            }

            if ($PSCmdlet.ShouldProcess("Alarm: $alarmStatus", 'Unsnooze')) {
                try {
                    Write-Verbose "Removing snooze from alarm '$alarmStatus' (Key: $alarmKey)"

                    $body = @{
                        snooze = 0
                    }

                    $null = Invoke-VergeAPI -Method PUT -Endpoint "alarms/$alarmKey" -Body $body -Connection $Server

                    Write-Verbose "Alarm '$alarmStatus' has been unsnoozed"

                    if ($PassThru) {
                        Get-VergeAlarm -Key $alarmKey -Server $Server
                    }
                }
                catch {
                    Write-Error -Message "Failed to unsnooze alarm '$alarmStatus': $($_.Exception.Message)" -ErrorId 'AlarmUnsnoozeFailed'
                }
            }
            return
        }

        # Handle Snooze action
        if ($Snooze) {
            # Calculate snooze timestamp
            $snoozeTimestamp = if ($SnoozeUntil) {
                [DateTimeOffset]::new($SnoozeUntil).ToUnixTimeSeconds()
            }
            else {
                [DateTimeOffset]::UtcNow.AddHours($SnoozeHours).ToUnixTimeSeconds()
            }

            $snoozeDisplay = if ($SnoozeUntil) {
                $SnoozeUntil.ToString('g')
            }
            else {
                "$SnoozeHours hours"
            }

            if ($PSCmdlet.ShouldProcess("Alarm: $alarmStatus", "Snooze for $snoozeDisplay")) {
                try {
                    Write-Verbose "Snoozing alarm '$alarmStatus' (Key: $alarmKey) for $snoozeDisplay"

                    $body = @{
                        snooze = $snoozeTimestamp
                    }

                    $null = Invoke-VergeAPI -Method PUT -Endpoint "alarms/$alarmKey" -Body $body -Connection $Server

                    Write-Verbose "Alarm '$alarmStatus' has been snoozed"

                    if ($PassThru) {
                        # ByKey lookup doesn't filter by snooze status, so no -IncludeSnoozed needed
                        Get-VergeAlarm -Key $alarmKey -Server $Server
                    }
                }
                catch {
                    Write-Error -Message "Failed to snooze alarm '$alarmStatus': $($_.Exception.Message)" -ErrorId 'AlarmSnoozeFailed'
                }
            }
        }
    }
}
