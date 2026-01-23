<#
.SYNOPSIS
    Examples for network management and firewall configuration.

.DESCRIPTION
    This script demonstrates network management tasks:
    - Creating and managing networks
    - Configuring DHCP reservations
    - Creating firewall rules
    - Managing DNS records
    - Network diagnostics

.NOTES
    Prerequisites:
    - PowerShell 7.4 or later
    - PSVergeOS module installed
    - Connected to a VergeOS system
#>

# Import the module
Import-Module PSVergeOS

#region Listing Networks
# ============================================================================
# QUERYING NETWORKS
# ============================================================================

# List all networks
Get-VergeNetwork

# List only running networks
Get-VergeNetwork -PowerState Running

# Find network by name
Get-VergeNetwork -Name "Internal"

# Find networks by type
Get-VergeNetwork -Type Internal
Get-VergeNetwork -Type External
Get-VergeNetwork -Type DMZ

# Networks with DHCP enabled
Get-VergeNetwork | Where-Object { $_.DHCPEnabled }

# Display network details
Get-VergeNetwork -Name "Internal" | Format-List *

#endregion

#region Creating Networks
# ============================================================================
# CREATING NETWORKS
# ============================================================================

# Create a basic internal network
New-VergeNetwork -Name "Dev-Network" -NetworkAddress "10.10.0.0/24"

# Create network with DHCP
New-VergeNetwork `
    -Name "Dev-Network" `
    -NetworkAddress "10.10.0.0/24" `
    -IPAddress "10.10.0.1" `
    -Gateway "10.10.0.1" `
    -DHCPEnabled `
    -DHCPStart "10.10.0.100" `
    -DHCPStop "10.10.0.200" `
    -PowerOn

# Create network routed through another network
New-VergeNetwork `
    -Name "App-Tier" `
    -Type Internal `
    -NetworkAddress "10.20.0.0/24" `
    -IPAddress "10.20.0.1" `
    -InterfaceNetwork "External" `
    -DHCPEnabled `
    -DHCPStart "10.20.0.50" `
    -DHCPStop "10.20.0.150" `
    -DNSServers @("8.8.8.8", "8.8.4.4") `
    -Domain "app.local" `
    -PowerOn `
    -PassThru

# Create a DMZ network
New-VergeNetwork `
    -Name "Web-DMZ" `
    -Type DMZ `
    -NetworkAddress "172.16.0.0/24" `
    -IPAddress "172.16.0.1" `
    -InterfaceNetwork "External" `
    -Description "Public-facing web servers" `
    -PowerOn

#endregion

#region Network Lifecycle
# ============================================================================
# NETWORK POWER OPERATIONS
# ============================================================================

# Start a network
Start-VergeNetwork -Name "Dev-Network"

# Stop a network
Stop-VergeNetwork -Name "Dev-Network"

# Restart a network (applies configuration changes)
Restart-VergeNetwork -Name "Dev-Network"

# Modify network settings
Set-VergeNetwork -Name "Dev-Network" -DHCPStart "10.10.0.50" -DHCPStop "10.10.0.250"

# Remove a network (must be stopped first)
Stop-VergeNetwork -Name "Old-Network" -Confirm:$false
Remove-VergeNetwork -Name "Old-Network" -Confirm:$false

#endregion

#region DHCP Reservations
# ============================================================================
# MANAGING DHCP HOST RESERVATIONS
# ============================================================================

# List DHCP reservations on a network
Get-VergeNetworkHost -Network "Internal"

# Create a DHCP reservation
New-VergeNetworkHost `
    -Network "Internal" `
    -Hostname "server01" `
    -MACAddress "00:11:22:33:44:55" `
    -IPAddress "10.10.0.10"

# Create reservation with description
New-VergeNetworkHost `
    -Network "Internal" `
    -Hostname "database" `
    -MACAddress "00:11:22:33:44:66" `
    -IPAddress "10.10.0.20" `
    -Description "Primary database server"

# Modify a reservation
Set-VergeNetworkHost -Network "Internal" -Hostname "server01" -IPAddress "10.10.0.15"

# Remove a reservation
Remove-VergeNetworkHost -Network "Internal" -Hostname "old-server"

