# System Administration Cmdlets

Cmdlets for managing clusters, nodes, and system settings.

## Overview

System cmdlets provide administration of VergeOS infrastructure including cluster management, node operations, and system configuration.

## Version Information

### Get-VergeVersion

Retrieves VergeOS version information.

**Syntax:**
```powershell
Get-VergeVersion
```

**Examples:**

```powershell
# Get version info
$version = Get-VergeVersion
Write-Host "VergeOS: $($version.VergeOSVersion)"
Write-Host "Kernel: $($version.KernelVersion)"
Write-Host "vSAN: $($version.vSANVersion)"

# Version check in scripts
$ver = Get-VergeVersion
$major = [int]($ver.VergeOSVersion -split '\.')[0]
if ($major -lt 26) {
    Write-Warning "Requires VergeOS 26.0 or later"
}
```

## Cluster Management

### Get-VergeCluster

Lists clusters.

**Syntax:**
```powershell
Get-VergeCluster [-Name <String>]
```

**Examples:**

```powershell
# List all clusters
Get-VergeCluster

# View cluster resources
Get-VergeCluster | Format-Table Name, Status, OnlineNodes, UsedCores, OnlineCores, UsedRAM, OnlineRAM

# Check capacity
Get-VergeCluster | ForEach-Object {
    $cpuPct = [math]::Round(($_.UsedCores / $_.OnlineCores) * 100, 1)
    $ramPct = [math]::Round(($_.UsedRAM / $_.OnlineRAM) * 100, 1)
    [PSCustomObject]@{
        Cluster = $_.Name
        CPUUsed = "$($_.UsedCores)/$($_.OnlineCores) ($cpuPct%)"
        RAMUsed = "$([math]::Round($_.UsedRAM/1024, 1))/$([math]::Round($_.OnlineRAM/1024, 1)) GB ($ramPct%)"
    }
} | Format-Table
```

---

### New-VergeCluster

Creates a new cluster.

**Syntax:**
```powershell
New-VergeCluster -Name <String> [-Description <String>] [-Compute]
    [-NestedVirtualization] [-MaxRAMPerVM <Int32>] [-MaxCoresPerVM <Int32>] [-PassThru]
```

**Examples:**

```powershell
# Create a compute cluster
New-VergeCluster -Name "Production" -Description "Production workloads" -Compute

# Cluster for nested virtualization
New-VergeCluster -Name "Lab" -Compute -NestedVirtualization -PassThru
```

---

### Set-VergeCluster

Modifies cluster settings.

**Examples:**

```powershell
# Update resource limits
Set-VergeCluster -Name "Production" -MaxRAMPerVM 262144 -MaxCoresPerVM 64

# Enable nested virtualization
Set-VergeCluster -Name "Development" -NestedVirtualization $true
```

---

### Remove-VergeCluster

Deletes a cluster.

> **Note:** Cluster must have no nodes or VMs before deletion.

## Node Management

### Get-VergeNode

Lists nodes.

**Syntax:**
```powershell
Get-VergeNode [-Name <String>] [-Cluster <String>] [-MaintenanceMode <Boolean>]
```

**Examples:**

```powershell
# List all nodes
Get-VergeNode

# View node details
Get-VergeNode | Format-Table Name, Status, Cluster, Cores, @{N='RAM_GB';E={[math]::Round($_.RAM/1024,1)}}, MaintenanceMode

# Find nodes needing restart
Get-VergeNode | Where-Object NeedsRestart | Format-Table Name, RestartReason

# Nodes in a specific cluster
Get-VergeNode -Cluster "Production"
```

---

### Enable-VergeNodeMaintenance

Puts a node into maintenance mode, migrating VMs off.

**Syntax:**
```powershell
Enable-VergeNodeMaintenance -Name <String> [-WhatIf]
```

**Examples:**

```powershell
# Preview maintenance
Enable-VergeNodeMaintenance -Name "node2" -WhatIf

# Enable maintenance mode
Enable-VergeNodeMaintenance -Name "node2"
```

---

### Disable-VergeNodeMaintenance

Takes a node out of maintenance mode.

```powershell
Disable-VergeNodeMaintenance -Name "node2"
```

---

### Restart-VergeNode

Performs a safe maintenance reboot with VM migration.

**Syntax:**
```powershell
Restart-VergeNode -Name <String> [-WhatIf]
```

**Examples:**

```powershell
# Preview reboot
Restart-VergeNode -Name "node2" -WhatIf

# Perform maintenance reboot
Restart-VergeNode -Name "node2"
```

## Hardware Discovery

### Get-VergeNodeDevice

Lists hardware devices (PCI, USB, GPU).

