function Get-VergeWebhook {
    <#
    .SYNOPSIS
        Retrieves webhook URL configurations from VergeOS.

    .DESCRIPTION
        Get-VergeWebhook retrieves one or more webhook URL configurations from a VergeOS system.
        Webhooks are used to send notifications and data to external systems when events occur.

    .PARAMETER Name
        The name of the webhook to retrieve. Supports wildcards (* and ?).
        If not specified, all webhooks are returned.

    .PARAMETER Key
        The unique key (ID) of the webhook to retrieve.

    .PARAMETER AuthorizationType
        Filter webhooks by authorization type: None, Basic, Bearer, or ApiKey.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeWebhook

        Retrieves all webhook configurations from the connected VergeOS system.

    .EXAMPLE
        Get-VergeWebhook -Name "slack-alerts"

        Retrieves a specific webhook by name.

    .EXAMPLE
        Get-VergeWebhook -Name "*slack*"

        Retrieves webhooks with "slack" in the name.

    .EXAMPLE
        Get-VergeWebhook -AuthorizationType Bearer

        Retrieves all webhooks using Bearer token authentication.

    .EXAMPLE
        Get-VergeWebhook -Key 1

        Retrieves a webhook by its key (ID).

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.Webhook'

    .NOTES
        Authorization types:
        - None: No authorization header sent
        - Basic: HTTP Basic authentication
        - Bearer: Bearer token authentication
        - ApiKey: API key authentication
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
        [ValidateSet('None', 'Basic', 'Bearer', 'ApiKey')]
        [string]$AuthorizationType,

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

        # Map API auth type values to friendly names
        $authTypeDisplayMapping = @{
            'none'   = 'None'
            'basic'  = 'Basic'
            'bearer' = 'Bearer'
            'apikey' = 'API Key'
        }
    }

    process {
        try {
            Write-Verbose "Querying webhooks from $($Server.Server)"

            # Build query parameters
            $queryParams = @{}
            $filters = [System.Collections.Generic.List[string]]::new()

            # Filter by key
            if ($PSCmdlet.ParameterSetName -eq 'ByKey') {
                $filters.Add("`$key eq $Key")
            }
            else {
                # Filter by name
                if ($Name) {
                    if ($Name -match '[\*\?]') {
                        # Wildcard search
                        $searchTerm = $Name -replace '[\*\?]', ''
                        if ($searchTerm) {
                            $filters.Add("name ct '$searchTerm'")
                        }
                    }
                    else {
                        $filters.Add("name eq '$Name'")
                    }
                }

                # Filter by authorization type
                if ($AuthorizationType) {
                    $apiAuthType = $authTypeMapping[$AuthorizationType]
                    $filters.Add("authorization_type eq '$apiAuthType'")
                }
            }

            # Apply filters
            if ($filters.Count -gt 0) {
                $queryParams['filter'] = $filters -join ' and '
            }

            # Request fields
            $queryParams['fields'] = '$key,name,type,url,headers,authorization_type,allow_insecure,timeout,retries'

            $response = Invoke-VergeAPI -Method GET -Endpoint 'webhook_urls' -Query $queryParams -Connection $Server

            # Handle both single object and array responses
            $webhooks = if ($response -is [array]) { $response } else { @($response) }

            foreach ($webhook in $webhooks) {
                # Skip null entries
                if (-not $webhook -or -not $webhook.'$key') {
                    continue
                }

                # Apply wildcard filtering for client-side matching
                if ($Name -and ($Name -match '[\*\?]')) {
                    if ($webhook.name -notlike $Name) {
                        continue
                    }
                }

                # Parse headers into hashtable
                $headersHashtable = @{}
                if ($webhook.headers) {
                    $headerLines = $webhook.headers -split "`n"
                    foreach ($line in $headerLines) {
                        $line = $line.Trim()
                        if ($line -and $line -match '^([^:]+):(.*)$') {
                            $headersHashtable[$Matches[1].Trim()] = $Matches[2].Trim()
                        }
                    }
                }

                # Get auth type display name
                $authTypeDisplay = $authTypeDisplayMapping[$webhook.authorization_type]
                if (-not $authTypeDisplay) {
                    $authTypeDisplay = $webhook.authorization_type
                }

                # Create output object
                $output = [PSCustomObject]@{
                    PSTypeName            = 'Verge.Webhook'
                    Key                   = [int]$webhook.'$key'
                    Name                  = $webhook.name
                    Type                  = $webhook.type
                    URL                   = $webhook.url
                    Headers               = $headersHashtable
                    HeadersRaw            = $webhook.headers
                    AuthorizationType     = $authTypeDisplay
                    AuthorizationTypeValue = $webhook.authorization_type
                    AllowInsecure         = [bool]$webhook.allow_insecure
                    Timeout               = [int]$webhook.timeout
                    Retries               = [int]$webhook.retries
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
