function Get-VergeNASUser {
    <#
    .SYNOPSIS
        Retrieves local users from a NAS service in VergeOS.

    .DESCRIPTION
        Get-VergeNASUser retrieves one or more local users from a NAS service.
        NAS local users are used for CIFS/SMB authentication when not using
        Active Directory integration.

    .PARAMETER NASService
        A NAS service object from Get-VergeNASService. Accepts pipeline input.

    .PARAMETER NASServiceName
        The name of the NAS service to get users from.

    .PARAMETER NASServiceKey
        The unique key (ID) of the NAS service.

    .PARAMETER Name
        The username to retrieve. Supports wildcards (* and ?).
        If not specified, all users are returned.

    .PARAMETER Key
        The unique key (ID) of the NAS user to retrieve.

    .PARAMETER Enabled
        Filter users by enabled status. Use $true for enabled users,
        $false for disabled users.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeNASUser -NASServiceName "NAS01"

        Lists all local users for the NAS service named "NAS01".

    .EXAMPLE
        Get-VergeNASService -Name "FileServer" | Get-VergeNASUser

        Lists all local users for the "FileServer" NAS service via pipeline.

    .EXAMPLE
        Get-VergeNASUser -NASServiceName "NAS01" -Name "admin"

        Gets a specific user by name from the NAS service.

    .EXAMPLE
        Get-VergeNASUser -NASServiceName "NAS01" -Enabled $true

        Gets all enabled users from the NAS service.

    .EXAMPLE
        Get-VergeNASService | Get-VergeNASUser -Name "backup*"

        Gets all users whose names start with "backup" across all NAS services.

    .OUTPUTS
        Verge.NASUser objects containing:
        - Key: The NAS user unique identifier
        - Name: Username
        - DisplayName: Display name
        - Enabled: Whether the account is enabled
        - NASServiceKey: Parent NAS service key
        - NASServiceName: Parent NAS service name
        - HomeShare: Home share name
        - HomeDrive: Home drive letter
        - Status: Account status (Enabled, Disabled, Error)
        - UserSID: Windows SID
        - UserID: Unix UID
        - Created: Account creation time

    .NOTES
        Use New-VergeNASUser to create local users.
        Use Set-VergeNASUser to modify user settings.
        Use Enable-VergeNASUser/Disable-VergeNASUser to change account status.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByNASName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObjectAndUserKey')]
        [PSTypeName('Verge.NASService')]
        [PSCustomObject]$NASService,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByNASName')]
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByNASNameAndUserKey')]
        [string]$NASServiceName,

        [Parameter(Mandatory, ParameterSetName = 'ByNASKey')]
        [Parameter(Mandatory, ParameterSetName = 'ByNASKeyAndUserKey')]
        [int]$NASServiceKey,

        [Parameter(Position = 1, ParameterSetName = 'ByNASName')]
        [Parameter(Position = 1, ParameterSetName = 'ByNASKey')]
        [Parameter(Position = 0, ParameterSetName = 'ByObject')]
        [SupportsWildcards()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByNASNameAndUserKey')]
        [Parameter(Mandatory, ParameterSetName = 'ByNASKeyAndUserKey')]
        [Parameter(Mandatory, ParameterSetName = 'ByObjectAndUserKey')]
        [Alias('Id', 'UserKey')]
        [string]$Key,

        [Parameter(ParameterSetName = 'ByNASName')]
        [Parameter(ParameterSetName = 'ByNASKey')]
        [Parameter(ParameterSetName = 'ByObject')]
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
        # Resolve NAS service based on parameter set
        $targetServices = switch -Wildcard ($PSCmdlet.ParameterSetName) {
            'ByNASName*' {
                Get-VergeNASService -Name $NASServiceName -Server $Server
            }
            'ByNASKey*' {
                Get-VergeNASService -Key $NASServiceKey -Server $Server
            }
            'ByObject*' {
                $NASService
            }
        }

        foreach ($service in $targetServices) {
            if (-not $service) {
                if ($PSCmdlet.ParameterSetName -like 'ByNASName*') {
                    Write-Error -Message "NAS service '$NASServiceName' not found." -ErrorId 'NASServiceNotFound'
                }
                continue
            }

            try {
                # Build query parameters
                $queryParams = @{}
                $filters = [System.Collections.Generic.List[string]]::new()

                # Always filter by service
                $filters.Add("service eq $($service.Key)")

                # Filter by user key if specified
                if ($Key) {
                    $filters.Add("`$key eq '$Key'")
                }
                # Filter by name with wildcard support
                elseif ($Name) {
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

                # Filter by enabled status
                if ($PSBoundParameters.ContainsKey('Enabled')) {
                    $enabledValue = if ($Enabled) { 'true' } else { 'false' }
                    $filters.Add("enabled eq $enabledValue")
                }

                # Apply filters
                if ($filters.Count -gt 0) {
                    $queryParams['filter'] = $filters -join ' and '
                }

                # Select fields with related information
                $queryParams['fields'] = @(
                    '$key'
                    'name'
                    'enabled'
                    'displayname'
                    'description'
                    'home_share'
                    'display(home_share) as home_share_display'
                    'home_drive'
                    'created'
                    'service'
                    'service#$display as service_name'
                    'status#status as status_value'
                    'status#status_info as status_info'
                    'status#user_sid as user_sid'
                    'status#group_sid as group_sid'
                    'status#user_id as user_id'
                    'status#group_id as group_id'
                ) -join ','

                Write-Verbose "Querying NAS users for service '$($service.Name)'"
                $response = Invoke-VergeAPI -Method GET -Endpoint 'vm_service_users' -Query $queryParams -Connection $Server

                # Handle response
                $users = if ($response -is [array]) { $response } else { @($response) }

                foreach ($user in $users) {
                    if (-not $user -or -not $user.'$key') {
                        continue
                    }

                    # Convert created timestamp
                    $created = $null
                    if ($user.created) {
                        $created = [DateTimeOffset]::FromUnixTimeSeconds($user.created).LocalDateTime
                    }

                    # Map status to display
                    $statusDisplay = switch ($user.status_value) {
                        'online'  { 'Enabled' }
                        'offline' { 'Disabled' }
                        'error'   { 'Error' }
                        default   { $user.status_value ?? 'Unknown' }
                    }

                    [PSCustomObject]@{
                        PSTypeName       = 'Verge.NASUser'
                        Key              = $user.'$key'
                        Name             = $user.name
                        DisplayName      = $user.displayname
                        Description      = $user.description
                        Enabled          = [bool]$user.enabled
                        NASServiceKey    = $user.service
                        NASServiceName   = $user.service_name ?? $service.Name
                        HomeShareKey     = $user.home_share
                        HomeShareName    = $user.home_share_display
                        HomeDrive        = $user.home_drive
                        Status           = $statusDisplay
                        StatusInfo       = $user.status_info
                        UserSID          = $user.user_sid
                        GroupSID         = $user.group_sid
                        UserID           = $user.user_id
                        GroupID          = $user.group_id
                        Created          = $created
                        _Connection      = $Server
                    }
                }
            }
            catch {
                Write-Error -Message "Failed to get NAS users for service '$($service.Name)': $($_.Exception.Message)" -ErrorId 'GetNASUsersFailed'
            }
        }
    }
}
