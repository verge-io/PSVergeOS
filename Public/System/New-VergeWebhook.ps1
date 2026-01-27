function New-VergeWebhook {
    <#
    .SYNOPSIS
        Creates a new webhook URL configuration in VergeOS.

    .DESCRIPTION
        New-VergeWebhook creates a new webhook URL configuration in VergeOS.
        Webhooks are used to send notifications and data to external systems when events occur.

    .PARAMETER Name
        The name of the webhook. Must be unique within the VergeOS system.

    .PARAMETER URL
        The destination URL for webhook payloads. Must start with http:// or https://.

    .PARAMETER Headers
        Custom HTTP headers to include in webhook requests. Can be specified as:
        - A hashtable: @{ 'Content-Type' = 'application/json'; 'X-Custom' = 'value' }
        - A string in "Header:Value" format (newline-separated for multiple headers)
        Default header is Content-Type: application/json.

    .PARAMETER AuthorizationType
        The authorization method for webhook requests:
        - None: No authorization header (default)
        - Basic: HTTP Basic authentication
        - Bearer: Bearer token authentication
        - ApiKey: API key authentication

    .PARAMETER AuthorizationValue
        The authorization credential value. Usage depends on AuthorizationType:
        - Basic: username:password (will be base64 encoded)
        - Bearer: token value
        - ApiKey: key value

    .PARAMETER AuthorizationCredential
        A PSCredential object for Basic authentication. Alternative to AuthorizationValue.

    .PARAMETER AllowInsecure
        Allow connections to servers with invalid or self-signed SSL certificates.

    .PARAMETER Timeout
        The request timeout in seconds. Range: 3-120, default: 5.

    .PARAMETER Retries
        The number of retry attempts for failed deliveries. Range: 0-100, default: 3.

    .PARAMETER PassThru
        Return the created webhook object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeWebhook -Name "slack-alerts" -URL "https://hooks.slack.com/services/xxx"

        Creates a webhook for Slack notifications.

    .EXAMPLE
        New-VergeWebhook -Name "api-notify" -URL "https://api.example.com/webhook" -AuthorizationType Bearer -AuthorizationValue "mytoken123" -PassThru

        Creates a webhook with Bearer token authentication and returns the created object.

    .EXAMPLE
        $headers = @{ 'Content-Type' = 'application/json'; 'X-Source' = 'VergeOS' }
        New-VergeWebhook -Name "custom-webhook" -URL "https://example.com/hook" -Headers $headers -Timeout 30

        Creates a webhook with custom headers and a 30-second timeout.

    .EXAMPLE
        $cred = Get-Credential
        New-VergeWebhook -Name "basic-auth-hook" -URL "https://example.com/hook" -AuthorizationType Basic -AuthorizationCredential $cred

        Creates a webhook with HTTP Basic authentication using credentials.

    .OUTPUTS
        None by default. Verge.Webhook when -PassThru is specified.

    .NOTES
        The webhook URL must be accessible from the VergeOS system.
        Consider network/firewall settings when configuring external webhook destinations.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [ValidateLength(1, 128)]
        [string]$Name,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^https?://')]
        [Alias('Uri')]
        [string]$URL,

        [Parameter()]
        [object]$Headers,

        [Parameter()]
        [ValidateSet('None', 'Basic', 'Bearer', 'ApiKey')]
        [string]$AuthorizationType = 'None',

        [Parameter()]
        [string]$AuthorizationValue,

        [Parameter()]
        [PSCredential]$AuthorizationCredential,

        [Parameter()]
        [switch]$AllowInsecure,

        [Parameter()]
        [ValidateRange(3, 120)]
        [int]$Timeout,

        [Parameter()]
        [ValidateRange(0, 100)]
        [int]$Retries,

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

        # Map friendly auth type names to API values
        $authTypeMapping = @{
            'None'   = 'none'
            'Basic'  = 'basic'
            'Bearer' = 'bearer'
            'ApiKey' = 'apikey'
        }
    }

    process {
        # Validate authorization parameters
        if ($AuthorizationType -ne 'None') {
            if ($AuthorizationType -eq 'Basic' -and $AuthorizationCredential) {
                # Convert credential to username:password format
                $username = $AuthorizationCredential.UserName
                $password = $AuthorizationCredential.GetNetworkCredential().Password
                $AuthorizationValue = "${username}:${password}"
            }
            elseif (-not $AuthorizationValue) {
                throw "AuthorizationValue or AuthorizationCredential is required when AuthorizationType is '$AuthorizationType'."
            }
        }

        # Build request body
        $body = @{
            name = $Name
            url  = $URL
        }

        # Process headers
        if ($Headers) {
            if ($Headers -is [hashtable] -or $Headers -is [System.Collections.IDictionary]) {
                # Convert hashtable to newline-separated format
                $headerLines = foreach ($key in $Headers.Keys) {
                    "${key}:$($Headers[$key])"
                }
                $body['headers'] = ($headerLines -join "`n") + "`n"
            }
            elseif ($Headers -is [string]) {
                # Use string as-is (ensure trailing newline)
                $body['headers'] = if ($Headers.EndsWith("`n")) { $Headers } else { "$Headers`n" }
            }
            else {
                throw "Headers must be a hashtable or string."
            }
        }

        # Authorization
        $body['authorization_type'] = $authTypeMapping[$AuthorizationType]
        if ($AuthorizationValue) {
            $body['authorization_value'] = $AuthorizationValue
        }

        # Optional settings
        if ($PSBoundParameters.ContainsKey('AllowInsecure')) {
            $body['allow_insecure'] = $AllowInsecure.IsPresent
        }

        if ($PSBoundParameters.ContainsKey('Timeout')) {
            $body['timeout'] = $Timeout
        }

        if ($PSBoundParameters.ContainsKey('Retries')) {
            $body['retries'] = $Retries
        }

        if ($PSCmdlet.ShouldProcess("$Name ($URL)", 'Create Webhook')) {
            try {
                Write-Verbose "Creating webhook '$Name' pointing to '$URL'"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'webhook_urls' -Body $body -Connection $Server

                # Get the created webhook key
                $webhookKey = $response.'$key'
                if (-not $webhookKey -and $response.key) {
                    $webhookKey = $response.key
                }

                Write-Verbose "Webhook created with Key: $webhookKey"

                if ($PassThru -and $webhookKey) {
                    # Return the created webhook
                    Start-Sleep -Milliseconds 500
                    Get-VergeWebhook -Key $webhookKey -Server $Server
                }
            }
            catch {
                $errorMessage = $_.Exception.Message
                if ($errorMessage -match 'already exists' -or $errorMessage -match 'duplicate' -or $errorMessage -match 'unique') {
                    throw "A webhook with name '$Name' already exists."
                }
                throw "Failed to create webhook '$Name': $errorMessage"
            }
        }
    }
}