# Bulk create reservations from CSV
<#
CSV format (hosts.csv):
Hostname,MACAddress,IPAddress,Description
web01,00:11:22:33:44:01,10.10.0.11,Web Server 1
web02,00:11:22:33:44:02,10.10.0.12,Web Server 2
db01,00:11:22:33:44:03,10.10.0.21,Database Server
#>
Import-Csv "hosts.csv" | ForEach-Object {
    New-VergeNetworkHost `
        -Network "Internal" `
        -Hostname $_.Hostname `
        -MACAddress $_.MACAddress `
        -IPAddress $_.IPAddress `
        -Description $_.Description
}

#endregion

#region Firewall Rules
# ============================================================================
# MANAGING FIREWALL RULES
# ============================================================================

# List firewall rules on a network
Get-VergeNetworkRule -Network "External"

# List only incoming rules
Get-VergeNetworkRule -Network "External" -Direction Incoming

# Create a rule to allow HTTPS traffic
New-VergeNetworkRule `
    -Network "External" `
    -Description "Allow HTTPS" `
    -Action Accept `
    -Direction Incoming `
    -Protocol TCP `
    -DestinationPort 443

# Create a rule to allow SSH from specific IP
New-VergeNetworkRule `
    -Network "External" `
    -Description "Allow SSH from Admin" `
    -Action Accept `
    -Direction Incoming `
    -Protocol TCP `
    -SourceIP "10.0.0.50" `
    -DestinationPort 22

# Create a rule to allow a port range
New-VergeNetworkRule `
    -Network "External" `
    -Description "Allow custom app ports" `
    -Action Accept `
    -Direction Incoming `
    -Protocol TCP `
    -DestinationPort "8000-8100"

# Create a rule to allow ICMP (ping)
New-VergeNetworkRule `
    -Network "External" `
    -Description "Allow ping" `
    -Action Accept `
    -Direction Incoming `
    -Protocol ICMP

# Create a deny rule (for explicit blocking)
New-VergeNetworkRule `
    -Network "External" `
    -Description "Block Telnet" `
    -Action Reject `
    -Direction Incoming `
    -Protocol TCP `
    -DestinationPort 23

# Modify an existing rule
Set-VergeNetworkRule -Key 123 -Description "Updated rule description"

# Remove a rule
Remove-VergeNetworkRule -Network "External" -Key 123

# IMPORTANT: Apply rules after making changes
Invoke-VergeNetworkApply -Network "External"

#endregion

#region DNS Management
# ============================================================================
# MANAGING DNS ZONES AND RECORDS
# ============================================================================

# List DNS zones on a network
Get-VergeDNSZone -Network "Internal"

# List DNS records in a zone
Get-VergeDNSRecord -Network "Internal"

# Create an A record
New-VergeDNSRecord `
    -Network "Internal" `
    -Name "webapp" `
    -Type A `
    -Value "10.10.0.100"

# Create a CNAME record
New-VergeDNSRecord `
    -Network "Internal" `
    -Name "www" `
    -Type CNAME `
    -Value "webapp.internal.local"

# Remove a DNS record
Remove-VergeDNSRecord -Network "Internal" -Name "old-record" -Type A

# After DNS changes, apply to network
Invoke-VergeNetworkApply -Network "Internal"

#endregion

#region Network Aliases (IP Groups)
# ============================================================================
# MANAGING NETWORK ALIASES FOR FIREWALL RULES
# ============================================================================

# List network aliases
Get-VergeNetworkAlias -Network "External"

# Create an alias for admin workstations
New-VergeNetworkAlias `
    -Network "External" `
    -Name "Admin-Workstations" `
    -Type IP `
    -Members @("10.0.0.50", "10.0.0.51", "10.0.0.52")

# Create an alias for a subnet
New-VergeNetworkAlias `
    -Network "External" `
    -Name "Dev-Subnet" `
    -Type IP `
    -Members @("10.10.0.0/24")

# Use alias in a firewall rule
New-VergeNetworkRule `
    -Network "External" `
    -Description "Allow SSH from admins" `
    -Action Accept `
    -Direction Incoming `
    -Protocol TCP `
    -SourceAlias "Admin-Workstations" `
    -DestinationPort 22

# Remove an alias
Remove-VergeNetworkAlias -Network "External" -Name "Old-Alias"

#endregion

#region Network Diagnostics
# ============================================================================
# NETWORK DIAGNOSTICS AND STATISTICS
# ============================================================================

# Get network statistics (traffic, packets)
Get-VergeNetworkStatistics -Network "External"

# Get network diagnostics (ARP table, DHCP leases)
Get-VergeNetworkDiagnostics -Network "Internal"

# View DHCP lease information
$diag = Get-VergeNetworkDiagnostics -Network "Internal"
$diag.DHCPLeases | Format-Table

# View ARP table
$diag.ARPTable | Format-Table

#endregion

#region Common Workflows
# ============================================================================
# COMMON NETWORK CONFIGURATION WORKFLOWS
# ============================================================================

# Workflow: Set up a complete web server network
$webNetworkName = "Web-Tier"

# 1. Create the network
$webNet = New-VergeNetwork `
    -Name $webNetworkName `
    -Type Internal `
    -NetworkAddress "10.30.0.0/24" `
    -IPAddress "10.30.0.1" `
    -Gateway "10.30.0.1" `
    -InterfaceNetwork "External" `
    -DHCPEnabled `
    -DHCPStart "10.30.0.100" `
    -DHCPStop "10.30.0.200" `
    -Domain "web.local" `
    -PassThru

# 2. Add firewall rules
@(
    @{ Desc = "Allow HTTP";  Port = 80 }
    @{ Desc = "Allow HTTPS"; Port = 443 }
) | ForEach-Object {
    New-VergeNetworkRule `
        -Network $webNetworkName `
        -Description $_.Desc `
        -Action Accept `
        -Direction Incoming `
        -Protocol TCP `
        -DestinationPort $_.Port
}

# 3. Apply rules and start network
Invoke-VergeNetworkApply -Network $webNetworkName
Start-VergeNetwork -Name $webNetworkName

Write-Host "Web tier network '$webNetworkName' is ready!"

# Workflow: Export network configuration for documentation
$network = Get-VergeNetwork -Name "Internal"
$rules = Get-VergeNetworkRule -Network "Internal"
$hosts = Get-VergeNetworkHost -Network "Internal"

[PSCustomObject]@{
    Name = $network.Name
    Type = $network.Type
    Network = $network.Network
    Gateway = $network.Gateway
    DHCP = if ($network.DHCPEnabled) { "$($network.DHCPStart) - $($network.DHCPStop)" } else { "Disabled" }
    RuleCount = $rules.Count
    HostCount = $hosts.Count
} | Format-List

#endregion
