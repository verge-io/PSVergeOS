function New-VergeCloudSnapshot {
    <#
    .SYNOPSIS
        Creates a new cloud (system) snapshot in VergeOS.

    .DESCRIPTION
        New-VergeCloudSnapshot creates a new cloud snapshot that captures the entire
        system state including all VMs and tenants at a point in time.

        This is an asynchronous operation that returns a task. Use -Wait to wait for
        the snapshot to complete, or use Wait-VergeTask to monitor progress.

    .PARAMETER Name
        The name for the new snapshot. If not specified, a default name with timestamp
        will be generated (format: Snapshot_YYYYMMDD_HHMM).

    .PARAMETER Retention
        How long to retain the snapshot. Can be specified as a TimeSpan or number of seconds.
        Default is 3 days (259200 seconds).

    .PARAMETER NeverExpire
        If specified, the snapshot will never expire automatically.

    .PARAMETER MinSnapshots
        Minimum number of snapshots to retain. Helps prevent having all snapshots expire
        during a prolonged outage. Default is 1.

    .PARAMETER Immutable
        If specified, the snapshot will be locked, read-only, and cannot be deleted
        until unlocked.

    .PARAMETER Private
        If specified, prevents the snapshot from being visible in tenants.

    .PARAMETER Wait
        Wait for the snapshot operation to complete before returning.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeCloudSnapshot

        Creates a cloud snapshot with default name and 3-day retention.

    .EXAMPLE
        New-VergeCloudSnapshot -Name "Pre-Upgrade" -Retention (New-TimeSpan -Days 7)

        Creates a cloud snapshot named "Pre-Upgrade" that expires in 7 days.

    .EXAMPLE
        New-VergeCloudSnapshot -Name "Permanent-Backup" -NeverExpire -Immutable

        Creates an immutable cloud snapshot that never expires.

    .EXAMPLE
        New-VergeCloudSnapshot -Name "Quick Snapshot" -Wait

        Creates a cloud snapshot and waits for it to complete.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.CloudSnapshot' (when -Wait is used)
        PSCustomObject with PSTypeName 'Verge.Task' (when -Wait is not used)

    .NOTES
        Cloud snapshots capture the entire system state. For VM-specific snapshots,
        use New-VergeVMSnapshot instead.

        Creating a cloud snapshot may take several minutes depending on system size.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'Retention')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [ValidateLength(1, 128)]
        [string]$Name,

        [Parameter(ParameterSetName = 'Retention')]
        [ValidateScript({
            if ($_ -is [TimeSpan]) { $true }
            elseif ($_ -is [int] -or $_ -is [long]) { $_ -gt 0 }
            else { throw "Retention must be a TimeSpan or positive number of seconds" }
        })]
        $Retention,

        [Parameter(Mandatory, ParameterSetName = 'NeverExpire')]
        [switch]$NeverExpire,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$MinSnapshots = 1,

        [Parameter()]
        [switch]$Immutable,

        [Parameter()]
        [switch]$Private,

        [Parameter()]
        [switch]$Wait,

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
        # Generate default name if not specified
        if (-not $Name) {
            $Name = "Snapshot_$(Get-Date -Format 'yyyyMMdd_HHmm')"
        }

        if ($PSCmdlet.ShouldProcess("Cloud Snapshot '$Name'", 'Create')) {
            # Build request body using table_actions create
            $body = @{
                name = $Name
                min_snapshots = $MinSnapshots
            }

            # Handle retention
            if ($NeverExpire) {
                # Setting retention to 0 means never expire
                $body['retention'] = 0
            }
            elseif ($PSBoundParameters.ContainsKey('Retention')) {
                if ($Retention -is [TimeSpan]) {
                    $body['retention'] = [int]$Retention.TotalSeconds
                }
                else {
                    $body['retention'] = [int]$Retention
                }
            }
            else {
                # Default: 3 days
                $body['retention'] = 259200
            }

            if ($Immutable) {
                $body['immutable'] = $true
            }

            if ($Private) {
                $body['private'] = $true
            }

            try {
                Write-Verbose "Creating cloud snapshot '$Name'"

                # The cloud_snapshots endpoint uses table_actions for create
                # POST to cloud_snapshots with the action fields
                $response = Invoke-VergeAPI -Method POST -Endpoint 'cloud_snapshots' -Body $body -Connection $Server

                if ($response) {
                    # The response should contain the task info
                    if ($response.task -or $response.'$key') {
                        $snapshotKey = $response.'$key'
                        $taskKey = $response.task

                        Write-Verbose "Cloud snapshot creation initiated (Snapshot Key: $snapshotKey, Task: $taskKey)"

                        if ($Wait -and $taskKey) {
                            Write-Verbose "Waiting for snapshot task to complete..."
                            $task = Wait-VergeTask -Key $taskKey -Server $Server

                            if ($task.Status -eq 'complete') {
                                # Return the completed snapshot
                                Get-VergeCloudSnapshot -Key $snapshotKey -Server $Server
                            }
                            else {
                                Write-Error -Message "Cloud snapshot creation failed: $($task.StatusInfo)" -ErrorId 'CreateCloudSnapshotFailed'
                            }
                        }
                        elseif ($snapshotKey) {
                            # Return the snapshot (may still be in progress)
                            Get-VergeCloudSnapshot -Key $snapshotKey -Server $Server
                        }
                        else {
                            # Return task info if no snapshot key
                            if ($taskKey) {
                                Get-VergeTask -Key $taskKey -Server $Server
                            }
                        }
                    }
                    else {
                        Write-Error -Message "Failed to create cloud snapshot: Unexpected response" -ErrorId 'CreateCloudSnapshotFailed'
                    }
                }
                else {
                    Write-Error -Message "Failed to create cloud snapshot: No response" -ErrorId 'CreateCloudSnapshotFailed'
                }
            }
            catch {
                Write-Error -Message "Failed to create cloud snapshot '$Name': $($_.Exception.Message)" -ErrorId 'CreateCloudSnapshotFailed'
            }
        }
    }
}
