function New-VergeAPIKey {
    <#
    .SYNOPSIS
        Creates a new API key for a user in VergeOS.

    .DESCRIPTION
        New-VergeAPIKey creates a new API key for a specified user.
        The API key secret is only displayed once at creation time.

    .PARAMETER User
        The username or user object to create the API key for.

    .PARAMETER UserKey
        The unique key (ID) of the user to create the API key for.

    .PARAMETER Name
        The name for the API key. Must be unique per user.

    .PARAMETER Description
        An optional description for the API key.

    .PARAMETER ExpiresIn
        The duration until the API key expires (e.g., "30d", "1y", "never").
        Supported units: d (days), w (weeks), m (months), y (years).
        Default is "never" (no expiration).

    .PARAMETER Expires
        A specific DateTime when the API key should expire.

    .PARAMETER IPAllowList
        Array of IP addresses or CIDR ranges that are allowed to use this key.

    .PARAMETER IPDenyList
        Array of IP addresses or CIDR ranges that are denied from using this key.

    .PARAMETER PassThru
        Return the created API key object (without the secret).

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeAPIKey -User "admin" -Name "automation-key"

        Creates a new API key for the admin user.

    .EXAMPLE
        New-VergeAPIKey -User "apiuser" -Name "ci-key" -ExpiresIn "90d" -Description "CI/CD automation"

        Creates an API key that expires in 90 days.

    .EXAMPLE
        Get-VergeUser -Name "apiuser" | New-VergeAPIKey -Name "restricted-key" -IPAllowList @("10.0.0.0/8")

        Creates an API key restricted to a specific IP range.

    .OUTPUTS
        PSCustomObject containing the API key and secret (secret only shown once)

    .NOTES
        IMPORTANT: The API key secret is only displayed at creation time.
        Store it securely as it cannot be retrieved later.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByUser')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByUser', ValueFromPipeline)]
        [object]$User,

        [Parameter(Mandatory, ParameterSetName = 'ByUserKey')]
        [int]$UserKey,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [ValidateLength(1, 128)]
        [string]$Name,

        [Parameter()]
        [ValidateLength(0, 2048)]
        [string]$Description,

        [Parameter()]
        [ValidatePattern('^(never|\d+[dwmy])$', ErrorMessage = "ExpiresIn must be 'never' or a duration like '30d', '1w', '3m', '1y'")]
        [string]$ExpiresIn = 'never',

        [Parameter()]
        [datetime]$Expires,

        [Parameter()]
        [string[]]$IPAllowList,

        [Parameter()]
        [string[]]$IPDenyList,

        [Parameter()]
        [switch]$PassThru,

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
        # Resolve user key
        $resolvedUserKey = $null
        $userName = $null

        if ($User) {
            if ($User -is [PSCustomObject] -and $User.PSObject.TypeNames -contains 'Verge.User') {
                $resolvedUserKey = $User.Key
                $userName = $User.Name
            }
            elseif ($User -is [int]) {
                $resolvedUserKey = $User
                $existingUser = Get-VergeUser -Key $User -Server $Server -ErrorAction SilentlyContinue
                $userName = if ($existingUser) { $existingUser.Name } else { "User $User" }
            }
            elseif ($User -is [string]) {
                $existingUser = Get-VergeUser -Name $User -Server $Server -ErrorAction SilentlyContinue
                if (-not $existingUser) {
                    Write-Error -Message "User not found: $User" -ErrorId 'UserNotFound' -Category ObjectNotFound
                    return
                }
                $resolvedUserKey = $existingUser.Key
                $userName = $User
            }
        }
        elseif ($UserKey) {
            $resolvedUserKey = $UserKey
            $existingUser = Get-VergeUser -Key $UserKey -Server $Server -ErrorAction SilentlyContinue
            $userName = if ($existingUser) { $existingUser.Name } else { "User $UserKey" }
        }

        if (-not $resolvedUserKey) {
            Write-Error -Message "Could not resolve user" -ErrorId 'UserNotFound' -Category ObjectNotFound
            return
        }

        # Build request body
        $body = @{
            user = $resolvedUserKey
            name = $Name
        }

        if ($Description) {
            $body['description'] = $Description
        }

        # Handle expiration
        if ($PSBoundParameters.ContainsKey('Expires')) {
            $body['expires'] = [int][DateTimeOffset]::new($Expires).ToUnixTimeSeconds()
            $body['expires_type'] = 'date'
        }
        elseif ($ExpiresIn -eq 'never') {
            $body['expires_type'] = 'never'
        }
        else {
            # Parse duration string
            $match = [regex]::Match($ExpiresIn, '^(\d+)([dwmy])$')
            if ($match.Success) {
                $value = [int]$match.Groups[1].Value
                $unit = $match.Groups[2].Value
                $expirationDate = switch ($unit) {
                    'd' { [datetime]::Now.AddDays($value) }
                    'w' { [datetime]::Now.AddDays($value * 7) }
                    'm' { [datetime]::Now.AddMonths($value) }
                    'y' { [datetime]::Now.AddYears($value) }
                }
                $body['expires'] = [int][DateTimeOffset]::new($expirationDate).ToUnixTimeSeconds()
                $body['expires_type'] = 'date'
            }
        }

        # IP lists
        if ($IPAllowList -and $IPAllowList.Count -gt 0) {
            $body['ip_allow_list'] = $IPAllowList -join ','
        }

        if ($IPDenyList -and $IPDenyList.Count -gt 0) {
            $body['ip_deny_list'] = $IPDenyList -join ','
        }

        if ($PSCmdlet.ShouldProcess("User '$userName'", "Create API Key '$Name'")) {
            try {
                Write-Verbose "Creating API key '$Name' for user '$userName'"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'user_api_keys' -Body $body -Connection $Server

                # Get the created key
                $apiKeyId = $response.'$key'

                # The secret is returned in the response
                $secret = $response.key

                Write-Verbose "API key '$Name' created with Key: $apiKeyId"

                # Output the secret - this is the only time it's visible
                $output = [PSCustomObject]@{
                    PSTypeName = 'Verge.APIKeyCreated'
                    Key        = [int]$apiKeyId
                    Name       = $Name
                    UserName   = $userName
                    Secret     = $secret
                    Message    = 'IMPORTANT: Store this secret securely. It cannot be retrieved again.'
                }

                Write-Output $output

                if ($PassThru) {
                    # Also return the API key object (without secret)
                    Start-Sleep -Milliseconds 500
                    Get-VergeAPIKey -Key $apiKeyId -Server $Server
                }
            }
            catch {
                throw "Failed to create API key '$Name': $($_.Exception.Message)"
            }
        }
    }
}
