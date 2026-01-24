# Networking Cmdlets

Cmdlets for managing virtual networks, firewall rules, DHCP, and DNS.

## Overview

Network cmdlets provide comprehensive control over VergeOS virtual networking including network creation, firewall rule management, DHCP configuration, and DNS management.

## Network Management

### Get-VergeNetwork

Retrieves virtual networks.

**Syntax:**
```powershell
Get-VergeNetwork [-Name <String>] [-Type <String>] [-PowerState <String>]
Get-VergeNetwork -Key <Int32>
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Name` | String | No | Network name (supports wildcards) |
| `-Key` | Int32 | No | Unique network identifier |
| `-Type` | String | No | Internal, External, DMZ |
| `-PowerState` | String | No | Running, Stopped |

**Examples:**

```powershell
# List all networks
Get-VergeNetwork

# Filter by type
Get-VergeNetwork -Type Internal

# Find networks with DHCP
Get-VergeNetwork | Where-Object { $_.DHCPEnabled }
```

---

### New-VergeNetwork

Creates a new virtual network.

**Syntax:**
```powershell
New-VergeNetwork -Name <String> [-Type <String>] [-NetworkAddress <String>]
    [-IPAddress <String>] [-Gateway <String>] [-DHCPEnabled] [-DHCPStart <String>]
    [-DHCPStop <String>] [-DNSServers <String[]>] [-Domain <String>]
    [-InterfaceNetwork <String>] [-PowerOn] [-PassThru]
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Name` | String | Yes | Network name |
| `-Type` | String | No | Internal, External, DMZ (default: Internal) |
| `-NetworkAddress` | String | No | CIDR notation (e.g., "10.0.0.0/24") |
| `-IPAddress` | String | No | Router IP within the network |
| `-Gateway` | String | No | Default gateway for DHCP clients |
| `-DHCPEnabled` | Switch | No | Enable DHCP server |
| `-DHCPStart` | String | No | DHCP pool start IP |
| `-DHCPStop` | String | No | DHCP pool end IP |
| `-DNSServers` | String[] | No | DNS servers for DHCP |
| `-Domain` | String | No | Network domain name |
| `-InterfaceNetwork` | String | No | Uplink network (for routing) |
| `-PowerOn` | Switch | No | Start network after creation |
| `-PassThru` | Switch | No | Return created network |

**Examples:**

```powershell
# Create a basic internal network
New-VergeNetwork -Name "Dev-Network" -NetworkAddress "10.10.0.0/24"

# Create network with DHCP
New-VergeNetwork -Name "App-Network" -NetworkAddress "10.20.0.0/24" `
    -IPAddress "10.20.0.1" -Gateway "10.20.0.1" `
    -DHCPEnabled -DHCPStart "10.20.0.100" -DHCPStop "10.20.0.200" `
    -DNSServers @("8.8.8.8", "8.8.4.4") -PowerOn

# Create routed network
New-VergeNetwork -Name "DMZ" -Type DMZ -NetworkAddress "172.16.0.0/24" `
    -IPAddress "172.16.0.1" -InterfaceNetwork "External" -PowerOn -PassThru
```

---

### Set-VergeNetwork

Modifies network configuration.

**Syntax:**
```powershell
Set-VergeNetwork -Name <String> [-DHCPStart <String>] [-DHCPStop <String>]
    [-DNSServers <String[]>] [-PassThru]
```

**Examples:**

```powershell
# Modify DHCP range
Set-VergeNetwork -Name "Internal" -DHCPStart "10.0.0.50" -DHCPStop "10.0.0.250"
```

---

### Remove-VergeNetwork

Deletes a virtual network.

**Syntax:**
```powershell
Remove-VergeNetwork -Name <String> [-Confirm]
```

> **Note:** Network must be stopped before removal.

---

### Start-VergeNetwork / Stop-VergeNetwork / Restart-VergeNetwork

Power management for networks.

```powershell
Start-VergeNetwork -Name "Dev-Network"
Stop-VergeNetwork -Name "Dev-Network"
Restart-VergeNetwork -Name "Dev-Network"
```