**Syntax:**
```powershell
Get-VergeNodeDevice [-Node <String>] -DeviceType <String> [-DeviceClass <String>]
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Node` | String | No | Filter by node |
| `-DeviceType` | String | Yes | PCI, USB, GPU |
| `-DeviceClass` | String | No | Filter by device class |

**Examples:**

```powershell
# List all GPUs
Get-VergeNodeDevice -DeviceType GPU | Format-Table Node, Name, Vendor

# List network controllers
Get-VergeNodeDevice -DeviceType PCI -DeviceClass "Network controller" |
    Format-Table Node, Name, Vendor, Driver

# USB devices on specific node
Get-VergeNodeDevice -Node "node1" -DeviceType USB

# Find SR-IOV capable devices
Get-VergeNodeDevice -DeviceType PCI |
    Where-Object { $_.SRIOVTotalVFs -gt 0 } |
    Format-Table Node, Name, SRIOVTotalVFs
```

---

### Get-VergeNodeDriver

Lists custom drivers installed on nodes.

**Syntax:**
```powershell
Get-VergeNodeDriver [-Node <String>] [-Status <String>]
```

**Examples:**

```powershell
# List all drivers
Get-VergeNodeDriver

# Find NVIDIA drivers
Get-VergeNodeDriver | Where-Object DriverName -like "*nvidia*"

# Check driver status
Get-VergeNodeDriver | Format-Table Node, DriverName, Status, StatusInfo
```

## System Statistics

### Get-VergeSystemStatistics

Retrieves system dashboard statistics.

**Syntax:**
```powershell
Get-VergeSystemStatistics
```

**Examples:**

```powershell
# Quick health check
$stats = Get-VergeSystemStatistics
Write-Host "VMs: $($stats.VMsOnline) running / $($stats.VMsTotal) total"
Write-Host "Nodes: $($stats.NodesOnline) online / $($stats.NodesTotal) total"
Write-Host "Alarms: $($stats.AlarmsTotal) ($($stats.AlarmsError) errors)"

# Check for issues
$stats = Get-VergeSystemStatistics
if ($stats.NodesOnline -lt $stats.NodesTotal) {
    Write-Warning "Not all nodes online"
}
if ($stats.AlarmsError -gt 0) {
    Write-Warning "$($stats.AlarmsError) error alarms present"
}
```

## System Settings

### Get-VergeSystemSetting

Lists system configuration settings.

**Syntax:**
```powershell
Get-VergeSystemSetting [-Key <String>]
```

**Examples:**

```powershell
# List all settings
Get-VergeSystemSetting | Format-Table Key, Value, DefaultValue

# Find specific setting
Get-VergeSystemSetting -Key "cloud_name"

# Find modified settings
Get-VergeSystemSetting | Where-Object IsModified | Format-Table Key, Value, DefaultValue
```

## License Information

### Get-VergeLicense

Retrieves license information.

**Syntax:**
```powershell
Get-VergeLicense
```

**Examples:**

```powershell
# Check license
$license = Get-VergeLicense | Select-Object -First 1
Write-Host "License: $($license.Name)"
Write-Host "Valid: $($license.IsValid)"
Write-Host "Expires: $($license.ValidUntil)"

# Check expiration
if ($license.ValidUntil) {
    $daysLeft = ($license.ValidUntil - (Get-Date)).Days
    if ($daysLeft -lt 30) {
        Write-Warning "License expires in $daysLeft days"
    }
}
```

## Tag Categories

Tag categories organize tags and define which resource types can be tagged.

### Get-VergeTagCategory

Lists tag categories.

**Syntax:**
```powershell
Get-VergeTagCategory [-Name <String>] [-Key <Int32>]
```

**Examples:**

```powershell
# List all tag categories
Get-VergeTagCategory

# Get a specific category
Get-VergeTagCategory -Name "Environment"

# View which resources can be tagged
Get-VergeTagCategory | Format-Table Name, TaggableVMs, TaggableNetworks, TaggableTenants, SingleTagSelection
```

---

### New-VergeTagCategory

Creates a new tag category.

**Syntax:**
```powershell
New-VergeTagCategory -Name <String> [-Description <String>] [-SingleTagSelection]
    [-TaggableVMs] [-TaggableNetworks] [-TaggableTenants] [-TaggableNodes]
    [-TaggableClusters] [-TaggableUsers] [-TaggableGroups] [-PassThru]
```

**Examples:**

```powershell
# Create environment category (single tag per resource)
New-VergeTagCategory -Name "Environment" `
    -Description "Deployment environment" `
    -TaggableVMs -TaggableNetworks -TaggableTenants `
    -SingleTagSelection

# Create application category (multiple tags allowed)
New-VergeTagCategory -Name "Application" `
    -Description "Application tier tags" `
    -TaggableVMs -PassThru
