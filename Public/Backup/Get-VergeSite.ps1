function Get-VergeSite {
    <#
    .SYNOPSIS
        Retrieves site configurations from VergeOS.

    .DESCRIPTION
        Get-VergeSite retrieves remote site configurations from a VergeOS system.
        Sites represent connections to other VergeOS systems for disaster recovery,
        replication, and remote management.

    .PARAMETER Name
        Filter by site name. Supports wildcards (* and ?).

    .PARAMETER Key
        Get a specific site by its key (ID).

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeSite

        Gets all configured sites.

    .EXAMPLE
        Get-VergeSite -Name "DR-*"

        Gets sites with names starting with "DR-".

    .EXAMPLE
        Get-VergeSite -Key 5

        Gets a specific site by its key.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.Site'

    .NOTES
        Sites are used for DR replication and remote management between VergeOS systems.

        Use New-VergeSite to create a new site connection.
        Use Get-VergeSiteSync to see outgoing sync configurations.
        Use Get-VergeSiteSyncIncoming to see incoming sync configurations.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ParameterSetName = 'List')]
        [SupportsWildcards()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

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
        $queryParams['fields'] = @(
            '$key'
            'name'
            'description'
            'enabled'
            'url'
            'domain'
            'city'
            'country'
            'timezone'
            'latitude'
            'longitude'
            'status'
            'status_info'
            'authentication_status'
            'config_cloud_snapshots'
            'config_statistics'
            'config_management'
            'config_repair_server'
            'vsan_host'
            'vsan_port'
            'is_tenant'
            'incoming_syncs_enabled'
            'outgoing_syncs_enabled'
            'statistics_interval'
            'statistics_retention'
            'created'
            'modified'
            'creator'
        ) -join ','

        # Build filters
        $filters = @()

        # Handle specific key lookup
        if ($PSCmdlet.ParameterSetName -eq 'ByKey') {
            $filters += "`$key eq $Key"
        }
        elseif ($Name -and $Name -notmatch '[\*\?]') {
            # Exact name match
            $filters += "name eq '$Name'"
        }

        if ($filters.Count -gt 0) {
            $queryParams['filter'] = $filters -join ' and '
        }

        $queryParams['sort'] = '+name'

        try {
            Write-Verbose "Querying sites from VergeOS"
            $response = Invoke-VergeAPI -Method GET -Endpoint 'sites' -Query $queryParams -Connection $Server

            # Handle both single object and array responses
            $sites = if ($response -is [array]) { $response } elseif ($response) { @($response) } else { @() }

            foreach ($site in $sites) {
                if (-not $site -or -not $site.name) {
                    continue
                }

                # Apply wildcard filter if specified
                if ($Name -and $Name -match '[\*\?]') {
                    if ($site.name -notlike $Name) {
                        continue
                    }
                }

                # Convert timestamps
                $createdDate = if ($site.created) {
                    [DateTimeOffset]::FromUnixTimeSeconds($site.created).LocalDateTime
                } else { $null }

                $modifiedDate = if ($site.modified) {
                    [DateTimeOffset]::FromUnixTimeSeconds($site.modified).LocalDateTime
                } else { $null }

                # Create output object
                $output = [PSCustomObject]@{
                    PSTypeName             = 'Verge.Site'
                    Key                    = [int]$site.'$key'
                    Name                   = $site.name
                    Description            = $site.description
                    Enabled                = [bool]$site.enabled
                    URL                    = $site.url
                    Domain                 = $site.domain
                    City                   = $site.city
                    Country                = $site.country
                    Timezone               = $site.timezone
                    Latitude               = $site.latitude
                    Longitude              = $site.longitude
                    Status                 = $site.status
                    StatusInfo             = $site.status_info
                    AuthenticationStatus   = $site.authentication_status
                    ConfigCloudSnapshots   = $site.config_cloud_snapshots
                    ConfigStatistics       = $site.config_statistics
                    ConfigManagement       = $site.config_management
                    ConfigRepairServer     = $site.config_repair_server
                    VSANHost               = $site.vsan_host
                    VSANPort               = $site.vsan_port
                    IsTenant               = [bool]$site.is_tenant
                    IncomingSyncsEnabled   = [bool]$site.incoming_syncs_enabled
                    OutgoingSyncsEnabled   = [bool]$site.outgoing_syncs_enabled
                    StatisticsInterval     = $site.statistics_interval
                    StatisticsRetention    = $site.statistics_retention
                    Created                = $createdDate
                    Modified               = $modifiedDate
                    Creator                = $site.creator
                }

                # Add hidden property for pipeline support
                $output | Add-Member -MemberType NoteProperty -Name '_Connection' -Value $Server -Force

                Write-Output $output
            }
        }
        catch {
            Write-Error -Message "Failed to get sites: $($_.Exception.Message)" -ErrorId 'GetSitesFailed'
        }
    }
}
