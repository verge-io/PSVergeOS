function Get-VergeAPIKey {
    <#
    .SYNOPSIS
        Retrieves API keys for users in VergeOS.

    .DESCRIPTION
        Get-VergeAPIKey retrieves API keys associated with user accounts.
        You can filter by user or retrieve all API keys.

    .PARAMETER User
        The username or user object to get API keys for.

    .PARAMETER UserKey
        The unique key (ID) of the user to get API keys for.

    .PARAMETER Key
        The unique key (ID) of a specific API key to retrieve.

    .PARAMETER Name
        Filter API keys by name. Supports wildcards (* and ?).

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeAPIKey

        Retrieves all API keys from the connected VergeOS system.

    .EXAMPLE
        Get-VergeAPIKey -User "admin"

        Retrieves all API keys for the admin user.

    .EXAMPLE
        Get-VergeUser -Name "apiuser" | Get-VergeAPIKey

        Retrieves API keys for a specific user via pipeline.

    .EXAMPLE
        Get-VergeAPIKey -Name "automation*"

        Retrieves API keys whose names start with "automation".

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.APIKey'

    .NOTES
        Use New-VergeAPIKey to create new API keys.
        Use Remove-VergeAPIKey to delete API keys.
    #>
    [CmdletBinding(DefaultParameterSetName = 'All')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ParameterSetName = 'ByUser', ValueFromPipeline)]
        [object]$User,

        [Parameter(ParameterSetName = 'ByUserKey')]
        [int]$UserKey,

        [Parameter(ParameterSetName = 'ByKey')]
        [Alias('Id', '$key')]
        [int]$Key,

        [Parameter(ParameterSetName = 'All')]
        [Parameter(ParameterSetName = 'ByUser')]
        [Parameter(ParameterSetName = 'ByUserKey')]
        [SupportsWildcards()]
        [string]$Name,

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

        # Filter by specific key
        if ($PSCmdlet.ParameterSetName -eq 'ByKey') {
            $filters.Add("`$key eq $Key")
        }
        else {
            # Filter by user
            $resolvedUserKey = $null

            if ($User) {
                if ($User -is [PSCustomObject] -and $User.PSObject.TypeNames -contains 'Verge.User') {
                    $resolvedUserKey = $User.Key
                }
                elseif ($User -is [int]) {
                    $resolvedUserKey = $User
                }
                elseif ($User -is [string]) {
                    $existingUser = Get-VergeUser -Name $User -Server $Server -ErrorAction SilentlyContinue
                    if ($existingUser) {
                        $resolvedUserKey = $existingUser.Key
                    }
                    else {
                        Write-Error -Message "User not found: $User" -ErrorId 'UserNotFound' -Category ObjectNotFound
                        return
                    }
                }
            }
            elseif ($UserKey) {
                $resolvedUserKey = $UserKey
            }

            if ($resolvedUserKey) {
                $filters.Add("user eq $resolvedUserKey")
            }

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
        }

        # Apply filters
        if ($filters.Count -gt 0) {
            $queryParams['filter'] = $filters -join ' and '
        }

        # Select fields
        $queryParams['fields'] = @(
            '$key'
            'user'
            'user#name as user_name'
            'name'
            'description'
            'created'
            'expires'
            'lastlogin_stamp'
            'lastlogin_ip'
            'ip_allow_list'
            'ip_deny_list'
        ) -join ','

        try {
            Write-Verbose "Querying API keys from $($Server.Server)"
            $response = Invoke-VergeAPI -Method GET -Endpoint 'user_api_keys' -Query $queryParams -Connection $Server

            # Handle both single object and array responses
            $apiKeys = if ($response -is [array]) { $response } else { @($response) }

            foreach ($apiKey in $apiKeys) {
                # Skip null entries
                if (-not $apiKey -or -not $apiKey.name) {
                    continue
                }

                # Convert timestamps
                $createdDate = if ($apiKey.created -and $apiKey.created -gt 0) {
                    [DateTimeOffset]::FromUnixTimeSeconds($apiKey.created).LocalDateTime
                } else { $null }

                $expiresDate = if ($apiKey.expires -and $apiKey.expires -gt 0) {
                    [DateTimeOffset]::FromUnixTimeSeconds($apiKey.expires).LocalDateTime
                } else { $null }

                $lastLoginDate = if ($apiKey.lastlogin_stamp -and $apiKey.lastlogin_stamp -gt 0) {
                    [DateTimeOffset]::FromUnixTimeSeconds($apiKey.lastlogin_stamp).LocalDateTime
                } else { $null }

                # Parse IP lists
                $allowList = if ($apiKey.ip_allow_list) {
                    $apiKey.ip_allow_list -split ',' | Where-Object { $_ }
                } else { @() }

                $denyList = if ($apiKey.ip_deny_list) {
                    $apiKey.ip_deny_list -split ',' | Where-Object { $_ }
                } else { @() }

                # Create output object
                $output = [PSCustomObject]@{
                    PSTypeName      = 'Verge.APIKey'
                    Key             = [int]$apiKey.'$key'
                    Name            = $apiKey.name
                    Description     = $apiKey.description
                    UserKey         = $apiKey.user
                    UserName        = $apiKey.user_name
                    Created         = $createdDate
                    Expires         = $expiresDate
                    IsExpired       = ($expiresDate -and $expiresDate -lt [datetime]::Now)
                    LastLogin       = $lastLoginDate
                    LastLoginIP     = $apiKey.lastlogin_ip
                    IPAllowList     = $allowList
                    IPDenyList      = $denyList
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