```

---

### Set-VergeTagCategory

Modifies a tag category.

**Syntax:**
```powershell
Set-VergeTagCategory -Name <String> [-Description <String>] [-TaggableVMs <Boolean>]
    [-TaggableNetworks <Boolean>] [-PassThru]
```

**Examples:**

```powershell
# Enable additional resource types
Set-VergeTagCategory -Name "Environment" -TaggableNodes $true -TaggableClusters $true

# Update description
Set-VergeTagCategory -Name "Application" -Description "Application and service identification"
```

---

### Remove-VergeTagCategory

Deletes a tag category.

> **Note:** Category must have no tags before deletion.

**Syntax:**
```powershell
Remove-VergeTagCategory -Name <String> [-Confirm:$false]
```

**Examples:**

```powershell
# Remove an empty category
Remove-VergeTagCategory -Name "UnusedCategory"

# Force removal without confirmation
Remove-VergeTagCategory -Name "OldCategory" -Confirm:$false
```

## Tags

Tags are labels within categories that can be assigned to resources.

### Get-VergeTag

Lists tags.

**Syntax:**
```powershell
Get-VergeTag [-Name <String>] [-Key <Int32>] [-Category <Object>]
```

**Examples:**

```powershell
# List all tags
Get-VergeTag

# List tags in a category
Get-VergeTag -Category "Environment"

# Find tags by name pattern
Get-VergeTag -Name "Prod*"

# Pipeline from category
Get-VergeTagCategory -Name "Environment" | Get-VergeTag

# View tags with category info
Get-VergeTag | Format-Table Name, CategoryName, Description
```

---

### New-VergeTag

Creates a new tag within a category.

**Syntax:**
```powershell
New-VergeTag -Name <String> -Category <Object> [-Description <String>] [-PassThru]
```

**Examples:**

```powershell
# Create environment tags
New-VergeTag -Name "Production" -Category "Environment" -Description "Production workloads"
New-VergeTag -Name "Development" -Category "Environment" -Description "Development workloads"

# Create and return the tag
$tag = New-VergeTag -Name "WebServer" -Category "Application" -PassThru
```

---

### Set-VergeTag

Modifies a tag.

**Syntax:**
```powershell
Set-VergeTag -Name <String> [-Description <String>] [-PassThru]
```

**Examples:**

```powershell
# Update description
Set-VergeTag -Name "Production" -Description "Production environment - critical workloads"
```

---

### Remove-VergeTag

Deletes a tag and all its assignments.

**Syntax:**
```powershell
Remove-VergeTag -Name <String> [-Confirm:$false]
```

**Examples:**

```powershell
# Remove a tag
Remove-VergeTag -Name "OldTag"

# Remove all tags in a category
Get-VergeTag -Category "OldCategory" | Remove-VergeTag -Confirm:$false
```

## Tag Members

Tag members represent the assignment of tags to resources.

### Get-VergeTagMember

Lists tag assignments.

**Syntax:**
```powershell
Get-VergeTagMember -Tag <Object> [-ResourceType <String>]
Get-VergeTagMember -Key <Int32>
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Tag` | Object | Yes* | Tag name, key, or object |
| `-ResourceType` | String | No | Filter by type: vms, vnets, tenants, etc. |
| `-Key` | Int32 | Yes* | Tag member assignment key |

**Examples:**

```powershell
# List all resources with a tag
Get-VergeTagMember -Tag "Production"

# List only VMs with a tag
Get-VergeTagMember -Tag "Production" -ResourceType vms

# Pipeline from tag
Get-VergeTag -Name "Production" | Get-VergeTagMember

# View assignments
Get-VergeTagMember -Tag "Production" | Format-Table TagName, ResourceType, ResourceKey, ResourceRef

# Count resources per tag
Get-VergeTag -Category "Environment" | ForEach-Object {
    $members = Get-VergeTagMember -Tag $_.Name
    [PSCustomObject]@{
        Tag   = $_.Name
        Count = $members.Count
    }
} | Format-Table
```

---

### Add-VergeTagMember

Assigns a tag to a resource.

**Syntax:**
```powershell
Add-VergeTagMember -Tag <Object> -VM <Object> [-PassThru]
Add-VergeTagMember -Tag <Object> -Network <Object> [-PassThru]
Add-VergeTagMember -Tag <Object> -Tenant <Object> [-PassThru]
Add-VergeTagMember -Tag <Object> -ResourceType <String> -ResourceKey <Int32> [-PassThru]
```

**Examples:**

```powershell
# Tag a VM by name
Add-VergeTagMember -Tag "Production" -VM "WebServer01"

# Tag via pipeline from Get-VergeVM
Get-VergeVM -Name "Web*" | Add-VergeTagMember -Tag "WebServer"

