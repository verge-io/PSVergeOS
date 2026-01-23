function Get-VergeSiteSyncIncoming {
    <#
    .SYNOPSIS
        Retrieves incoming site sync configurations from VergeOS.

    .DESCRIPTION
        Get-VergeSiteSyncIncoming retrieves incoming sync configurations for sites in VergeOS.
        These syncs receive cloud snapshots and data from remote sites for disaster recovery
        purposes.

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
        Get-VergeSiteSyncIncoming

        Gets all incoming site syncs.

    .EXAMPLE
        Get-VergeSiteSyncIncoming -SiteName "DR-Site"

        Gets all incoming syncs for the site named "DR-Site".

    .EXAMPLE
        Get-VergeSiteSyncIncoming -Key 1

        Gets a specific incoming sync by its key.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.SiteSyncIncoming'

    .NOTES
        Incoming syncs receive data (cloud snapshots) from a remote site to this system.
        Use Get-VergeSiteSync to see syncs going out from this system.

        The RegistrationCode is used by the remote site to establish the sync connection.
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
            'sync_id'
            'registration_code'
            'public_ip'
            'force_tier'
            'min_snapshots'
            'last_sync'
            'vsan_host'
            'vsan_port'
            'request_url'
            'system_created'
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
            Write-Verbose "Querying incoming site syncs from VergeOS"
            $response = Invoke-VergeAPI -Method GET -Endpoint 'site_syncs_incoming' -Query $queryParams -Connection $Server

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
                $lastSyncDate = if ($sync.last_sync -and $sync.last_sync -gt 0) {
                    [DateTimeOffset]::FromUnixTimeSeconds($sync.last_sync).LocalDateTime
                } else { $null }

                # Create output object
                $output = [PSCustomObject]@{
                    PSTypeName        = 'Verge.SiteSyncIncoming'
                    Key               = [int]$sync.'$key'
                    SiteKey           = $sync.site
                    SiteName          = $syncSiteName
                    Name              = $sync.name
                    Description       = $sync.description
                    Enabled           = [bool]$sync.enabled
                    Status            = $sync.status
                    StatusInfo        = $sync.status_info
                    State             = $sync.state
                    SyncId            = $sync.sync_id
                    RegistrationCode  = $sync.registration_code
                    PublicIP          = $sync.public_ip
                    ForceTier         = $sync.force_tier
                    MinSnapshots      = $sync.min_snapshots
                    LastSync          = $lastSyncDate
                    VSANHost          = $sync.vsan_host
                    VSANPort          = $sync.vsan_port
                    RequestURL        = $sync.request_url
                    SystemCreated     = [bool]$sync.system_created
                }

                # Add hidden property for pipeline support
                $output | Add-Member -MemberType NoteProperty -Name '_Connection' -Value $Server -Force

                Write-Output $output
            }
        }
        catch {
            Write-Error -Message "Failed to get incoming site syncs: $($_.Exception.Message)" -ErrorId 'GetIncomingSiteSyncsFailed'
        }
    }
}
