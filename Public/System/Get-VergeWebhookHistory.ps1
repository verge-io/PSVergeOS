function Get-VergeWebhookHistory {
    <#
    .SYNOPSIS
        Retrieves webhook delivery history from VergeOS.

    .DESCRIPTION
        Get-VergeWebhookHistory retrieves the webhook message delivery queue and history.
        This shows messages that have been queued, are in progress, have been delivered,
        or have failed delivery.

    .PARAMETER Key
        The unique key (ID) of a specific webhook history entry to retrieve.

    .PARAMETER WebhookKey
        Filter to show history for a specific webhook URL by its key (ID).

    .PARAMETER WebhookName
        Filter to show history for a specific webhook URL by its name.

    .PARAMETER Status
        Filter by delivery status: Queued, Running, Sent, or Error.

    .PARAMETER Pending
        Show only pending messages (queued or running).

    .PARAMETER Failed
        Show only failed messages (error status).

    .PARAMETER Limit
        Maximum number of history entries to return. Default is 100.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeWebhookHistory

        Retrieves recent webhook delivery history.

    .EXAMPLE
        Get-VergeWebhookHistory -WebhookName "slack-alerts"

        Retrieves delivery history for the "slack-alerts" webhook.

    .EXAMPLE
        Get-VergeWebhookHistory -Status Error

        Retrieves all failed webhook deliveries.

    .EXAMPLE
        Get-VergeWebhookHistory -Pending

        Retrieves all pending (queued or running) webhook messages.

    .EXAMPLE
        Get-VergeWebhookHistory -WebhookKey 1 -Limit 10

        Retrieves the last 10 deliveries for webhook with key 1.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.WebhookHistory'

    .NOTES
        Webhook messages are automatically cleaned up after 70 days.
        The maximum stored entries is 3000, with automatic deletion of oldest entries
        beyond 1000 when the limit is reached.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Filter')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByKey', ValueFromPipelineByPropertyName)]
        [Alias('Id', '$key')]
        [int]$Key,

        [Parameter(ParameterSetName = 'Filter')]
        [int]$WebhookKey,

        [Parameter(ParameterSetName = 'Filter')]
        [string]$WebhookName,

        [Parameter(ParameterSetName = 'Filter')]
        [ValidateSet('Queued', 'Running', 'Sent', 'Error')]
        [string]$Status,

        [Parameter(ParameterSetName = 'Filter')]
        [switch]$Pending,

        [Parameter(ParameterSetName = 'Filter')]
        [switch]$Failed,

        [Parameter(ParameterSetName = 'Filter')]
        [ValidateRange(1, 3000)]
        [int]$Limit = 100,

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

        # Map friendly status names to API values
        $statusMapping = @{
            'Queued'  = 'queued'
            'Running' = 'running'
            'Sent'    = 'sent'
            'Error'   = 'error'
        }

        # Map API status values to friendly names
        $statusDisplayMapping = @{
            'queued'  = 'Queued'
            'running' = 'Running'
            'sent'    = 'Sent'
            'error'   = 'Error'
        }

        # Cache for webhook URL lookups
        $webhookCache = @{}
    }

    process {
        try {
            Write-Verbose "Querying webhook history from $($Server.Server)"

            # Resolve webhook name to key if specified
            $resolvedWebhookKey = $WebhookKey
            if ($WebhookName) {
                $webhook = Get-VergeWebhook -Name $WebhookName -Server $Server -ErrorAction Stop
                if (-not $webhook) {
                    throw "Webhook '$WebhookName' not found."
                }
                if ($webhook -is [array]) {
                    throw "Multiple webhooks match name '$WebhookName'. Use -WebhookKey to specify the exact webhook."
                }
                $resolvedWebhookKey = $webhook.Key
                $webhookCache[$webhook.Key] = $webhook.Name
            }

            # Build query parameters
            $queryParams = @{}
            $filters = [System.Collections.Generic.List[string]]::new()

            # Filter by key
            if ($PSCmdlet.ParameterSetName -eq 'ByKey') {
                $filters.Add("`$key eq $Key")
            }
            else {
                # Filter by webhook URL
                if ($resolvedWebhookKey) {
                    $filters.Add("webhook_url eq $resolvedWebhookKey")
                }

                # Filter by status
                if ($Status) {
                    $apiStatus = $statusMapping[$Status]
                    $filters.Add("status eq '$apiStatus'")
                }
                elseif ($Pending) {
                    $filters.Add("(status eq 'queued' or status eq 'running')")
                }
                elseif ($Failed) {
                    $filters.Add("status eq 'error'")
                }

                # Limit results
                $queryParams['limit'] = $Limit
            }

            # Apply filters
            if ($filters.Count -gt 0) {
                $queryParams['filter'] = $filters -join ' and '
            }

            # Request fields and sort by created descending (newest first)
            $queryParams['fields'] = '$key,webhook_url,message,status,status_info,last_attempt,created'
            $queryParams['sort'] = '-created'

            $response = Invoke-VergeAPI -Method GET -Endpoint 'webhooks' -Query $queryParams -Connection $Server

            # Handle both single object and array responses
            $entries = if ($response -is [array]) { $response } else { @($response) }

            foreach ($entry in $entries) {
                # Skip null entries
                if (-not $entry -or -not $entry.'$key') {
                    continue
                }

                # Get webhook name from cache or lookup
                $webhookUrlKey = $entry.webhook_url
                $webhookUrlName = $null
                if ($webhookUrlKey) {
                    if ($webhookCache.ContainsKey($webhookUrlKey)) {
                        $webhookUrlName = $webhookCache[$webhookUrlKey]
                    }
                    else {
                        try {
                            $wh = Get-VergeWebhook -Key $webhookUrlKey -Server $Server -ErrorAction SilentlyContinue
                            if ($wh) {
                                $webhookUrlName = $wh.Name
                                $webhookCache[$webhookUrlKey] = $wh.Name
                            }
                        }
                        catch {
                            # Webhook may have been deleted
                        }
                    }
                }

                # Get status display name
                $statusDisplay = $statusDisplayMapping[$entry.status]
                if (-not $statusDisplay) {
                    $statusDisplay = $entry.status
                }

                # Parse message JSON for display
                $messageObject = $null
                if ($entry.message) {
                    try {
                        $messageObject = $entry.message | ConvertFrom-Json
                    }
                    catch {
                        # Keep as string if not valid JSON
                    }
                }

                # Create output object
                $output = [PSCustomObject]@{
                    PSTypeName     = 'Verge.WebhookHistory'
                    Key            = [int]$entry.'$key'
                    WebhookKey     = if ($webhookUrlKey) { [int]$webhookUrlKey } else { $null }
                    WebhookName    = $webhookUrlName
                    Status         = $statusDisplay
                    StatusValue    = $entry.status
                    StatusInfo     = $entry.status_info
                    Message        = $messageObject
                    MessageRaw     = $entry.message
                    LastAttempt    = if ($entry.last_attempt) { [DateTimeOffset]::FromUnixTimeSeconds($entry.last_attempt).LocalDateTime } else { $null }
                    Created        = if ($entry.created) { [DateTimeOffset]::FromUnixTimeSeconds($entry.created).LocalDateTime } else { $null }
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