# Tag a network
Add-VergeTagMember -Tag "Production" -Network "DMZ"

# Tag a tenant
Add-VergeTagMember -Tag "Production" -Tenant "CustomerA"

# Generic resource tagging
Add-VergeTagMember -Tag "Production" -ResourceType vms -ResourceKey 123

# Bulk tag all VMs in a cluster
Get-VergeVM -Cluster "Prod-Cluster" | ForEach-Object {
    Add-VergeTagMember -Tag "Production" -VM $_
}
```

---

### Remove-VergeTagMember

Removes a tag from a resource.

**Syntax:**
```powershell
Remove-VergeTagMember -Key <Int32> [-Confirm:$false]
Remove-VergeTagMember -Tag <Object> -VM <Object> [-Confirm:$false]
Remove-VergeTagMember -Tag <Object> -Network <Object> [-Confirm:$false]
Remove-VergeTagMember -TagMember <Object> [-Confirm:$false]
```

**Examples:**

```powershell
# Remove tag from VM by specifying both
Remove-VergeTagMember -Tag "Development" -VM "WebServer01"

# Remove by tag member key
Remove-VergeTagMember -Key 42 -Confirm:$false

# Remove all assignments for a tag via pipeline
Get-VergeTagMember -Tag "Staging" | Remove-VergeTagMember -Confirm:$false

# Remove without confirmation
Remove-VergeTagMember -Tag "Production" -Network "OldNetwork" -Confirm:$false
```

## Common Workflows

### Tagging Workflow

```powershell
# 1. Create tag structure
New-VergeTagCategory -Name "Environment" -TaggableVMs -SingleTagSelection
New-VergeTag -Name "Production" -Category "Environment"
New-VergeTag -Name "Development" -Category "Environment"

# 2. Tag resources
Get-VergeVM -Name "Prod-*" | ForEach-Object {
    Add-VergeTagMember -Tag "Production" -VM $_
}

# 3. Query by tag
Get-VergeTagMember -Tag "Production" -ResourceType vms

# 4. Generate report
Get-VergeTag -Category "Environment" | ForEach-Object {
    $count = (Get-VergeTagMember -Tag $_.Name -ResourceType vms).Count
    [PSCustomObject]@{ Environment = $_.Name; VMCount = $count }
} | Format-Table
```

### System Health Check

```powershell
function Get-VergeHealthReport {
    $report = @{}

    # Version
    $version = Get-VergeVersion
    $report['Version'] = $version.VergeOSVersion

    # Clusters
    $clusters = Get-VergeCluster
    $report['Clusters'] = "$($clusters.Count) total"

    # Nodes
    $nodes = Get-VergeNode
    $onlineNodes = ($nodes | Where-Object Status -eq 'Running').Count
    $report['Nodes'] = "$onlineNodes/$($nodes.Count) online"
    $report['NodesNeedRestart'] = ($nodes | Where-Object NeedsRestart).Count

    # Statistics
    $stats = Get-VergeSystemStatistics
    $report['VMs'] = "$($stats.VMsOnline)/$($stats.VMsTotal) running"
    $report['Alarms'] = "$($stats.AlarmsTotal) ($($stats.AlarmsError) errors)"

    [PSCustomObject]$report | Format-List
}

Get-VergeHealthReport
```

### Node Maintenance Workflow

```powershell
$nodeName = "node2"

# 1. Check current state
$node = Get-VergeNode -Name $nodeName
Write-Host "Node: $($node.Name), Status: $($node.Status)"

# 2. Enable maintenance mode
Enable-VergeNodeMaintenance -Name $nodeName

# 3. Wait for VMs to migrate
while ((Get-VergeNode -Name $nodeName).Status -ne 'Maintenance') {
    Write-Host "Waiting for maintenance mode..."
    Start-Sleep -Seconds 10
}

# 4. Perform reboot if needed
Restart-VergeNode -Name $nodeName

# 5. Disable maintenance when done
Disable-VergeNodeMaintenance -Name $nodeName
```

### Hardware Inventory

```powershell
Write-Host "Hardware Summary"
Write-Host "================"
$pci = Get-VergeNodeDevice -DeviceType PCI
$usb = Get-VergeNodeDevice -DeviceType USB
$gpu = Get-VergeNodeDevice -DeviceType GPU

Write-Host "PCI Devices: $($pci.Count)"
Write-Host "USB Devices: $($usb.Count)"
Write-Host "GPUs: $($gpu.Count)"

