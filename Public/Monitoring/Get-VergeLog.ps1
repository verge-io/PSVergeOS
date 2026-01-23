function Get-VergeLog {
    <#
    .SYNOPSIS
        Retrieves system logs from VergeOS.

    .DESCRIPTION
        Get-VergeLog retrieves log entries from a VergeOS system. Logs include
        audit events, messages, warnings, errors, and critical events from
        various system components.

    .PARAMETER Level
        Filter logs by level: Critical, Error, Warning, Message, Audit, Summary, Debug.
        Accepts multiple values.

    .PARAMETER ObjectType
        Filter logs by object type such as VM, Network, Tenant, User, System, etc.

    .PARAMETER User
        Filter logs by the user who performed the action.

    .PARAMETER Text
        Filter logs containing this text (case-insensitive search).

    .PARAMETER Since
        Return logs since this date/time.

    .PARAMETER Before
        Return logs before this date/time.

    .PARAMETER Limit
        Maximum number of log entries to return. Default is 100.

    .PARAMETER ErrorsOnly
        Shortcut to filter for Error and Critical level logs only.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeLog

        Retrieves the most recent 100 log entries.

    .EXAMPLE
        Get-VergeLog -Level Error, Critical

        Retrieves error and critical log entries.

    .EXAMPLE
        Get-VergeLog -ErrorsOnly

        Shortcut to retrieve only error and critical logs.

    .EXAMPLE
        Get-VergeLog -ObjectType VM -Limit 50

        Retrieves the last 50 VM-related log entries.

    .EXAMPLE
        Get-VergeLog -Since (Get-Date).AddHours(-1)

        Retrieves logs from the last hour.

    .EXAMPLE
        Get-VergeLog -User "admin" -Text "powered on"

        Retrieves logs for actions by admin user containing "powered on".

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.Log'

    .NOTES
        Logs are retained for approximately 31 days by default.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateSet('Critical', 'Error', 'Warning', 'Message', 'Audit', 'Summary', 'Debug')]
        [string[]]$Level,

        [Parameter()]
        [ValidateSet(
            'VM', 'Network', 'Tenant', 'User', 'System', 'Node', 'Cluster',
            'File', 'Group', 'Permission', 'SMTP', 'Task', 'Site',
            'SystemSnapshot', 'CatalogRepository', 'OIDCApplication',
            'ServiceContainer', 'NASService', 'VMImport', 'VMwareBackup',
            'SnapshotProfile', 'ImportExport', 'Update', 'Other'
        )]
        [string]$ObjectType,

        [Parameter()]
        [string]$User,

        [Parameter()]
        [string]$Text,

        [Parameter()]
        [datetime]$Since,

        [Parameter()]
        [datetime]$Before,

        [Parameter()]
        [ValidateRange(1, 10000)]
        [int]$Limit = 100,

        [Parameter()]
        [switch]$ErrorsOnly,

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

        # Map object types to API values
        $objectTypeMap = @{
            'VM'                = 'vm'
            'Network'           = 'vnet'
            'Tenant'            = 'tenant'
            'User'              = 'user'
            'System'            = 'system'
            'Node'              = 'node'
            'Cluster'           = 'cluster'
            'File'              = 'file'
            'Group'             = 'group'
            'Permission'        = 'permission'
            'SMTP'              = 'smtp'
            'Task'              = 'task'
            'Site'              = 'site'
            'SystemSnapshot'    = 'cloud_snapshots'
            'CatalogRepository' = 'catalog_repository'
            'OIDCApplication'   = 'oidc_application'
            'ServiceContainer'  = 'service_container'
            'NASService'        = 'vm_service'
            'VMImport'          = 'vm_import'
            'VMwareBackup'      = 'vmware_container'
            'SnapshotProfile'   = 'snapshot_profile'
            'ImportExport'      = 'import_export'
            'Update'            = 'updates'
            'Other'             = 'other'
        }

        # Reverse map for display
        $objectTypeDisplayMap = @{
            'vm'                  = 'VM'
            'vnet'                = 'Network'
            'tenant'              = 'Tenant'
            'user'                = 'User'
            'system'              = 'System'
            'node'                = 'Node'
            'cluster'             = 'Cluster'
            'file'                = 'File'
            'group'               = 'Group'
            'permission'          = 'Permission'
            'smtp'                = 'SMTP'
            'task'                = 'Task'
            'site'                = 'Site'
            'cloud_snapshots'     = 'SystemSnapshot'
            'catalog_repository'  = 'CatalogRepository'
            'oidc_application'    = 'OIDCApplication'
            'service_container'   = 'ServiceContainer'
            'vm_service'          = 'NASService'
            'vm_import'           = 'VMImport'
            'vmware_container'    = 'VMwareBackup'
            'snapshot_profile'    = 'SnapshotProfile'
            'import_export'       = 'ImportExport'
            'updates'             = 'Update'
            'other'               = 'Other'
        }
    }

    process {
        # Build query parameters
        $queryParams = @{}
        $filters = [System.Collections.Generic.List[string]]::new()

        # Handle ErrorsOnly shortcut
        if ($ErrorsOnly) {
            $Level = @('Error', 'Critical')
        }

        # Filter by level
        if ($Level -and $Level.Count -gt 0) {
            # Force array output to avoid string indexing issues
            $levelFilters = @($Level | ForEach-Object { "level eq '$($_.ToLower())'" })
            if ($levelFilters.Count -eq 1) {
                $filters.Add($levelFilters[0])
            }
            else {
                $filters.Add("($($levelFilters -join ' or '))")
            }
        }

        # Filter by object type
        if ($ObjectType) {
            $apiObjectType = $objectTypeMap[$ObjectType]
            $filters.Add("object_type eq '$apiObjectType'")
        }

        # Filter by user
        if ($User) {
            $filters.Add("user ct '$User'")
        }

        # Filter by text
        if ($Text) {
            $filters.Add("text ct '$Text'")
        }

        # Filter by timestamp (logs use microseconds)
        if ($Since) {
            $sinceUs = [DateTimeOffset]::new($Since).ToUnixTimeMilliseconds() * 1000
            $filters.Add("timestamp ge $sinceUs")
        }

        if ($Before) {
            $beforeUs = [DateTimeOffset]::new($Before).ToUnixTimeMilliseconds() * 1000
            $filters.Add("timestamp lt $beforeUs")
        }

        # Apply filters
        if ($filters.Count -gt 0) {
            $queryParams['filter'] = $filters -join ' and '
        }

        # Request fields
        $queryParams['fields'] = @(
            '$key'
            'level'
            'text'
            'timestamp'
            'user'
            'object_type'
            'object_name'
        ) -join ','

        $queryParams['sort'] = '-timestamp'
        $queryParams['limit'] = $Limit

        try {
            Write-Verbose "Querying logs from $($Server.Server)"
            $response = Invoke-VergeAPI -Method GET -Endpoint 'logs' -Query $queryParams -Connection $Server

            $logs = if ($response -is [array]) { $response } else { @($response) }

            foreach ($log in $logs) {
                if (-not $log -or $null -eq $log.'$key') {
                    continue
                }

                # Map level to display name
                $levelDisplay = switch ($log.level) {
                    'critical' { 'Critical' }
                    'error'    { 'Error' }
                    'warning'  { 'Warning' }
                    'message'  { 'Message' }
                    'audit'    { 'Audit' }
                    'summary'  { 'Summary' }
                    'debug'    { 'Debug' }
                    default    { $log.level }
                }

                # Map object type to display name
                $objectTypeDisplay = if ($objectTypeDisplayMap.ContainsKey($log.object_type)) {
                    $objectTypeDisplayMap[$log.object_type]
                }
                else {
                    $log.object_type
                }

                # Convert timestamp from microseconds
                $timestamp = if ($log.timestamp) {
                    [DateTimeOffset]::FromUnixTimeMilliseconds($log.timestamp / 1000).LocalDateTime
                }
                else {
                    $null
                }

                $output = [PSCustomObject]@{
                    PSTypeName = 'Verge.Log'
                    Key        = [long]$log.'$key'
                    Level      = $levelDisplay
                    Text       = $log.text
                    Timestamp  = $timestamp
                    User       = $log.user
                    ObjectType = $objectTypeDisplay
                    ObjectName = $log.object_name
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