---

### Invoke-VergeNetworkApply

Applies pending firewall rule changes to a network.

**Syntax:**
```powershell
Invoke-VergeNetworkApply -Network <String>
```

> **Important:** Always call this after adding, modifying, or removing firewall rules.

**Examples:**

```powershell
# Add rules then apply
New-VergeNetworkRule -Network "External" -Name "Allow-HTTPS" -Action Accept -Direction Incoming -Protocol TCP -DestinationPorts "443"
Invoke-VergeNetworkApply -Network "External"
```

## Firewall Rules

### Get-VergeNetworkRule

Lists firewall rules on a network.

**Syntax:**
```powershell
Get-VergeNetworkRule -Network <String> [-Direction <String>]
```

**Examples:**

```powershell
# List all rules
Get-VergeNetworkRule -Network "External"

# List incoming rules only
Get-VergeNetworkRule -Network "External" -Direction Incoming
```

---

### New-VergeNetworkRule

Creates a firewall rule.

**Syntax:**
```powershell
New-VergeNetworkRule -Network <String> -Name <String> -Action <String>
    -Direction <String> -Protocol <String> [-SourceIP <String>]
    [-DestinationIP <String>] [-DestinationPorts <String>] [-Description <String>]
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Network` | String | Yes | Target network |
| `-Name` | String | Yes | Rule name |
| `-Action` | String | Yes | Accept, Reject, Drop |
| `-Direction` | String | Yes | Incoming, Outgoing |
| `-Protocol` | String | Yes | TCP, UDP, ICMP, Any |
| `-SourceIP` | String | No | Source IP or CIDR |
| `-DestinationIP` | String | No | Destination IP or CIDR |
| `-DestinationPorts` | String | No | Port or range (e.g., "443" or "8000-8100") |
| `-Description` | String | No | Rule description |

**Examples:**

```powershell
# Allow HTTPS
New-VergeNetworkRule -Network "External" -Name "Allow-HTTPS" `
    -Action Accept -Direction Incoming -Protocol TCP -DestinationPorts "443"

# Allow SSH from specific IP
New-VergeNetworkRule -Network "External" -Name "Allow-SSH-Admin" `
    -Action Accept -Direction Incoming -Protocol TCP `
    -SourceIP "10.0.0.50" -DestinationPorts "22"

# Allow port range
New-VergeNetworkRule -Network "External" -Name "Allow-App-Ports" `
    -Action Accept -Direction Incoming -Protocol TCP `
    -DestinationPorts "8000-8100"

# Allow ICMP (ping)
New-VergeNetworkRule -Network "External" -Name "Allow-Ping" `
    -Action Accept -Direction Incoming -Protocol ICMP

# Block a port
New-VergeNetworkRule -Network "External" -Name "Block-Telnet" `
    -Action Reject -Direction Incoming -Protocol TCP `
    -DestinationPorts "23"

# Apply changes
Invoke-VergeNetworkApply -Network "External"
```

---

### Set-VergeNetworkRule

Modifies an existing firewall rule.

---

### Remove-VergeNetworkRule

Deletes a firewall rule.

```powershell
Remove-VergeNetworkRule -Network "External" -Key 123
Invoke-VergeNetworkApply -Network "External"
```

## DHCP Host Reservations

### Get-VergeNetworkHost

Lists DHCP host reservations.

```powershell
Get-VergeNetworkHost -Network "Internal"
```

---

### New-VergeNetworkHost

Creates a DHCP reservation.

**Syntax:**
```powershell
New-VergeNetworkHost -Network <String> -Hostname <String> -MACAddress <String>
    -IPAddress <String> [-Description <String>]
```

**Examples:**

```powershell
# Create a reservation
New-VergeNetworkHost -Network "Internal" -Hostname "server01" `
    -MACAddress "00:11:22:33:44:55" -IPAddress "10.10.0.10"