# Group by class
Write-Host "`nPCI Devices by Class:"
$pci | Group-Object Class | Sort-Object Count -Descending | Format-Table Name, Count
```

## SSL/TLS Certificates

Cmdlets for managing SSL/TLS certificates including manual uploads, Let's Encrypt (ACME), and self-signed certificates.

### Get-VergeCertificate

Lists SSL/TLS certificates with filtering options.

**Syntax:**
```powershell
Get-VergeCertificate [-Domain <String>] [-Key <Int32>] [-Type <String>] [-Valid] [-IncludeKeys]
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Domain` | String | No | Filter by domain (supports wildcards) |
| `-Key` | Int32 | No | Get certificate by unique key |
| `-Type` | String | No | Filter by type: Manual, LetsEncrypt, SelfSigned |
| `-Valid` | Switch | No | Show only valid (unexpired) certificates |
| `-IncludeKeys` | Switch | No | Include public/private key material |

**Examples:**

```powershell
# List all certificates
Get-VergeCertificate

# View certificate summary
Get-VergeCertificate | Format-Table Domain, Type, Valid, DaysUntilExpiry, Expires -AutoSize

# Get a specific certificate
Get-VergeCertificate -Key 1

# Filter by type
Get-VergeCertificate -Type LetsEncrypt
Get-VergeCertificate -Type SelfSigned

# Get only valid certificates
Get-VergeCertificate -Valid

# Filter by domain pattern
Get-VergeCertificate -Domain "api*"

# Include key material (use with caution)
Get-VergeCertificate -Key 1 -IncludeKeys | Select-Object Domain, PublicKey, PrivateKey
```

---

### New-VergeCertificate

Creates a new SSL/TLS certificate.

**Syntax:**
```powershell
New-VergeCertificate -DomainName <String> -Type <String> [-Description <String>]
    [-DomainList <String[]>] [-KeyType <String>] [-RSAKeySize <String>]
    [-PublicKey <String>] [-PrivateKey <String>] [-Chain <String>]
    [-ACMEServer <String>] [-EABKeyId <String>] [-EABHMACKey <String>]
    [-ContactUserId <Int32>] [-AgreeTOS] [-PassThru]
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-DomainName` | String | Yes | Primary domain name |
| `-Type` | String | Yes | Certificate type: Manual, LetsEncrypt, SelfSigned |
| `-Description` | String | No | Certificate description |
| `-DomainList` | String[] | No | Additional SANs |
| `-KeyType` | String | No | ECDSA or RSA |
| `-RSAKeySize` | String | No | RSA key size: 2048, 3072, 4096 |
| `-PublicKey` | String | No | PEM-encoded public certificate (Manual type) |
| `-PrivateKey` | String | No | PEM-encoded private key (Manual type) |
| `-Chain` | String | No | PEM-encoded certificate chain (Manual type) |
| `-ACMEServer` | String | No | ACME server URL (LetsEncrypt type) |
| `-ContactUserId` | Int32 | No | Contact user for ACME (LetsEncrypt type) |
| `-AgreeTOS` | Switch | No | Accept Terms of Service (LetsEncrypt type) |
| `-PassThru` | Switch | No | Return the created certificate |

**Examples:**

```powershell
# Create a self-signed certificate
New-VergeCertificate -DomainName "internal.local" -Type SelfSigned

# Create with description and return result
$cert = New-VergeCertificate -DomainName "app.local" `
    -Type SelfSigned `
    -Description "Application certificate" `
    -PassThru

# Create with SANs
New-VergeCertificate -DomainName "example.com" `
    -Type SelfSigned `
    -DomainList "www.example.com", "api.example.com"

# Upload a manual certificate
$publicKey = Get-Content "./cert.pem" -Raw
$privateKey = Get-Content "./key.pem" -Raw
New-VergeCertificate -DomainName "example.com" `
    -Type Manual `
    -PublicKey $publicKey `
    -PrivateKey $privateKey

# Create Let's Encrypt certificate
New-VergeCertificate -DomainName "public.example.com" `
    -Type LetsEncrypt `
    -AgreeTOS `
    -ContactUserId 1
```

---

### Set-VergeCertificate

Modifies certificate properties.

**Syntax:**
```powershell
Set-VergeCertificate -Key <Int32> [-Description <String>] [-DomainList <String[]>]
    [-PublicKey <String>] [-PrivateKey <String>] [-Chain <String>]
    [-ACMEServer <String>] [-KeyType <String>] [-RSAKeySize <String>]
    [-ContactUserId <Int32>] [-AgreeTOS] [-PassThru]
```

**Examples:**

