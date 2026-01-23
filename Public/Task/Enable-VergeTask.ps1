function Enable-VergeTask {
    <#
    .SYNOPSIS
        Enables a VergeOS scheduled task.

    .DESCRIPTION
        Enable-VergeTask enables a previously disabled scheduled task, allowing it to run
        according to its schedule or event triggers.

    .PARAMETER Task
        A task object from Get-VergeTask. Accepts pipeline input.

    .PARAMETER Key
        The unique key (ID) of the task to enable.

    .PARAMETER Name
        The name of the task to enable.

    .PARAMETER PassThru
        Return the task object after enabling. By default, returns nothing on success.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Enable-VergeTask -Name "Backup VM"

        Enables the task named "Backup VM".

    .EXAMPLE
        Get-VergeTask | Where-Object { -not $_.Enabled } | Enable-VergeTask

        Enables all disabled tasks.

    .EXAMPLE
        Enable-VergeTask -Key 5 -PassThru

        Enables task with key 5 and returns the updated task object.

    .OUTPUTS
        None by default. Verge.Task when -PassThru is specified.

    .NOTES
        Use Stop-VergeTask to disable a task.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low', DefaultParameterSetName = 'ByTask')]
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
        # Get the task to enable based on parameter set
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

        # Check if already enabled
        if ($targetTask.Enabled) {
            Write-Warning "Task '$($targetTask.Name)' is already enabled."
            if ($PassThru) {
                Write-Output $targetTask
            }
            return
        }

        $taskKey = $targetTask.Key
        $taskName = $targetTask.Name

        # Confirm action
        if ($PSCmdlet.ShouldProcess($taskName, 'Enable task')) {
            try {
                Write-Verbose "Enabling task '$taskName' (Key: $taskKey)"

                $body = @{
                    enabled = $true
                }

                $response = Invoke-VergeAPI -Method PUT -Endpoint "tasks/$taskKey" -Body $body -Connection $Server

                Write-Verbose "Task '$taskName' has been enabled"

                if ($PassThru) {
                    # Return refreshed task object
                    Get-VergeTask -Key $taskKey -Server $Server
                }
            }
            catch {
                Write-Error -Message "Failed to enable task '$taskName': $($_.Exception.Message)" -ErrorId 'TaskEnableFailed'
            }
        }
    }
}
