#Requires -Modules PSVergeOS
<#
.SYNOPSIS
    Demonstrates webhook integration with VergeOS for event notifications.

.DESCRIPTION
    This example shows how to configure webhooks to send notifications
    to external systems like Slack, Microsoft Teams, or custom APIs.

.NOTES
    Prerequisites:
    - PSVergeOS module installed
    - Connection to VergeOS established
    - Destination webhook URLs (e.g., Slack incoming webhook)
#>

# Connect to VergeOS (replace with your credentials)
$credential = Get-Credential -Message "Enter VergeOS credentials"
Connect-VergeOS -Server "https://vergeos.example.com" -Credential $credential

# ============================================================================
# WEBHOOK CONFIGURATION
# ============================================================================

# List all configured webhooks
Write-Host "Current webhook configurations:" -ForegroundColor Cyan
Get-VergeWebhook | Format-Table Name, URL, AuthorizationType, Timeout

# ============================================================================
# EXAMPLE 1: Create a Simple Webhook (No Authentication)
# ============================================================================

# Create a webhook for Slack notifications
$slackWebhook = New-VergeWebhook -Name "slack-alerts" `
    -URL "https://hooks.slack.com/services/YOUR/WEBHOOK/URL" `
    -Timeout 10 `
    -Retries 3 `
    -PassThru

Write-Host "Created webhook: $($slackWebhook.Name)" -ForegroundColor Green

# ============================================================================
# EXAMPLE 2: Create a Webhook with Bearer Token Authentication
# ============================================================================

# Create a webhook with API authentication
$apiWebhook = New-VergeWebhook -Name "monitoring-api" `
    -URL "https://api.monitoring.example.com/events" `
    -AuthorizationType Bearer `
    -AuthorizationValue "your-api-token" `
    -Timeout 15 `
    -PassThru

Write-Host "Created webhook: $($apiWebhook.Name)" -ForegroundColor Green

# ============================================================================
# EXAMPLE 3: Create a Webhook with Custom Headers
# ============================================================================

# Create a webhook with custom headers
$headers = @{
    'Content-Type' = 'application/json'
    'X-Source'     = 'VergeOS'
    'X-Priority'   = 'high'
}

$customWebhook = New-VergeWebhook -Name "custom-endpoint" `
    -URL "https://api.example.com/webhook" `
    -Headers $headers `
    -AuthorizationType ApiKey `
    -AuthorizationValue "sk-your-api-key" `
    -Timeout 30 `
    -PassThru

Write-Host "Created webhook: $($customWebhook.Name)" -ForegroundColor Green

# ============================================================================
# EXAMPLE 4: Send Test Messages
# ============================================================================

# Send a default test message
Send-VergeWebhook -Name "slack-alerts"
Write-Host "Sent default test message" -ForegroundColor Yellow

# Send a custom message to Slack
$slackMessage = @{
    text   = "VergeOS Alert: Test notification"
    blocks = @(
        @{
            type = "section"
            text = @{
                type = "mrkdwn"
                text = "*VergeOS Notification*`nThis is a test message from the webhook integration."
            }
        }
    )
}

Send-VergeWebhook -Name "slack-alerts" -Message $slackMessage
Write-Host "Sent custom Slack message" -ForegroundColor Yellow

# Send a JSON message to an API endpoint
$apiMessage = @{
    event     = "test"
    timestamp = (Get-Date).ToString("o")
    source    = "VergeOS"
    data      = @{
        message = "Webhook integration test"
        level   = "info"
    }
}

Send-VergeWebhook -Name "monitoring-api" -Message $apiMessage
Write-Host "Sent API event message" -ForegroundColor Yellow

# ============================================================================
# EXAMPLE 5: Check Webhook Delivery History
# ============================================================================

# View recent webhook history
Write-Host "`nRecent webhook deliveries:" -ForegroundColor Cyan
Get-VergeWebhookHistory -Limit 10 | Format-Table WebhookName, Status, StatusInfo, Created

# Check for failed deliveries
$failed = Get-VergeWebhookHistory -Failed -Limit 5
if ($failed) {
    Write-Host "`nFailed deliveries:" -ForegroundColor Red
    $failed | Format-Table WebhookName, StatusInfo, Created
}
else {
    Write-Host "`nNo failed deliveries found" -ForegroundColor Green
}

# Check pending messages
$pending = Get-VergeWebhookHistory -Pending
if ($pending) {
    Write-Host "`nPending messages:" -ForegroundColor Yellow
    $pending | Format-Table WebhookName, Status, Created
}
else {
    Write-Host "`nNo pending messages" -ForegroundColor Green
}

# View history for a specific webhook
Write-Host "`nDelivery history for slack-alerts:" -ForegroundColor Cyan
Get-VergeWebhookHistory -WebhookName "slack-alerts" -Limit 5 |
    Format-Table Status, StatusInfo, Created

# ============================================================================
# EXAMPLE 6: Update Webhook Configuration
# ============================================================================

# Update webhook timeout and retries
Set-VergeWebhook -Name "slack-alerts" -Timeout 20 -Retries 5
Write-Host "Updated slack-alerts timeout and retries" -ForegroundColor Green

# Update authentication
Set-VergeWebhook -Name "monitoring-api" `
    -AuthorizationType Bearer `
    -AuthorizationValue "new-api-token"
Write-Host "Updated monitoring-api authentication" -ForegroundColor Green

# Enable insecure connections for internal endpoints
Set-VergeWebhook -Name "custom-endpoint" -AllowInsecure $true
Write-Host "Enabled insecure connections for custom-endpoint" -ForegroundColor Yellow

# ============================================================================
# EXAMPLE 7: Resource Groups (For Reference)
# ============================================================================

# List all resource groups (GPU, PCI, USB device pools)
Write-Host "`nResource groups:" -ForegroundColor Cyan
$resourceGroups = Get-VergeResourceGroup
if ($resourceGroups) {
    $resourceGroups | Format-Table Name, Type, Class, Enabled
}
else {
    Write-Host "No resource groups configured" -ForegroundColor Gray
}

# Filter by type (e.g., GPU passthrough)
$gpuGroups = Get-VergeResourceGroup -Type HostGPU
if ($gpuGroups) {
    Write-Host "`nHost GPU resource groups:" -ForegroundColor Cyan
    $gpuGroups | Format-Table Name, Description, Enabled
}

# ============================================================================
# EXAMPLE 8: Cleanup
# ============================================================================

# Remove test webhooks (uncomment to execute)
# Remove-VergeWebhook -Name "slack-alerts" -Confirm:$false
# Remove-VergeWebhook -Name "monitoring-api" -Confirm:$false
# Remove-VergeWebhook -Name "custom-endpoint" -Confirm:$false

# Remove all webhooks matching a pattern
# Get-VergeWebhook -Name "test-*" | Remove-VergeWebhook -Confirm:$false

Write-Host "`nWebhook integration examples complete!" -ForegroundColor Green