```powershell
# Update description
Set-VergeCertificate -Key 1 -Description "Production API certificate"

# Update via pipeline
Get-VergeCertificate -Key 1 | Set-VergeCertificate -Description "Updated" -PassThru

# Update SANs
Set-VergeCertificate -Key 1 -DomainList "www.example.com", "api.example.com"

# Update certificate keys (manual certificates)
$newPublicKey = Get-Content "./new-cert.pem" -Raw
$newPrivateKey = Get-Content "./new-key.pem" -Raw
Set-VergeCertificate -Key 1 -PublicKey $newPublicKey -PrivateKey $newPrivateKey
```

---

### Remove-VergeCertificate

Deletes a certificate.

**Syntax:**
```powershell
Remove-VergeCertificate -Key <Int32> [-Confirm:$false]
Remove-VergeCertificate -Domain <String> [-Confirm:$false]
Remove-VergeCertificate -Certificate <Object> [-Confirm:$false]
```

**Examples:**

```powershell
# Remove by key
Remove-VergeCertificate -Key 2

# Remove without confirmation
Remove-VergeCertificate -Key 2 -Confirm:$false

# Remove via pipeline
Get-VergeCertificate -Key 2 | Remove-VergeCertificate

# Remove test certificates
Get-VergeCertificate | Where-Object { $_.Description -like "*test*" } | Remove-VergeCertificate
```

> **Note:** The default system certificate may be protected from deletion.

---

### Update-VergeCertificate

Renews a Let's Encrypt certificate or regenerates a self-signed certificate.

**Syntax:**
```powershell
Update-VergeCertificate -Key <Int32> [-Force] [-PassThru]
Update-VergeCertificate -Domain <String> [-Force] [-PassThru]
Update-VergeCertificate -Certificate <Object> [-Force] [-PassThru]
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Key` | Int32 | Yes* | Certificate key to renew |
| `-Domain` | String | Yes* | Certificate domain to renew |
| `-Certificate` | Object | Yes* | Certificate object from pipeline |
| `-Force` | Switch | No | Force renewal even if not expiring soon |
| `-PassThru` | Switch | No | Return the renewed certificate |

**Examples:**

```powershell
# Renew/regenerate by key
Update-VergeCertificate -Key 1 -Force

# Renew via pipeline
Get-VergeCertificate -Key 1 | Update-VergeCertificate -Force

# Renew and return result
$renewed = Update-VergeCertificate -Key 1 -Force -PassThru
$renewed | Format-List Domain, Type, Valid, Expires

# Renew all certificates expiring within 30 days
Get-VergeCertificate | Where-Object { $_.DaysUntilExpiry -lt 30 } | Update-VergeCertificate -Force
```

> **Note:** For Let's Encrypt certificates, ensure DNS/HTTP validation is properly configured.

## Certificate Workflows

### Certificate Expiration Monitoring

```powershell
# Find certificates expiring soon
$expiring = Get-VergeCertificate | Where-Object {
    $_.DaysUntilExpiry -lt 30 -and $_.DaysUntilExpiry -ge 0
}
if ($expiring) {
    Write-Warning "Certificates expiring within 30 days:"
    $expiring | Format-Table Domain, Type, DaysUntilExpiry, Expires -AutoSize
}

# Certificate health report
$certs = Get-VergeCertificate
[PSCustomObject]@{
    Total    = $certs.Count
    Valid    = ($certs | Where-Object Valid).Count
    Expired  = ($certs | Where-Object { $_.DaysUntilExpiry -lt 0 }).Count
    Warning  = ($certs | Where-Object { $_.DaysUntilExpiry -ge 0 -and $_.DaysUntilExpiry -lt 30 }).Count
    Healthy  = ($certs | Where-Object { $_.DaysUntilExpiry -ge 30 }).Count
} | Format-List
```

### Auto-Renewal Workflow

```powershell
# Renew all expiring Let's Encrypt and self-signed certificates
Get-VergeCertificate | Where-Object {
    $_.DaysUntilExpiry -lt 14 -and
    $_.DaysUntilExpiry -ge 0 -and
    $_.TypeValue -in @('letsencrypt', 'self_signed')
} | ForEach-Object {
    Write-Host "Renewing: $($_.Domain) (expires in $($_.DaysUntilExpiry) days)"
    Update-VergeCertificate -Key $_.Key -Force
}
```

### Certificate Backup

```powershell
# Export certificate with keys
$cert = Get-VergeCertificate -Key 1 -IncludeKeys
$timestamp = Get-Date -Format "yyyyMMdd"

if ($cert.PublicKey) {
    $cert.PublicKey | Set-Content "./backup/$($cert.Domain)-$timestamp.crt"
}
if ($cert.PrivateKey) {
    $cert.PrivateKey | Set-Content "./backup/$($cert.Domain)-$timestamp.key"
}
```

## Webhooks

Cmdlets for managing webhook URL configurations that send notifications to external systems like Slack, Microsoft Teams, or custom APIs.

### Get-VergeWebhook