# Bulk import from CSV
Import-Csv "hosts.csv" | ForEach-Object {
    New-VergeNetworkHost -Network "Internal" -Hostname $_.Hostname `
        -MACAddress $_.MAC -IPAddress $_.IP
}
```

---

### Set-VergeNetworkHost

Modifies a DHCP reservation.

---

### Remove-VergeNetworkHost

Deletes a DHCP reservation.

## Network Aliases (IP Groups)

### Get-VergeNetworkAlias

Lists IP aliases/groups that can be used in firewall rules.

---

### New-VergeNetworkAlias

Creates an IP alias for use in firewall rules.

**Syntax:**
```powershell
New-VergeNetworkAlias -Network <String> -Name <String> -Type <String> -Members <String[]>
```

**Examples:**

```powershell
# Create alias for admin workstations
New-VergeNetworkAlias -Network "External" -Name "Admin-Workstations" `
    -Type IP -Members @("10.0.0.50", "10.0.0.51", "10.0.0.52")

# Use alias in rule
New-VergeNetworkRule -Network "External" -Name "Allow-SSH-Admins" `
    -Action Accept -Direction Incoming -Protocol TCP `
    -SourceIP "alias:Admin-Workstations" -DestinationPorts "22"
```

---

### Remove-VergeNetworkAlias

Deletes an IP alias.

## DNS Management

### Get-VergeDNSZone

Lists DNS zones on a network.

---

### Get-VergeDNSRecord

Lists DNS records.

```powershell
Get-VergeDNSRecord -Network "Internal"
```

---

### New-VergeDNSRecord

Creates a DNS record.

**Syntax:**
```powershell
New-VergeDNSRecord -Network <String> -Name <String> -Type <String> -Value <String>
```

**Examples:**

```powershell
# Create A record
New-VergeDNSRecord -Network "Internal" -Name "webapp" -Type A -Value "10.10.0.100"

# Create CNAME record
New-VergeDNSRecord -Network "Internal" -Name "www" -Type CNAME -Value "webapp.internal.local"

# Apply changes
Invoke-VergeNetworkApply -Network "Internal"
```

---

### Remove-VergeDNSRecord

Deletes a DNS record.

## Diagnostics

### Get-VergeNetworkStatistics

Retrieves network traffic statistics.

```powershell
Get-VergeNetworkStatistics -Network "External"
```

---

### Get-VergeNetworkDiagnostics

Retrieves ARP table and DHCP lease information.

```powershell
$diag = Get-VergeNetworkDiagnostics -Network "Internal"
$diag.DHCPLeases | Format-Table
$diag.ARPTable | Format-Table
```

## Common Workflows

### Complete Network Setup

```powershell
$networkName = "Web-Tier"

# 1. Create network with DHCP
$network = New-VergeNetwork -Name $networkName -Type Internal `
    -NetworkAddress "10.30.0.0/24" -IPAddress "10.30.0.1" -Gateway "10.30.0.1" `
    -InterfaceNetwork "External" -DHCPEnabled `
    -DHCPStart "10.30.0.100" -DHCPStop "10.30.0.200" -PassThru

# 2. Add firewall rules
New-VergeNetworkRule -Network $networkName -Name "Allow-HTTP" `
    -Action Accept -Direction Incoming -Protocol TCP -DestinationPorts "80"
New-VergeNetworkRule -Network $networkName -Name "Allow-HTTPS" `
    -Action Accept -Direction Incoming -Protocol TCP -DestinationPorts "443"

# 3. Apply rules and start
Invoke-VergeNetworkApply -Network $networkName
Start-VergeNetwork -Name $networkName
```

### Export Network Configuration

```powershell
$network = Get-VergeNetwork -Name "Internal"
$rules = Get-VergeNetworkRule -Network "Internal"
$hosts = Get-VergeNetworkHost -Network "Internal"

[PSCustomObject]@{
    Name = $network.Name
    Type = $network.Type
    Network = $network.Network
    DHCP = "$($network.DHCPStart) - $($network.DHCPStop)"
    RuleCount = $rules.Count
    HostCount = $hosts.Count
} | Format-List
```
