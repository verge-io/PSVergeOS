function Get-VergeAlarm {
    <#
    .SYNOPSIS
        Retrieves alarms from VergeOS.

    .DESCRIPTION
        Get-VergeAlarm retrieves active alarms from a VergeOS system.
        Alarms indicate conditions requiring attention such as errors,
        warnings, or critical issues with VMs, networks, nodes, or the system.

    .PARAMETER Key
        The unique key (ID) of the alarm to retrieve.

    .PARAMETER Level
        Filter alarms by severity level: Critical, Error, Warning, Message, Audit.

    .PARAMETER OwnerType
        Filter alarms by owner type: VM, Network, Node, Tenant, User, System.

    .PARAMETER Active
        Only return active (non-snoozed) alarms. This is the default.

    .PARAMETER IncludeSnoozed
        Include snoozed alarms in the results.

    .PARAMETER History
        Return alarm history instead of current alarms.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeAlarm

        Retrieves all active alarms from the connected VergeOS system.

    .EXAMPLE
        Get-VergeAlarm -Level Critical

        Retrieves only critical alarms.

    .EXAMPLE
        Get-VergeAlarm -Level Error, Critical

        Retrieves error and critical alarms.

    .EXAMPLE
        Get-VergeAlarm -OwnerType VM

        Retrieves alarms related to virtual machines.

    .EXAMPLE
        Get-VergeAlarm -IncludeSnoozed

        Retrieves all alarms including snoozed ones.

    .EXAMPLE
        Get-VergeAlarm -History

        Retrieves alarm history (resolved alarms).

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.Alarm' or 'Verge.AlarmHistory'

    .NOTES
        Use Set-VergeAlarm to snooze or acknowledge alarms.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Active')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByKey', ValueFromPipelineByPropertyName)]
        [Alias('Id', '$key')]
        [int]$Key,

        [Parameter(ParameterSetName = 'Active')]
        [Parameter(ParameterSetName = 'All')]
        [ValidateSet('Critical', 'Error', 'Warning', 'Message', 'Audit', 'Summary', 'Debug')]
        [string[]]$Level,

        [Parameter(ParameterSetName = 'Active')]
        [Parameter(ParameterSetName = 'All')]
        [ValidateSet('VM', 'Network', 'Node', 'Tenant', 'User', 'System', 'CloudSnapshot')]
        [string]$OwnerType,

        [Parameter(ParameterSetName = 'Active')]
        [switch]$Active,

        [Parameter(ParameterSetName = 'All')]
        [switch]$IncludeSnoozed,

        [Parameter(ParameterSetName = 'History')]
        [switch]$History,

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

        # Map owner types to API values
        $ownerTypeMap = @{
            'VM'            = 'vms'
            'Network'       = 'vnets'
            'Node'          = 'nodes'
            'Tenant'        = 'tenant_nodes'
            'User'          = 'users'
            'System'        = 'system'
            'CloudSnapshot' = 'cloud_snapshots'
        }
    }

    process {
        # Handle alarm history
        if ($History) {
            $queryParams = @{}
            $queryParams['fields'] = @(
                '$key'
                'alarm_raised'
                'alarm_lowered'
                'archived_by'
                'owner'
                'alarm_type'
                'level'
                'status'
                'alarm_id'
            ) -join ','

            $queryParams['sort'] = '-alarm_lowered'

            try {
                Write-Verbose "Querying alarm history from $($Server.Server)"
                $response = Invoke-VergeAPI -Method GET -Endpoint 'alarm_history' -Query $queryParams -Connection $Server

                $alarms = if ($response -is [array]) { $response } else { @($response) }

                foreach ($alarm in $alarms) {
                    if (-not $alarm -or $null -eq $alarm.'$key') {
                        continue
                    }

                    $levelDisplay = switch ($alarm.level) {
                        'critical' { 'Critical' }
                        'error'    { 'Error' }
                        'warning'  { 'Warning' }
                        'message'  { 'Message' }
                        'audit'    { 'Audit' }
                        'summary'  { 'Summary' }
                        'debug'    { 'Debug' }
                        default    { $alarm.level }
                    }

                    $output = [PSCustomObject]@{
                        PSTypeName   = 'Verge.AlarmHistory'
                        Key          = [int]$alarm.'$key'
                        Level        = $levelDisplay
                        Status       = $alarm.status
                        AlarmType    = $alarm.alarm_type
                        AlarmId      = $alarm.alarm_id
                        Owner        = $alarm.owner
                        ArchivedBy   = $alarm.archived_by
                        RaisedAt     = if ($alarm.alarm_raised) { [DateTimeOffset]::FromUnixTimeSeconds($alarm.alarm_raised).LocalDateTime } else { $null }
                        LoweredAt    = if ($alarm.alarm_lowered) { [DateTimeOffset]::FromUnixTimeSeconds($alarm.alarm_lowered).LocalDateTime } else { $null }
                    }

                    $output | Add-Member -MemberType NoteProperty -Name '_Connection' -Value $Server -Force
                    Write-Output $output
                }
            }
            catch {
                $PSCmdlet.ThrowTerminatingError($_)
            }
            return
        }

        # Build query parameters for current alarms
        $queryParams = @{}
        $filters = [System.Collections.Generic.List[string]]::new()

        # Filter by key
        if ($PSCmdlet.ParameterSetName -eq 'ByKey') {
            $filters.Add("`$key eq $Key")
        }
        else {
            # Filter by level
            if ($Level -and $Level.Count -gt 0) {
                $levelFilters = $Level | ForEach-Object { "level eq '$($_.ToLower())'" }
                if ($levelFilters.Count -eq 1) {
                    $filters.Add($levelFilters[0])
                }
                else {
                    $filters.Add("($($levelFilters -join ' or '))")
                }
            }

            # Filter by owner type
            if ($OwnerType) {
                $apiOwnerType = $ownerTypeMap[$OwnerType]
                $filters.Add("owner_type eq '$apiOwnerType'")
            }

            # Active (non-snoozed) filter - default behavior unless IncludeSnoozed
            if (-not $IncludeSnoozed) {
                # Show alarms where snooze is 0 or snooze time has passed
                $filters.Add("(snooze eq 0 or snooze le {`$now})")
            }
        }

        # Apply filters
        if ($filters.Count -gt 0) {
            $queryParams['filter'] = $filters -join ' and '
        }

        # Request fields using the active view
        $queryParams['fields'] = @(
            '$key'
            'owner'
            'owner#name as owner_name'
            'owner_type'
            'sub_owner'
            'alarm_type'
            'alarm_type#name as alarm_type_name'
            'alarm_type#description as alarm_type_description'
            'level'
            'status'
            'alarm_id'
            'resolvable'
            'resolve_text'
            'created'
            'modified'
            'snooze'
            'snoozed_by'
        ) -join ','

        $queryParams['sort'] = '-created'

        try {
            Write-Verbose "Querying alarms from $($Server.Server)"
            $response = Invoke-VergeAPI -Method GET -Endpoint 'alarms' -Query $queryParams -Connection $Server

            $alarms = if ($response -is [array]) { $response } else { @($response) }

            foreach ($alarm in $alarms) {
                if (-not $alarm -or $null -eq $alarm.'$key') {
                    continue
                }

                # Map level to display name
                $levelDisplay = switch ($alarm.level) {
                    'critical' { 'Critical' }
                    'error'    { 'Error' }
                    'warning'  { 'Warning' }
                    'message'  { 'Message' }
                    'audit'    { 'Audit' }
                    'summary'  { 'Summary' }
                    'debug'    { 'Debug' }
                    default    { $alarm.level }
                }

                # Map owner type to friendly name
                $ownerTypeDisplay = switch ($alarm.owner_type) {
                    'vms'             { 'VM' }
                    'vnets'           { 'Network' }
                    'nodes'           { 'Node' }
                    'tenant_nodes'    { 'Tenant' }
                    'users'           { 'User' }
                    'system'          { 'System' }
                    'cloud_snapshots' { 'CloudSnapshot' }
                    default           { $alarm.owner_type }
                }

                # Determine if alarm is snoozed
                $isSnoozed = $alarm.snooze -and $alarm.snooze -gt 0 -and $alarm.snooze -gt [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

                $output = [PSCustomObject]@{
                    PSTypeName       = 'Verge.Alarm'
                    Key              = [int]$alarm.'$key'
                    Level            = $levelDisplay
                    Status           = $alarm.status
                    AlarmType        = $alarm.alarm_type_name
                    AlarmTypeKey     = $alarm.alarm_type
                    Description      = $alarm.alarm_type_description
                    AlarmId          = $alarm.alarm_id
                    Owner            = $alarm.owner_name
                    OwnerKey         = $alarm.owner
                    OwnerType        = $ownerTypeDisplay
                    SubOwner         = $alarm.sub_owner
                    Resolvable       = [bool]$alarm.resolvable
                    ResolveText      = $alarm.resolve_text
                    IsSnoozed        = $isSnoozed
                    SnoozedBy        = $alarm.snoozed_by
                    SnoozeUntil      = if ($alarm.snooze -and $alarm.snooze -gt 0) { [DateTimeOffset]::FromUnixTimeSeconds($alarm.snooze).LocalDateTime } else { $null }
                    Created          = if ($alarm.created) { [DateTimeOffset]::FromUnixTimeSeconds($alarm.created).LocalDateTime } else { $null }
                    Modified         = if ($alarm.modified) { [DateTimeOffset]::FromUnixTimeSeconds($alarm.modified).LocalDateTime } else { $null }
                }

                $output | Add-Member -MemberType NoteProperty -Name '_Connection' -Value $Server -Force
                Write-Output $output
            }
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}