Lists webhook URL configurations.

**Syntax:**
```powershell
Get-VergeWebhook [-Name <String>] [-Key <Int32>] [-AuthorizationType <String>]
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Name` | String | No | Filter by name (supports wildcards) |
| `-Key` | Int32 | No | Get webhook by unique key |
| `-AuthorizationType` | String | No | Filter by auth type: None, Basic, Bearer, ApiKey |

**Examples:**

```powershell
# List all webhooks
Get-VergeWebhook

# View webhook details
Get-VergeWebhook | Format-Table Name, URL, AuthorizationType, Timeout

# Get specific webhook
Get-VergeWebhook -Name "slack-alerts"

# Find webhooks by auth type
Get-VergeWebhook -AuthorizationType Bearer
```

---

### New-VergeWebhook

Creates a new webhook URL configuration.

**Syntax:**
```powershell
New-VergeWebhook -Name <String> -URL <String> [-Headers <Object>]
    [-AuthorizationType <String>] [-AuthorizationValue <String>]
    [-Credential <PSCredential>] [-AllowInsecure] [-Timeout <Int32>]
    [-Retries <Int32>] [-PassThru]
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Name` | String | Yes | Unique webhook name |
| `-URL` | String | Yes | Webhook endpoint URL |
| `-Headers` | Object | No | Custom headers (hashtable or JSON string) |
| `-AuthorizationType` | String | No | None, Basic, Bearer, or ApiKey |
| `-AuthorizationValue` | String | No | Token/key for Bearer or ApiKey auth |
| `-Credential` | PSCredential | No | Credentials for Basic auth |
| `-AllowInsecure` | Switch | No | Allow self-signed certificates |
| `-Timeout` | Int32 | No | Request timeout in seconds |
| `-Retries` | Int32 | No | Number of retry attempts |
| `-PassThru` | Switch | No | Return the created webhook |

**Examples:**

```powershell
# Create a Slack webhook
New-VergeWebhook -Name "slack-alerts" `
    -URL "https://hooks.slack.com/services/YOUR/WEBHOOK/URL" `
    -Timeout 10 -Retries 3

# Create webhook with Bearer token
New-VergeWebhook -Name "monitoring-api" `
    -URL "https://api.monitoring.example.com/events" `
    -AuthorizationType Bearer `
    -AuthorizationValue "your-api-token"

# Create webhook with custom headers
$headers = @{
    'Content-Type' = 'application/json'
    'X-Source'     = 'VergeOS'
}
New-VergeWebhook -Name "custom-api" `
    -URL "https://api.example.com/webhook" `
    -Headers $headers `
    -AuthorizationType ApiKey `
    -AuthorizationValue "sk-your-api-key"

# Create webhook with Basic auth
$cred = Get-Credential
New-VergeWebhook -Name "basic-auth-hook" `
    -URL "https://api.example.com/hook" `
    -AuthorizationType Basic `
    -Credential $cred
```

---

### Set-VergeWebhook

Modifies webhook configuration.

**Syntax:**
```powershell
Set-VergeWebhook -Key <Int32> [-Name <String>] [-URL <String>]
    [-Headers <Object>] [-AuthorizationType <String>]
    [-AuthorizationValue <String>] [-AllowInsecure <Boolean>]
    [-Timeout <Int32>] [-Retries <Int32>] [-PassThru]
```

**Examples:**

```powershell
# Update timeout and retries
Set-VergeWebhook -Key 1 -Timeout 20 -Retries 5

# Update authentication
Set-VergeWebhook -Key 1 -AuthorizationType Bearer -AuthorizationValue "new-token"

# Update via pipeline
Get-VergeWebhook -Name "slack-alerts" | Set-VergeWebhook -Timeout 30

# Enable insecure connections
Set-VergeWebhook -Key 1 -AllowInsecure $true
```

---

### Remove-VergeWebhook

Deletes a webhook configuration.

**Syntax:**
```powershell
Remove-VergeWebhook -Key <Int32> [-Confirm:$false]
Remove-VergeWebhook -Name <String> [-Confirm:$false]
Remove-VergeWebhook -InputObject <Object> [-Confirm:$false]
```

**Examples:**

```powershell
# Remove by key
Remove-VergeWebhook -Key 1

# Remove by name
Remove-VergeWebhook -Name "old-webhook" -Confirm:$false

# Remove via pipeline
Get-VergeWebhook -Name "test-*" | Remove-VergeWebhook -Confirm:$false
```

---

### Send-VergeWebhook

Sends a test message to a webhook.

