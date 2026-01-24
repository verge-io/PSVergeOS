# Connection Cmdlets

Cmdlets for establishing and managing connections to VergeOS systems.

## Overview

Before using any other PSVergeOS cmdlets, you must establish a connection to a VergeOS system using `Connect-VergeOS`. The module supports multiple simultaneous connections for managing different environments.

## Cmdlets

### Connect-VergeOS

Establishes a connection to a VergeOS system.

**Syntax:**
```powershell
Connect-VergeOS -Server <String> -Credential <PSCredential> [-SkipCertificateCheck] [-PassThru]
Connect-VergeOS -Server <String> -Token <String> [-SkipCertificateCheck] [-PassThru]
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Server` | String | Yes | Hostname or IP address of the VergeOS system |
| `-Credential` | PSCredential | Yes* | Username and password for authentication |
| `-Token` | String | Yes* | API token for non-interactive authentication |
| `-SkipCertificateCheck` | Switch | No | Skip TLS certificate validation (self-signed certs) |
| `-PassThru` | Switch | No | Return the connection object |

*Either `-Credential` or `-Token` is required.

**Examples:**

```powershell
# Interactive login with credential prompt
Connect-VergeOS -Server "vergeos.company.com" -Credential (Get-Credential)

# Token-based login for automation
Connect-VergeOS -Server "vergeos.company.com" -Token $env:VERGE_TOKEN

# Self-signed certificate environment
Connect-VergeOS -Server "vergeos.local" -Token $env:VERGE_TOKEN -SkipCertificateCheck

# Connect and store the connection object
$prod = Connect-VergeOS -Server "prod.vergeos.local" -Credential $cred -PassThru
```

---

### Disconnect-VergeOS

Closes a connection to a VergeOS system.

**Syntax:**
```powershell
Disconnect-VergeOS [-Server <String>] [-All]
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Server` | String | No | Server to disconnect from (default: current default) |
| `-All` | Switch | No | Disconnect from all servers |

**Examples:**

```powershell
# Disconnect from default server
Disconnect-VergeOS

# Disconnect from a specific server
Disconnect-VergeOS -Server "dev.vergeos.local"

# Disconnect from all servers
Disconnect-VergeOS -All
```

---

### Get-VergeConnection

Displays active connections.

**Syntax:**
```powershell
Get-VergeConnection [-Default] [-Server <String>]
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Default` | Switch | No | Return only the default connection |
| `-Server` | String | No | Return connection for a specific server |

**Examples:**

```powershell
# List all connections
Get-VergeConnection

# Get the default connection
Get-VergeConnection -Default

# Display connection details in a table
Get-VergeConnection | Format-Table Server, Username, VergeOSVersion, ConnectedAt, IsDefault
```

**Output Properties:**

| Property | Description |
|----------|-------------|
| `Server` | VergeOS server hostname |
| `Username` | Authenticated username |
| `VergeOSVersion` | VergeOS software version |
| `ConnectedAt` | Connection timestamp |
| `IsDefault` | Whether this is the default connection |
| `IsConnected` | Connection status |

---

### Set-VergeConnection

Changes the default connection when multiple servers are connected.

**Syntax:**
```powershell
Set-VergeConnection -Server <String>
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Server` | String | Yes | Server to set as default |

**Examples:**

```powershell
# Connect to multiple servers
Connect-VergeOS -Server "prod.vergeos.local" -Credential $cred
Connect-VergeOS -Server "dev.vergeos.local" -Credential $cred

# Switch default to production
Set-VergeConnection -Server "prod.vergeos.local"

# Verify the change
Get-VergeConnection -Default
```

## Multi-Server Management

PSVergeOS supports managing multiple VergeOS systems simultaneously:

```powershell
# Connect to multiple environments
$prod = Connect-VergeOS -Server "prod.vergeos.local" -Token $env:PROD_TOKEN -PassThru
$dev = Connect-VergeOS -Server "dev.vergeos.local" -Token $env:DEV_TOKEN -PassThru

# Query specific server using -Server parameter
$prodVMs = Get-VergeVM -Server $prod
$devVMs = Get-VergeVM -Server $dev

# Compare environments
Write-Host "Production VMs: $($prodVMs.Count)"
Write-Host "Development VMs: $($devVMs.Count)"
```

## Authentication Methods

### Interactive Credentials

Best for manual administration:

```powershell
Connect-VergeOS -Server "vergeos.company.com" -Credential (Get-Credential)
```

### API Token

Best for automation and scripts:

```powershell
# Store token in environment variable (recommended)
$env:VERGE_TOKEN = "your-api-token"
Connect-VergeOS -Server "vergeos.company.com" -Token $env:VERGE_TOKEN
```

### Stored Credentials

For scheduled tasks, use SecretManagement:

```powershell
# Store credential (one-time setup)
Set-Secret -Name "VergeOS-Prod" -Secret (Get-Credential)

# Use stored credential
$cred = Get-Secret -Name "VergeOS-Prod"
Connect-VergeOS -Server "vergeos.company.com" -Credential $cred
```

## Certificate Handling

For environments with self-signed certificates:

```powershell
Connect-VergeOS -Server "vergeos.local" -Credential $cred -SkipCertificateCheck
```

> **Note:** Use `-SkipCertificateCheck` only in trusted environments. For production, configure proper TLS certificates.
