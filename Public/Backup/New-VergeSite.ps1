function New-VergeSite {
    <#
    .SYNOPSIS
        Creates a new site connection in VergeOS.

    .DESCRIPTION
        New-VergeSite creates a connection to another VergeOS system for disaster recovery,
        replication, and remote management purposes. The site is authenticated using
        credentials from the remote system.

    .PARAMETER Name
        The name for the site connection.

    .PARAMETER URL
        The URL of the remote VergeOS system (e.g., https://dr-site.example.com).

    .PARAMETER Credential
        Credentials for authenticating to the remote VergeOS system.

    .PARAMETER Description
        Optional description for the site.

    .PARAMETER AllowInsecure
        Allow insecure SSL connections (for self-signed certificates).

    .PARAMETER ConfigCloudSnapshots
        Cloud snapshot sync configuration.
        Valid values: disabled, send, receive, both

    .PARAMETER ConfigStatistics
        Statistics sync configuration.
        Valid values: disabled, send, receive, both

    .PARAMETER ConfigManagement
        Machine management configuration.
        Valid values: disabled, manage, managed, both

    .PARAMETER ConfigRepairServer
        Repair server configuration.
        Valid values: disabled, send, receive, both

    .PARAMETER AutoCreateSyncs
        Automatically create sync configurations. Default is $true.

    .PARAMETER Domain
        Domain name for the site.

    .PARAMETER City
        City where the site is located.

    .PARAMETER Country
        Country code where the site is located (e.g., US, GB, DE).

    .PARAMETER Timezone
        Timezone for the site (e.g., America/New_York).

    .PARAMETER RequestURL
        The URL that the remote system should use to connect back to this system.
        Required when the remote system needs to establish a bidirectional connection.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        $cred = Get-Credential
        New-VergeSite -Name "DR-Site" -URL "https://dr.example.com" -Credential $cred

        Creates a new site connection to a remote VergeOS system.

    .EXAMPLE
        $cred = Get-Credential
        New-VergeSite -Name "Offsite-DR" -URL "https://offsite.example.com" -Credential $cred -ConfigCloudSnapshots send -AllowInsecure

        Creates a site configured to send cloud snapshots, allowing self-signed certificates.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.Site'

    .NOTES
        The credentials provided are only used for initial authentication and establishing
        the site connection. They are not stored after the connection is established.

        After creating a site, use Get-VergeSiteSync to see the automatically created
        sync configurations, or use New-VergeSiteSync to create custom configurations.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory, Position = 1)]
        [ValidatePattern('^https?://')]
        [string]$URL,

        [Parameter(Mandatory)]
        [PSCredential]$Credential,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [switch]$AllowInsecure,

        [Parameter()]
        [ValidateSet('disabled', 'send', 'receive', 'both')]
        [string]$ConfigCloudSnapshots = 'disabled',

        [Parameter()]
        [ValidateSet('disabled', 'send', 'receive', 'both')]
        [string]$ConfigStatistics = 'disabled',

        [Parameter()]
        [ValidateSet('disabled', 'manage', 'managed', 'both')]
        [string]$ConfigManagement = 'disabled',

        [Parameter()]
        [ValidateSet('disabled', 'send', 'receive', 'both')]
        [string]$ConfigRepairServer = 'disabled',

        [Parameter()]
        [bool]$AutoCreateSyncs = $true,

        [Parameter()]
        [string]$Domain,

        [Parameter()]
        [string]$City,

        [Parameter()]
        [string]$Country,

        [Parameter()]
        [string]$Timezone,

        [Parameter()]
        [ValidatePattern('^https?://')]
        [string]$RequestURL,

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
        if ($PSCmdlet.ShouldProcess("Site '$Name' at $URL", 'Create')) {
            # Build request body
            $body = @{
                name = $Name
                url = $URL
                auth_user = $Credential.UserName
                auth_password = $Credential.GetNetworkCredential().Password
                enabled = $true
                allow_insecure = [bool]$AllowInsecure
                config_cloud_snapshots = $ConfigCloudSnapshots
                config_statistics = $ConfigStatistics
                config_management = $ConfigManagement
                config_repair_server = $ConfigRepairServer
                automatically_create_syncs = $AutoCreateSyncs
            }

            if ($Description) {
                $body['description'] = $Description
            }
            if ($Domain) {
                $body['domain'] = $Domain
            }
            if ($City) {
                $body['city'] = $City
            }
            if ($Country) {
                $body['country'] = $Country
            }
            if ($Timezone) {
                $body['timezone'] = $Timezone
            }
            if ($RequestURL) {
                $body['request_url'] = $RequestURL
            }

            try {
                Write-Verbose "Creating site '$Name' connected to $URL"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'sites' -Body $body -Connection $Server

                if ($response -and $response.'$key') {
                    Write-Verbose "Site created with key $($response.'$key')"

                    # Retrieve the full site details
                    $newSite = Get-VergeSite -Key $response.'$key' -Server $Server
                    Write-Output $newSite
                }
                else {
                    Write-Warning "Site creation returned unexpected response"
                    Write-Output $response
                }
            }
            catch {
                Write-Error -Message "Failed to create site '$Name': $($_.Exception.Message)" -ErrorId 'CreateSiteFailed'
            }
        }
    }
}