**Syntax:**
```powershell
Send-VergeWebhook -Key <Int32> [-Message <Object>]
Send-VergeWebhook -Name <String> [-Message <Object>]
Send-VergeWebhook -InputObject <Object> [-Message <Object>]
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Key` | Int32 | Yes* | Webhook key |
| `-Name` | String | Yes* | Webhook name |
| `-InputObject` | Object | Yes* | Webhook from pipeline |
| `-Message` | Object | No | Message payload (hashtable or JSON string) |

**Examples:**

```powershell
# Send default test message
Send-VergeWebhook -Name "slack-alerts"

# Send custom Slack message
$msg = @{
    text   = "VergeOS Alert: Test notification"
    blocks = @(
        @{
            type = "section"
            text = @{
                type = "mrkdwn"
                text = "*VergeOS Notification*`nTest message from webhook integration."
            }
        }
    )
}
Send-VergeWebhook -Name "slack-alerts" -Message $msg

# Send JSON message to API
$apiMsg = @{
    event     = "test"
    timestamp = (Get-Date).ToString("o")
    source    = "VergeOS"
}
Send-VergeWebhook -Name "monitoring-api" -Message $apiMsg
```

---

### Get-VergeWebhookHistory

Retrieves webhook delivery history.

**Syntax:**
```powershell
Get-VergeWebhookHistory [-WebhookKey <Int32>] [-WebhookName <String>]
    [-Status <String>] [-Pending] [-Failed] [-Limit <Int32>]
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-WebhookKey` | Int32 | No | Filter by webhook key |
| `-WebhookName` | String | No | Filter by webhook name |
| `-Status` | String | No | Filter: Queued, Running, Sent, Error |
| `-Pending` | Switch | No | Show only pending (queued/running) |
| `-Failed` | Switch | No | Show only failed messages |
| `-Limit` | Int32 | No | Maximum entries to return (default: 100) |

**Examples:**

```powershell
# View recent history
Get-VergeWebhookHistory -Limit 10 | Format-Table WebhookName, Status, StatusInfo, Created

# Check failed deliveries
Get-VergeWebhookHistory -Failed | Format-Table WebhookName, StatusInfo, Created

# Check pending messages
Get-VergeWebhookHistory -Pending

# History for specific webhook
Get-VergeWebhookHistory -WebhookName "slack-alerts" -Limit 5
```

## Resource Groups

Cmdlets for viewing hardware resource groups (GPU, PCI, USB, SR-IOV NIC, vGPU) that can be assigned to VMs.

### Get-VergeResourceGroup

Lists resource groups.

**Syntax:**
```powershell
Get-VergeResourceGroup [-Name <String>] [-Key <Int32>] [-UUID <String>]
    [-Type <String>] [-Class <String>] [-Enabled <Boolean>]
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Name` | String | No | Filter by name (supports wildcards) |
| `-Key` | Int32 | No | Get by unique key |
| `-UUID` | String | No | Get by UUID |
| `-Type` | String | No | Filter: PCI, SRIOVNIC, USB, HostGPU, NVIDIAvGPU |
| `-Class` | String | No | Filter: GPU, vGPU, Storage, HID, USB, Network, etc. |
| `-Enabled` | Boolean | No | Filter by enabled status |

**Examples:**

```powershell
# List all resource groups
Get-VergeResourceGroup

# View resource groups summary
Get-VergeResourceGroup | Format-Table Name, Type, Class, Enabled

# Get GPU resource groups
Get-VergeResourceGroup -Type HostGPU

# Get enabled network resource groups
Get-VergeResourceGroup -Class Network -Enabled $true

# Find by name pattern
Get-VergeResourceGroup -Name "*nvidia*"
```

## Webhook Workflows

### Slack Integration

```powershell
# Setup Slack webhook
New-VergeWebhook -Name "slack-alerts" `
    -URL "https://hooks.slack.com/services/YOUR/WEBHOOK/URL" `
    -Timeout 10 -Retries 3

# Send notification
$msg = @{
    text = ":warning: VergeOS Alert"
    attachments = @(
        @{
            color = "danger"
            title = "High CPU Usage"
            text  = "Production cluster at 95% CPU"
        }
    )
}
Send-VergeWebhook -Name "slack-alerts" -Message $msg

# Check delivery
Get-VergeWebhookHistory -WebhookName "slack-alerts" -Limit 1
```

### Webhook Health Check

```powershell
# Check for failed webhooks
$failed = Get-VergeWebhookHistory -Failed -Limit 20
if ($failed) {
    Write-Warning "Failed webhook deliveries:"
    $failed | Group-Object WebhookName | ForEach-Object {
        Write-Host "  $($_.Name): $($_.Count) failures"
    }
}

# Retry pending messages (by resending)
Get-VergeWebhookHistory -Pending | ForEach-Object {
    Write-Host "Pending: $($_.WebhookName) - $($_.Status)"
}
```
