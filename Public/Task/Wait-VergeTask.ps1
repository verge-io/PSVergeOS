function Wait-VergeTask {
    <#
    .SYNOPSIS
        Waits for a VergeOS task to complete.

    .DESCRIPTION
        Wait-VergeTask polls the status of a task until it completes (becomes idle)
        or the specified timeout is reached. This is useful for synchronous operations
        where you need to wait for a background task to finish.

    .PARAMETER Task
        A task object from Get-VergeTask. Accepts pipeline input.

    .PARAMETER Key
        The unique key (ID) of the task to wait for.

    .PARAMETER Name
        The name of the task to wait for.

    .PARAMETER TimeoutSeconds
        Maximum time to wait in seconds. Default is 300 (5 minutes).
        Use 0 for infinite wait.

    .PARAMETER PollingIntervalSeconds
        How often to check task status in seconds. Default is 2.

    .PARAMETER PassThru
        Return the task object when completed. By default, returns nothing on success.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Wait-VergeTask -Name "Backup VM"

        Waits for the task named "Backup VM" to complete.

    .EXAMPLE
        Get-VergeTask -Running | Wait-VergeTask

        Waits for all running tasks to complete.

    .EXAMPLE
        Wait-VergeTask -Key 5 -TimeoutSeconds 600 -PassThru

        Waits up to 10 minutes for task with key 5 and returns the task when complete.

    .EXAMPLE
        Get-VergeTask -Name "Clone*" | Wait-VergeTask -PollingIntervalSeconds 5

        Waits for all clone tasks, checking every 5 seconds.

    .OUTPUTS
        None by default. Verge.Task when -PassThru is specified.

    .NOTES
        The cmdlet shows progress while waiting.
        Use Get-VergeTask to check task status manually.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByTask')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByTask')]
        [PSTypeName('Verge.Task')]
        [PSCustomObject]$Task,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$TimeoutSeconds = 300,

        [Parameter()]
        [ValidateRange(1, 60)]
        [int]$PollingIntervalSeconds = 2,

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
    }

    process {
        # Get the task to wait for based on parameter set
        $targetTask = switch ($PSCmdlet.ParameterSetName) {
            'ByTask' {
                $Task
            }
            'ByKey' {
                Get-VergeTask -Key $Key -Server $Server
            }
            'ByName' {
                Get-VergeTask -Name $Name -Server $Server | Select-Object -First 1
            }
        }

        if (-not $targetTask) {
            Write-Error -Message "Task not found" -ErrorId 'TaskNotFound'
            return
        }

        # If task is already idle, return immediately
        if (-not $targetTask.IsRunning) {
            Write-Verbose "Task '$($targetTask.Name)' is already idle"
            if ($PassThru) {
                Write-Output $targetTask
            }
            return
        }

        $taskKey = $targetTask.Key
        $taskName = $targetTask.Name
        $startTime = Get-Date
        $progressId = Get-Random

        Write-Verbose "Waiting for task '$taskName' (Key: $taskKey) to complete..."

        try {
            while ($true) {
                # Check timeout
                $elapsed = (Get-Date) - $startTime
                if ($TimeoutSeconds -gt 0 -and $elapsed.TotalSeconds -ge $TimeoutSeconds) {
                    Write-Progress -Id $progressId -Activity "Waiting for task" -Completed
                    throw [System.TimeoutException]::new(
                        "Timeout waiting for task '$taskName' after $TimeoutSeconds seconds"
                    )
                }

                # Get current task status
                $currentTask = Get-VergeTask -Key $taskKey -Server $Server

                if (-not $currentTask) {
                    Write-Progress -Id $progressId -Activity "Waiting for task" -Completed
                    throw [System.InvalidOperationException]::new(
                        "Task '$taskName' no longer exists"
                    )
                }

                # Check if completed
                if (-not $currentTask.IsRunning) {
                    Write-Progress -Id $progressId -Activity "Waiting for task" -Completed
                    Write-Verbose "Task '$taskName' completed after $([int]$elapsed.TotalSeconds) seconds"
                    if ($PassThru) {
                        Write-Output $currentTask
                    }
                    return
                }

                # Update progress
                $statusText = "Task '$taskName' - Status: $($currentTask.Status)"
                if ($TimeoutSeconds -gt 0) {
                    $percentComplete = [Math]::Min(100, [int](($elapsed.TotalSeconds / $TimeoutSeconds) * 100))
                    $remainingSeconds = $TimeoutSeconds - [int]$elapsed.TotalSeconds
                    Write-Progress -Id $progressId -Activity "Waiting for task to complete" `
                        -Status $statusText `
                        -PercentComplete $percentComplete `
                        -SecondsRemaining $remainingSeconds
                }
                else {
                    Write-Progress -Id $progressId -Activity "Waiting for task to complete" `
                        -Status $statusText `
                        -PercentComplete -1
                }

                # Wait before next poll
                Start-Sleep -Seconds $PollingIntervalSeconds
            }
        }
        finally {
            Write-Progress -Id $progressId -Activity "Waiting for task" -Completed -ErrorAction SilentlyContinue
        }
    }
}
