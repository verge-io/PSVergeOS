<#
.SYNOPSIS
    Examples for connecting to VergeOS.

.DESCRIPTION
    This script demonstrates various ways to establish and manage
    connections to VergeOS systems using PSVergeOS.

.NOTES
    Prerequisites:
    - PowerShell 7.4 or later
    - PSVergeOS module installed
    - Access to a VergeOS system
#>

# Import the module
Import-Module PSVergeOS

#region Interactive Login

# Connect with interactive credential prompt
Connect-VergeOS -Server "vergeos.company.com" -Credential (Get-Credential)

#endregion

#region Token-Based Login (Automation)

# Set your API token as an environment variable (recommended)
# $env:VERGE_TOKEN = "your-api-token-here"

# Connect using the token
Connect-VergeOS -Server "vergeos.company.com" -Token $env:VERGE_TOKEN

#endregion

#region Self-Signed Certificates

# For development/lab environments with self-signed certificates
Connect-VergeOS -Server "vergeos.local" -Token $env:VERGE_TOKEN -SkipCertificateCheck

#endregion

#region Multiple Connections

# Connect to multiple VergeOS systems
$prod = Connect-VergeOS -Server "prod.vergeos.local" -Token $env:PROD_TOKEN -PassThru
$dev = Connect-VergeOS -Server "dev.vergeos.local" -Token $env:DEV_TOKEN -PassThru

# View all connections
Get-VergeConnection

# The most recent connection is the default
Get-VergeConnection -Default

# Change the default connection
Set-VergeConnection -Server "prod.vergeos.local"

# Query a specific server (not the default)
# Get-VergeVM -Server $dev

#endregion

#region Connection Management

# View connection details
Get-VergeConnection | Format-Table Server, Username, VergeOSVersion, ConnectedAt, IsDefault

# Disconnect from a specific server
Disconnect-VergeOS -Server "dev.vergeos.local"

# Disconnect from all servers
Disconnect-VergeOS -All

#endregion
