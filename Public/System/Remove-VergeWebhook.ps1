function Remove-VergeWebhook {
    <#
    .SYNOPSIS
        Removes a webhook URL configuration from VergeOS.

    .DESCRIPTION
        Remove-VergeWebhook deletes a webhook URL configuration from VergeOS.
        This also removes any pending webhook messages in the queue for this webhook.

    .PARAMETER Key
        The unique key (ID) of the webhook to remove.

    .PARAMETER Name
        The name of the webhook to remove.

    .PARAMETER InputObject
        A webhook object from Get-VergeWebhook. Used for pipeline input.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeWebhook -Key 1

        Removes the webhook with key 1.

    .EXAMPLE
        Remove-VergeWebhook -Name "slack-alerts"

        Removes the webhook named "slack-alerts".

    .EXAMPLE
        Get-VergeWebhook -Name "pstest*" | Remove-VergeWebhook

        Removes all webhooks matching the pattern "pstest*".

    .EXAMPLE
        Remove-VergeWebhook -Key 1 -Confirm:$false

        Removes the webhook without confirmation prompt.

    .OUTPUTS
        None
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByKey')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByKey')]
        [Alias('Id', '$key')]
        [int]$Key,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByInputObject')]
        [PSTypeName('Verge.Webhook')]
        [object]$InputObject,

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

        $confirmMessage = "Webhook '$webhookName' (Key: $webhookKey)"

        if ($PSCmdlet.ShouldProcess($confirmMessage, 'Remove')) {
            try {
                Write-Verbose "Removing webhook '$webhookName' (Key: $webhookKey)"
                Invoke-VergeAPI -Method DELETE -Endpoint "webhook_urls/$webhookKey" -Connection $Server | Out-Null
                Write-Verbose "Webhook '$webhookName' removed successfully"
            }
            catch {
                $errorMessage = $_.Exception.Message
                if ($errorMessage -match 'not found' -or $errorMessage -match '404') {
                    throw "Webhook with key $webhookKey not found."
                }
                throw "Failed to remove webhook '$webhookName': $errorMessage"
            }
        }
    }
}
