function Set-VergeWebhook {
    <#
    .SYNOPSIS
        Updates an existing webhook URL configuration in VergeOS.

    .DESCRIPTION
        Set-VergeWebhook updates an existing webhook URL configuration in VergeOS.
        You can modify the name, URL, headers, authentication, and other settings.

    .PARAMETER Key
        The unique key (ID) of the webhook to update.

    .PARAMETER InputObject
        A webhook object from Get-VergeWebhook. Used for pipeline input.

    .PARAMETER Name
        The new name for the webhook. Must be unique within the VergeOS system.

    .PARAMETER URL
        The new destination URL for webhook payloads.

    .PARAMETER Headers
        Custom HTTP headers to include in webhook requests. Can be specified as:
        - A hashtable: @{ 'Content-Type' = 'application/json'; 'X-Custom' = 'value' }
        - A string in "Header:Value" format (newline-separated for multiple headers)

    .PARAMETER AuthorizationType
        The authorization method for webhook requests:
        - None: No authorization header
        - Basic: HTTP Basic authentication
        - Bearer: Bearer token authentication
        - ApiKey: API key authentication

    .PARAMETER AuthorizationValue
        The authorization credential value.

    .PARAMETER AuthorizationCredential
        A PSCredential object for Basic authentication.

    .PARAMETER AllowInsecure
        Allow connections to servers with invalid or self-signed SSL certificates.

    .PARAMETER Timeout
        The request timeout in seconds. Range: 3-120.

    .PARAMETER Retries
        The number of retry attempts for failed deliveries. Range: 0-100.

    .PARAMETER PassThru
        Return the updated webhook object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Set-VergeWebhook -Key 1 -Timeout 30

        Updates the timeout for webhook with key 1 to 30 seconds.

    .EXAMPLE
        Get-VergeWebhook -Name "slack-alerts" | Set-VergeWebhook -URL "https://new-url.example.com/hook" -PassThru

        Updates the URL for the "slack-alerts" webhook using pipeline input.

    .EXAMPLE
        Set-VergeWebhook -Key 1 -AuthorizationType Bearer -AuthorizationValue "newtoken123"

        Updates the webhook to use Bearer token authentication.

    .OUTPUTS
        None by default. Verge.Webhook when -PassThru is specified.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByKey')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByKey')]
        [Alias('Id', '$key')]
        [int]$Key,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByInputObject')]
        [PSTypeName('Verge.Webhook')]
        [object]$InputObject,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [ValidateLength(1, 128)]
        [string]$Name,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^https?://')]
        [Alias('Uri')]
        [string]$URL,

        [Parameter()]
        [object]$Headers,

        [Parameter()]
        [ValidateSet('None', 'Basic', 'Bearer', 'ApiKey')]
        [string]$AuthorizationType,

        [Parameter()]
        [string]$AuthorizationValue,

        [Parameter()]
        [PSCredential]$AuthorizationCredential,

        [Parameter()]
        [bool]$AllowInsecure,

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
        # Get key from input object if provided
        if ($PSCmdlet.ParameterSetName -eq 'ByInputObject') {
            $Key = $InputObject.Key
            # Use connection from input object if available and not explicitly specified
            if ($InputObject._Connection -and -not $PSBoundParameters.ContainsKey('Server')) {
                $Server = $InputObject._Connection
            }
        }

        # Build request body with only specified parameters
        $body = @{}
        $changes = [System.Collections.Generic.List[string]]::new()

        if ($PSBoundParameters.ContainsKey('Name')) {
            $body['name'] = $Name
            $changes.Add("Name=$Name")
        }

        if ($PSBoundParameters.ContainsKey('URL')) {
            $body['url'] = $URL
            $changes.Add("URL=$URL")
        }

        # Process headers
        if ($PSBoundParameters.ContainsKey('Headers')) {
            if ($null -eq $Headers) {
                $body['headers'] = ''
                $changes.Add("Headers=cleared")
            }
            elseif ($Headers -is [hashtable] -or $Headers -is [System.Collections.IDictionary]) {
                $headerLines = foreach ($key in $Headers.Keys) {
                    "${key}:$($Headers[$key])"
                }
                $body['headers'] = ($headerLines -join "`n") + "`n"
                $changes.Add("Headers=updated")
            }
            elseif ($Headers -is [string]) {
                $body['headers'] = if ($Headers.EndsWith("`n")) { $Headers } else { "$Headers`n" }
                $changes.Add("Headers=updated")
            }
        }

        # Authorization
        if ($PSBoundParameters.ContainsKey('AuthorizationType')) {
            $body['authorization_type'] = $authTypeMapping[$AuthorizationType]
            $changes.Add("AuthorizationType=$AuthorizationType")

            # Handle Basic auth with credential
            if ($AuthorizationType -eq 'Basic' -and $AuthorizationCredential) {
                $username = $AuthorizationCredential.UserName
                $password = $AuthorizationCredential.GetNetworkCredential().Password
                $body['authorization_value'] = "${username}:${password}"
                $changes.Add("AuthorizationValue=***")
            }
            elseif ($AuthorizationType -ne 'None' -and $PSBoundParameters.ContainsKey('AuthorizationValue')) {
                $body['authorization_value'] = $AuthorizationValue
                $changes.Add("AuthorizationValue=***")
            }
        }
        elseif ($PSBoundParameters.ContainsKey('AuthorizationValue')) {
            $body['authorization_value'] = $AuthorizationValue
            $changes.Add("AuthorizationValue=***")
        }

        if ($PSBoundParameters.ContainsKey('AllowInsecure')) {
            $body['allow_insecure'] = $AllowInsecure
            $changes.Add("AllowInsecure=$AllowInsecure")
        }

        if ($PSBoundParameters.ContainsKey('Timeout')) {
            $body['timeout'] = $Timeout
            $changes.Add("Timeout=$Timeout")
        }

        if ($PSBoundParameters.ContainsKey('Retries')) {
            $body['retries'] = $Retries
            $changes.Add("Retries=$Retries")
        }

        if ($body.Count -eq 0) {
            Write-Warning "No changes specified. Use parameters to specify what to update."
            return
        }

        $changeDescription = $changes -join ', '

        if ($PSCmdlet.ShouldProcess("Webhook Key $Key", "Update ($changeDescription)")) {
            try {
                Write-Verbose "Updating webhook $Key with changes: $changeDescription"
                Invoke-VergeAPI -Method PUT -Endpoint "webhook_urls/$Key" -Body $body -Connection $Server | Out-Null

                Write-Verbose "Webhook $Key updated successfully"

                if ($PassThru) {
                    Get-VergeWebhook -Key $Key -Server $Server
                }
            }
            catch {
                $errorMessage = $_.Exception.Message
                if ($errorMessage -match 'not found' -or $errorMessage -match '404') {
                    throw "Webhook with key $Key not found."
                }
                if ($errorMessage -match 'already exists' -or $errorMessage -match 'duplicate' -or $errorMessage -match 'unique') {
                    throw "A webhook with that name already exists."
                }
                throw "Failed to update webhook $Key`: $errorMessage"
            }
        }
    }
}
