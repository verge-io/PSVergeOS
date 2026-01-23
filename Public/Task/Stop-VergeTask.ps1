function Stop-VergeTask {
    <#
    .SYNOPSIS
        Disables a VergeOS scheduled task.

    .DESCRIPTION
        Stop-VergeTask disables a scheduled task, preventing it from running in the future.
        If the task is currently running, it will complete but won't run again until re-enabled.

    .PARAMETER Task
        A task object from Get-VergeTask. Accepts pipeline input.

    .PARAMETER Key
        The unique key (ID) of the task to disable.

    .PARAMETER Name
        The name of the task to disable.

    .PARAMETER PassThru
        Return the task object after disabling. By default, returns nothing on success.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Stop-VergeTask -Name "Backup VM"

        Disables the task named "Backup VM".

    .EXAMPLE
        Get-VergeTask -Name "Daily*" | Stop-VergeTask

        Disables all tasks whose names start with "Daily".

    .EXAMPLE
        Stop-VergeTask -Key 5 -PassThru

        Disables task with key 5 and returns the updated task object.

    .OUTPUTS
        None by default. Verge.Task when -PassThru is specified.

    .NOTES
        To re-enable a task, use Enable-VergeTask or Set-VergeTask.
        Disabling a running task will allow it to complete but prevent future runs.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByTask')]
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
        # Get the task to disable based on parameter set
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

        # Check if already disabled
        if (-not $targetTask.Enabled) {
            Write-Warning "Task '$($targetTask.Name)' is already disabled."
            if ($PassThru) {
                Write-Output $targetTask
            }
            return
        }

        $taskKey = $targetTask.Key
        $taskName = $targetTask.Name

        # Warn if task is running
        if ($targetTask.IsRunning) {
            Write-Warning "Task '$taskName' is currently running. It will complete but will be disabled for future runs."
        }

        # Confirm action
        if ($PSCmdlet.ShouldProcess($taskName, 'Disable task')) {
            try {
                Write-Verbose "Disabling task '$taskName' (Key: $taskKey)"

                $body = @{
                    enabled = $false
                }

                $response = Invoke-VergeAPI -Method PUT -Endpoint "tasks/$taskKey" -Body $body -Connection $Server

                Write-Verbose "Task '$taskName' has been disabled"

                if ($PassThru) {
                    # Return refreshed task object
                    Get-VergeTask -Key $taskKey -Server $Server
                }
            }
            catch {
                Write-Error -Message "Failed to disable task '$taskName': $($_.Exception.Message)" -ErrorId 'TaskDisableFailed'
            }
        }
    }
}
