function Send-VergeWebhook {
    <#
    .SYNOPSIS
        Sends a test message to a webhook URL in VergeOS.

    .DESCRIPTION
        Send-VergeWebhook sends a test message to a configured webhook URL.
        This is useful for verifying that the webhook endpoint is reachable
        and properly configured to receive messages from VergeOS.

    .PARAMETER Key
        The unique key (ID) of the webhook to send a test message to.

    .PARAMETER Name
        The name of the webhook to send a test message to.

    .PARAMETER InputObject
        A webhook object from Get-VergeWebhook. Used for pipeline input.

    .PARAMETER Message
        The JSON message payload to send. Defaults to a simple test message.
        Can be a string (JSON) or a hashtable/object that will be converted to JSON.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Send-VergeWebhook -Key 1

        Sends a default test message to the webhook with key 1.

    .EXAMPLE
        Send-VergeWebhook -Name "slack-alerts"

        Sends a test message to the webhook named "slack-alerts".

    .EXAMPLE
        Send-VergeWebhook -Key 1 -Message '{"text": "Test from PowerShell"}'

        Sends a custom JSON message to the webhook.

    .EXAMPLE
        $msg = @{ text = "Alert from VergeOS"; channel = "#alerts" }
        Get-VergeWebhook -Name "slack" | Send-VergeWebhook -Message $msg

        Sends a custom message using pipeline input and a hashtable.

    .EXAMPLE
        Get-VergeWebhook | Send-VergeWebhook -Verbose

        Sends test messages to all configured webhooks.

    .OUTPUTS
        None. Check Get-VergeWebhookHistory for delivery status.

    .NOTES
        The message is queued for delivery. Use Get-VergeWebhookHistory to check
        the delivery status of sent messages.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByKey')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByKey')]
        [Alias('Id', '$key')]
        [int]$Key,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByInputObject')]
        [PSTypeName('Verge.Webhook')]
        [object]$InputObject,

        [Parameter(Position = 1)]
        [object]$Message,

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
        # Resolve the key based on parameter set
        $webhookKey = $null
        $webhookName = $null

        switch ($PSCmdlet.ParameterSetName) {
            'ByKey' {
                $webhookKey = $Key
            }
            'ByName' {
                # Look up webhook by name
                $webhook = Get-VergeWebhook -Name $Name -Server $Server -ErrorAction Stop
                if (-not $webhook) {
                    throw "Webhook '$Name' not found."
                }
                if ($webhook -is [array]) {
                    throw "Multiple webhooks match name '$Name'. Use -Key to specify the exact webhook."
                }
                $webhookKey = $webhook.Key
                $webhookName = $webhook.Name
            }
            'ByInputObject' {
                $webhookKey = $InputObject.Key
                $webhookName = $InputObject.Name
                # Use connection from input object if available
                if ($InputObject._Connection -and -not $PSBoundParameters.ContainsKey('Server')) {
                    $Server = $InputObject._Connection
                }
            }
        }

        # Get webhook details for confirmation message if we don't have the name
        if (-not $webhookName) {
            try {
                $webhook = Get-VergeWebhook -Key $webhookKey -Server $Server -ErrorAction SilentlyContinue
                $webhookName = $webhook.Name
            }
            catch {
                $webhookName = "Key $webhookKey"
            }
        }

        # Process message
        $messageJson = $null
        if ($PSBoundParameters.ContainsKey('Message')) {
            if ($Message -is [string]) {
                $messageJson = $Message
            }
            elseif ($Message -is [hashtable] -or $Message -is [System.Collections.IDictionary] -or $Message -is [PSCustomObject]) {
                $messageJson = $Message | ConvertTo-Json -Depth 10 -Compress
            }
            else {
                $messageJson = $Message | ConvertTo-Json -Depth 10 -Compress
            }
        }
        else {
            # Default test message
            $messageJson = '{"text": "Webhook test from VergeOS"}'
        }

        $confirmMessage = "Send test message to webhook '$webhookName' (Key: $webhookKey)"

        if ($PSCmdlet.ShouldProcess($confirmMessage, 'Send')) {
            try {
                Write-Verbose "Sending test message to webhook '$webhookName' (Key: $webhookKey)"
                Write-Verbose "Message: $messageJson"

                $body = @{
                    message = $messageJson
                }

                # Use the action endpoint pattern: webhook_urls/{id}/send
                Invoke-VergeAPI -Method POST -Endpoint "webhook_urls/$webhookKey/send" -Body $body -Connection $Server | Out-Null

                Write-Verbose "Test message queued for webhook '$webhookName'"
            }
            catch {
                $errorMessage = $_.Exception.Message
                if ($errorMessage -match 'not found' -or $errorMessage -match '404') {
                    throw "Webhook with key $webhookKey not found."
                }
                throw "Failed to send test message to webhook '$webhookName': $errorMessage"
            }
        }
    }
}
