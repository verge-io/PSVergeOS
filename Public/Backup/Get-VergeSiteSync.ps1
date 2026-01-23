function Get-VergeSiteSync {
    <#
    .SYNOPSIS
        Retrieves outgoing site sync configurations from VergeOS.

    .DESCRIPTION
        Get-VergeSiteSync retrieves outgoing sync configurations for sites in VergeOS.
        These syncs are used for replicating cloud snapshots and data to remote sites
        for disaster recovery purposes.

    .PARAMETER Name
        Filter by sync name. Supports wildcards (* and ?).

    .PARAMETER Key
        Get a specific sync by its key (ID).

    .PARAMETER SiteKey
        Filter syncs by site key.

    .PARAMETER SiteName
        Filter syncs by site name.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeSiteSync

        Gets all outgoing site syncs.

    .EXAMPLE
        Get-VergeSiteSync -SiteName "DR-Site"

        Gets all outgoing syncs for the site named "DR-Site".

    .EXAMPLE
        Get-VergeSiteSync -Key 1

        Gets a specific sync by its key.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.SiteSync'

    .NOTES
        Outgoing syncs send data (cloud snapshots) from this system to a remote site.
        Use Get-VergeSiteSyncIncoming to see syncs coming into this system.

        Use Start-VergeSiteSync and Stop-VergeSiteSync to control sync operations.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ParameterSetName = 'List')]
        [SupportsWildcards()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(ParameterSetName = 'List')]
        [int]$SiteKey,

        [Parameter(ParameterSetName = 'List')]
        [string]$SiteName,

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
        # Resolve site key if site name provided
        if ($SiteName) {
            $site = Get-VergeSite -Name $SiteName -Server $Server
            if (-not $site) {
                Write-Error -Message "Site not found: $SiteName" -ErrorId 'SiteNotFound'
                return
            }
            $SiteKey = $site.Key
        }

        # Build query parameters
        $queryParams = @{}
        $queryParams['fields'] = @(
            '$key'
            'site'
            'name'
            'description'
            'enabled'
            'status'
            'status_info'
            'state'
            'url'
            'encryption'
            'compression'
            'netinteg'
            'threads'
            'file_threads'
            'sendthrottle'
            'destination_tier'
            'queue_retry_count'
            'queue_retry_interval_seconds'
            'queue_retry_interval_multiplier'
            'last_run'
            'remote_min_snapshots'
            'note'
        ) -join ','

        # Build filters
        $filters = @()

        # Handle specific key lookup
        if ($PSCmdlet.ParameterSetName -eq 'ByKey') {
            $filters += "`$key eq $Key"
        }
        else {
            if ($Name -and $Name -notmatch '[\*\?]') {
                # Exact name match
                $filters += "name eq '$Name'"
            }
            if ($SiteKey) {
                $filters += "site eq $SiteKey"
            }
        }

        if ($filters.Count -gt 0) {
            $queryParams['filter'] = $filters -join ' and '
        }

        $queryParams['sort'] = '+name'

        try {
            Write-Verbose "Querying outgoing site syncs from VergeOS"
            $response = Invoke-VergeAPI -Method GET -Endpoint 'site_syncs_outgoing' -Query $queryParams -Connection $Server

            # Handle both single object and array responses
            $syncs = if ($response -is [array]) { $response } elseif ($response) { @($response) } else { @() }

            foreach ($sync in $syncs) {
                if (-not $sync) {
                    continue
                }

                # Apply wildcard filter if specified
                if ($Name -and $Name -match '[\*\?]') {
                    if ($sync.name -notlike $Name) {
                        continue
                    }
                }

                # Get site name
                $syncSiteName = $null
                if ($sync.site) {
                    try {
                        $siteObj = Get-VergeSite -Key $sync.site -Server $Server
                        $syncSiteName = $siteObj.Name
                    } catch {
                        Write-Verbose "Could not retrieve site name for sync: $($_.Exception.Message)"
                    }
                }

                # Convert timestamps
                $lastRunDate = if ($sync.last_run -and $sync.last_run -gt 0) {
                    [DateTimeOffset]::FromUnixTimeSeconds($sync.last_run).LocalDateTime
                } else { $null }

                # Create output object
                $output = [PSCustomObject]@{
                    PSTypeName                    = 'Verge.SiteSync'
                    Key                           = [int]$sync.'$key'
                    SiteKey                       = $sync.site
                    SiteName                      = $syncSiteName
                    Name                          = $sync.name
                    Description                   = $sync.description
                    Enabled                       = [bool]$sync.enabled
                    Status                        = $sync.status
                    StatusInfo                    = $sync.status_info
                    State                         = $sync.state
                    URL                           = $sync.url
                    Encryption                    = [bool]$sync.encryption
                    Compression                   = [bool]$sync.compression
                    NetworkIntegrity              = [bool]$sync.netinteg
                    DataThreads                   = $sync.threads
                    FileThreads                   = $sync.file_threads
                    SendThrottle                  = $sync.sendthrottle
                    DestinationTier               = $sync.destination_tier
                    QueueRetryCount               = $sync.queue_retry_count
                    QueueRetryIntervalSeconds     = $sync.queue_retry_interval_seconds
                    QueueRetryIntervalMultiplier  = [bool]$sync.queue_retry_interval_multiplier
                    LastRun                       = $lastRunDate
                    RemoteMinSnapshots            = $sync.remote_min_snapshots
                    Note                          = $sync.note
                }

                # Add hidden property for pipeline support
                $output | Add-Member -MemberType NoteProperty -Name '_Connection' -Value $Server -Force

                Write-Output $output
            }
        }
        catch {
            Write-Error -Message "Failed to get site syncs: $($_.Exception.Message)" -ErrorId 'GetSiteSyncsFailed'
        }
    }
}
