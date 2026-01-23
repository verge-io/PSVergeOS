function Get-VergeTask {
    <#
    .SYNOPSIS
        Retrieves tasks from VergeOS.

    .DESCRIPTION
        Get-VergeTask retrieves scheduled automation tasks from a VergeOS system.
        Tasks can be filtered by name, status (running/idle), or owner.

    .PARAMETER Name
        The name of the task to retrieve. Supports wildcards (* and ?).

    .PARAMETER Key
        The unique key (ID) of the task to retrieve.

    .PARAMETER Status
        Filter tasks by status: Running or Idle.

    .PARAMETER Running
        Shortcut to filter for only running tasks.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeTask

        Retrieves all tasks from the connected VergeOS system.

    .EXAMPLE
        Get-VergeTask -Running

        Retrieves all currently running tasks.

    .EXAMPLE
        Get-VergeTask -Name "Daily*"

        Retrieves tasks whose names start with "Daily".

    .EXAMPLE
        Get-VergeTask -Status Idle

        Retrieves all idle tasks.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.Task'

    .NOTES
        Use Wait-VergeTask to wait for task completion.
        Use Stop-VergeTask to cancel a running task.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Filter')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ParameterSetName = 'Filter')]
        [SupportsWildcards()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey', ValueFromPipelineByPropertyName)]
        [Alias('Id', '$key')]
        [int]$Key,

        [Parameter(ParameterSetName = 'Filter')]
        [ValidateSet('Running', 'Idle')]
        [string]$Status,

        [Parameter(ParameterSetName = 'Filter')]
        [switch]$Running,

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

        # Build filter string
        $filters = [System.Collections.Generic.List[string]]::new()

        # Filter by key
        if ($PSCmdlet.ParameterSetName -eq 'ByKey') {
            $filters.Add("`$key eq $Key")
        }
        else {
            # Filter by name (with wildcard support)
            if ($Name) {
                if ($Name -match '[\*\?]') {
                    $searchTerm = $Name -replace '[\*\?]', ''
                    if ($searchTerm) {
                        $filters.Add("name ct '$searchTerm'")
                    }
                }
                else {
                    $filters.Add("name eq '$Name'")
                }
            }

            # Filter by status
            if ($Running) {
                $filters.Add("status eq 'running'")
            }
            elseif ($Status) {
                $statusValue = $Status.ToLower()
                $filters.Add("status eq '$statusValue'")
            }
        }

        # Apply filters
        if ($filters.Count -gt 0) {
            $queryParams['filter'] = $filters -join ' and '
        }

        # Request fields
        $queryParams['fields'] = @(
            '$key'
            'name'
            'description'
            'enabled'
            'status'
            'action'
            'action_display'
            'table'
            'owner'
            'owner#$display as owner_display'
            'creator'
            'creator#$display as creator_display'
            'last_run'
            'delete_after_run'
            'id'
        ) -join ','

        try {
            Write-Verbose "Querying tasks from $($Server.Server)"
            $response = Invoke-VergeAPI -Method GET -Endpoint 'tasks' -Query $queryParams -Connection $Server

            # Handle both single object and array responses
            $tasks = if ($response -is [array]) { $response } else { @($response) }

            foreach ($task in $tasks) {
                # Skip null entries
                if (-not $task -or -not $task.name) {
                    continue
                }

                # Map status to user-friendly display
                $statusDisplay = switch ($task.status) {
                    'running' { 'Running' }
                    'idle'    { 'Idle' }
                    default   { $task.status }
                }

                # Create output object
                $output = [PSCustomObject]@{
                    PSTypeName      = 'Verge.Task'
                    Key             = [int]$task.'$key'
                    Name            = $task.name
                    Description     = $task.description
                    Status          = $statusDisplay
                    IsRunning       = $task.status -eq 'running'
                    Enabled         = [bool]$task.enabled
                    Action          = $task.action
                    ActionDisplay   = $task.action_display
                    Table           = $task.table
                    Owner           = $task.owner_display
                    OwnerKey        = $task.owner
                    Creator         = $task.creator_display
                    CreatorKey      = $task.creator
                    LastRun         = $task.last_run
                    DeleteAfterRun  = [bool]$task.delete_after_run
                    TaskId          = $task.id
                }

                # Add hidden properties for pipeline support
                $output | Add-Member -MemberType NoteProperty -Name '_Connection' -Value $Server -Force

                Write-Output $output
            }
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}
