function Get-VergeUser {
    <#
    .SYNOPSIS
        Retrieves users from VergeOS.

    .DESCRIPTION
        Get-VergeUser retrieves one or more users from a VergeOS system.
        You can filter users by name, type, or enabled status. Supports wildcards for
        name filtering.

    .PARAMETER Name
        The username to retrieve. Supports wildcards (* and ?).
        If not specified, all users are returned.

    .PARAMETER Key
        The unique key (ID) of the user to retrieve.

    .PARAMETER Type
        Filter users by type: Normal, API, or VDI.

    .PARAMETER Enabled
        Filter users by enabled status. Use $true or $false.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeUser

        Retrieves all users from the connected VergeOS system.

    .EXAMPLE
        Get-VergeUser -Name "admin"

        Retrieves the admin user.

    .EXAMPLE
        Get-VergeUser -Name "test*"

        Retrieves all users whose names start with "test".

    .EXAMPLE
        Get-VergeUser -Type API

        Retrieves all API users.

    .EXAMPLE
        Get-VergeUser -Enabled $false

        Retrieves all disabled users.

    .EXAMPLE
        Get-VergeUser | Where-Object { $_.TwoFactorEnabled }

        Retrieves all users with 2FA enabled.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.User'

    .NOTES
        Use New-VergeUser to create users.
        Use Enable-VergeUser and Disable-VergeUser to manage user status.
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
        [ValidateSet('Normal', 'API', 'VDI')]
        [string]$Type,

        [Parameter(ParameterSetName = 'Filter')]
        [bool]$Enabled,

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

        # Exclude system user types by default
        $filters.Add("type ne 'site_sync'")
        $filters.Add("type ne 'site_user'")

        # Filter by key
        if ($PSCmdlet.ParameterSetName -eq 'ByKey') {
            $filters.Add("`$key eq $Key")
        }
        else {
            # Filter by name (with wildcard support)
            if ($Name) {
                if ($Name -match '[\*\?]') {
                    # Wildcard - use 'ct' (contains) for partial match
                    $searchTerm = $Name -replace '[\*\?]', ''
                    if ($searchTerm) {
                        $filters.Add("name ct '$searchTerm'")
                    }
                }
                else {
                    # Exact match
                    $filters.Add("name eq '$Name'")
                }
            }

            # Filter by type
            if ($Type) {
                $typeMap = @{
                    'Normal' = 'normal'
                    'API'    = 'api'
                    'VDI'    = 'vdi'
                }
                $apiType = $typeMap[$Type]
                $filters.Add("type eq '$apiType'")
            }

            # Filter by enabled status
            if ($PSBoundParameters.ContainsKey('Enabled')) {
                $enabledValue = if ($Enabled) { 'true' } else { 'false' }
                $filters.Add("enabled eq $enabledValue")
            }
        }

        # Apply filters
        if ($filters.Count -gt 0) {
            $queryParams['filter'] = $filters -join ' and '
        }

        # Select fields for comprehensive user data
        $queryParams['fields'] = @(
            '$key'
            'name'
            'displayname'
            'email'
            'type'
            'enabled'
            'created'
            'last_login'
            'change_password'
            'physical_access'
            'two_factor_authentication'
            'two_factor_type'
            'two_factor_setup_next_login'
            'account_locked'
            'failed_attempts'
            'auth_source'
            'auth_source#name as auth_source_name'
            'remote_name'
            'identity'
            'creator'
        ) -join ','

        try {
            Write-Verbose "Querying users from $($Server.Server)"
            $response = Invoke-VergeAPI -Method GET -Endpoint 'users' -Query $queryParams -Connection $Server

            # Handle both single object and array responses
            $users = if ($response -is [array]) { $response } else { @($response) }

            foreach ($user in $users) {
                # Skip null entries
                if (-not $user -or -not $user.name) {
                    continue
                }

                # Map type to user-friendly display
                $typeDisplay = switch ($user.type) {
                    'normal' { 'Normal' }
                    'api' { 'API' }
                    'vdi' { 'VDI' }
                    'site_sync' { 'Site Sync' }
                    'site_user' { 'Site User' }
                    default { $user.type }
                }

                # Map 2FA type to user-friendly display
                $twoFactorTypeDisplay = switch ($user.two_factor_type) {
                    'email' { 'Email' }
                    'authenticator' { 'Authenticator' }
                    default { $user.two_factor_type }
                }

                # Convert timestamps
                $createdDate = if ($user.created -and $user.created -gt 0) {
                    [DateTimeOffset]::FromUnixTimeSeconds($user.created).LocalDateTime
                } else { $null }

                $lastLoginDate = if ($user.last_login -and $user.last_login -gt 0) {
                    [DateTimeOffset]::FromUnixTimeSeconds($user.last_login).LocalDateTime
                } else { $null }

                $accountLockedDate = if ($user.account_locked -and $user.account_locked -gt 0) {
                    [DateTimeOffset]::FromUnixTimeSeconds($user.account_locked).LocalDateTime
                } else { $null }

                # Create output object
                $output = [PSCustomObject]@{
                    PSTypeName              = 'Verge.User'
                    Key                     = [int]$user.'$key'
                    Name                    = $user.name
                    DisplayName             = $user.displayname
                    Email                   = $user.email
                    Type                    = $typeDisplay
                    TypeRaw                 = $user.type
                    Enabled                 = [bool]$user.enabled
                    Created                 = $createdDate
                    LastLogin               = $lastLoginDate
                    RequirePasswordChange   = [bool]$user.change_password
                    PhysicalAccess          = [bool]$user.physical_access
                    TwoFactorEnabled        = [bool]$user.two_factor_authentication
                    TwoFactorType           = $twoFactorTypeDisplay
                    TwoFactorTypeRaw        = $user.two_factor_type
                    TwoFactorSetupRequired  = [bool]$user.two_factor_setup_next_login
                    AccountLocked           = $accountLockedDate
                    IsLocked                = ($user.account_locked -and $user.account_locked -gt 0)
                    FailedAttempts          = [int]$user.failed_attempts
                    AuthSource              = $user.auth_source_name
                    AuthSourceKey           = $user.auth_source
                    RemoteName              = $user.remote_name
                    Identity                = $user.identity
                    Creator                 = $user.creator
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
