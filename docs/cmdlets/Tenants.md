---
title: Tenant Cmdlets
description: Cmdlets for managing multi-tenant environments including provisioning, networking, snapshots, and VM sharing
tags: [tenant, multi-tenant, get-vergetenant, new-vergetenant, clone, snapshot, isolation, crash-cart, shared-object, network-block, external-ip, layer2, context]
categories: [Tenants]
---

# Tenant Cmdlets

Cmdlets for managing multi-tenant environments.

## Overview

Tenant cmdlets provide complete management of VergeOS multi-tenant environments including tenant provisioning, resource allocation, snapshots, and VM sharing.

## Tenant Lifecycle

### Get-VergeTenant

Lists tenants.

**Syntax:**
```powershell
Get-VergeTenant [-Name <String>] [-PowerState <String>]
Get-VergeTenant -Key <Int32>
```

**Examples:**

```powershell
# List all tenants
Get-VergeTenant

# Filter by name
Get-VergeTenant -Name "Customer-*"

# Get running tenants
Get-VergeTenant -PowerState Running
```

---

### New-VergeTenant

Creates a new tenant.

**Syntax:**
```powershell
New-VergeTenant -Name <String> [-Description <String>] [-AdminPassword <SecureString>]
    [-Cluster <String>] [-PassThru]
```

**Examples:**

```powershell
# Create a tenant
$password = Read-Host -AsSecureString -Prompt "Admin Password"
New-VergeTenant -Name "Customer-ABC" -Description "ABC Corporation" `
    -AdminPassword $password -PassThru
```

---

### Set-VergeTenant

Modifies tenant settings.

---

### Remove-VergeTenant

Deletes a tenant.

> **Warning:** This permanently deletes the tenant and all its resources.

---

### Start-VergeTenant

Powers on a tenant.

```powershell
Start-VergeTenant -Name "Customer-ABC"
```

---

### Stop-VergeTenant

Powers off a tenant.

```powershell
Stop-VergeTenant -Name "Customer-ABC"
```

---

### Restart-VergeTenant

Restarts a tenant.

---

### New-VergeTenantClone

Creates a copy of a tenant.

**Syntax:**
```powershell
New-VergeTenantClone -SourceTenant <String> -Name <String> [-PowerOn] [-PassThru]
```

**Examples:**

```powershell
# Clone for testing
New-VergeTenantClone -SourceTenant "Template-Tenant" -Name "Test-Tenant" -PowerOn
```

## Tenant Context

### Connect-VergeTenantContext

Executes commands within a tenant's context.

**Syntax:**
```powershell
Connect-VergeTenantContext -Tenant <String> -ScriptBlock <ScriptBlock>
```

**Examples:**

```powershell
# Run commands inside tenant
Connect-VergeTenantContext -Tenant "Customer-ABC" -ScriptBlock {
    Get-VergeVM
    Get-VergeNetwork
}
```

## Tenant Snapshots

### Get-VergeTenantSnapshot

Lists tenant snapshots.

---

### New-VergeTenantSnapshot

Creates a tenant snapshot.

**Syntax:**
```powershell
New-VergeTenantSnapshot -Tenant <String> -Name <String> [-Description <String>] [-PassThru]
```

**Examples:**

```powershell
# Create snapshot before maintenance
New-VergeTenantSnapshot -Tenant "Customer-ABC" -Name "Pre-Upgrade"
```

---

### Restore-VergeTenantSnapshot

Restores a tenant from snapshot.

---

### Remove-VergeTenantSnapshot

Deletes a tenant snapshot.

## Tenant Storage

### Get-VergeTenantStorage

Lists storage allocations for a tenant.

---

### New-VergeTenantStorage

Assigns storage to a tenant.

**Syntax:**
```powershell
New-VergeTenantStorage -Tenant <String> -Tier <Int32> -SizeGB <Int32> [-PassThru]
```

**Examples:**

```powershell
# Assign 500GB of Tier 1 storage
New-VergeTenantStorage -Tenant "Customer-ABC" -Tier 1 -SizeGB 500

# Assign capacity tier storage
New-VergeTenantStorage -Tenant "Customer-ABC" -Tier 3 -SizeGB 2000
```

---

### Set-VergeTenantStorage

Modifies tenant storage allocation.

---

### Remove-VergeTenantStorage

Removes storage allocation from tenant.

## Tenant Networking

### Get-VergeTenantExternalIP

Lists external IPs assigned to a tenant.

---

### New-VergeTenantExternalIP

Assigns an external IP to a tenant.

**Syntax:**
```powershell
New-VergeTenantExternalIP -Tenant <String> -IPAddress <String> [-PassThru]
```

---

### Remove-VergeTenantExternalIP

Removes an external IP from a tenant.

---

### Get-VergeTenantNetworkBlock

Lists network blocks assigned to a tenant.

---

### New-VergeTenantNetworkBlock

Assigns a network block (CIDR) to a tenant.

**Syntax:**
```powershell
New-VergeTenantNetworkBlock -Tenant <String> -Network <String> -CIDR <String> [-PassThru]
```

**Examples:**

```powershell
# Assign a /28 block
New-VergeTenantNetworkBlock -Tenant "Customer-ABC" -Network "External" `
    -CIDR "192.168.100.0/28"
```

---

### Remove-VergeTenantNetworkBlock

Removes a network block from a tenant.

---

### Get-VergeTenantLayer2Network

Lists Layer 2 networks available to a tenant.

---

### New-VergeTenantLayer2Network

Creates a Layer 2 network connection to a tenant.

---

### Set-VergeTenantLayer2Network

Modifies Layer 2 network settings.

---

### Remove-VergeTenantLayer2Network

Removes Layer 2 network from tenant.

## VM Sharing

### Get-VergeSharedObject

Lists VMs shared with a tenant.

---

### New-VergeSharedObject

Shares a VM with a tenant.

**Syntax:**
```powershell
New-VergeSharedObject -VM <String> -Tenant <String> [-PassThru]
```

**Examples:**

```powershell
# Share a template VM
New-VergeSharedObject -VM "Ubuntu-Template" -Tenant "Customer-ABC"
```

---

### Import-VergeSharedObject

Imports a shared VM into the tenant.

**Syntax:**
```powershell
Import-VergeSharedObject -SharedObject <Object> [-NewName <String>] [-PassThru]
```

---

### Remove-VergeSharedObject

Removes VM sharing.

## Emergency Access

### New-VergeTenantCrashCart

Deploys an emergency console VM for tenant access.

**Syntax:**
```powershell
New-VergeTenantCrashCart -Tenant <String> [-PassThru]
```

**Examples:**

```powershell
# Deploy crash cart for emergency access
New-VergeTenantCrashCart -Tenant "Customer-ABC"
```

---

### Remove-VergeTenantCrashCart

Removes the crash cart VM.

## Tenant Isolation

### Enable-VergeTenantIsolation

Enables tenant isolation mode.

---

### Disable-VergeTenantIsolation

Disables tenant isolation mode.

## File Sharing

### Send-VergeTenantFile

Shares a file with a tenant.

**Syntax:**
```powershell
Send-VergeTenantFile -Tenant <String> -FilePath <String>
```

## Common Workflows

### Provision New Customer Tenant

```powershell
$tenantName = "Customer-NewCo"
$password = Read-Host -AsSecureString -Prompt "Admin Password"

# 1. Create tenant
$tenant = New-VergeTenant -Name $tenantName -Description "NewCo Inc." `
    -AdminPassword $password -PassThru

# 2. Assign storage
New-VergeTenantStorage -Tenant $tenantName -Tier 1 -SizeGB 200
New-VergeTenantStorage -Tenant $tenantName -Tier 3 -SizeGB 1000

# 3. Assign networking
New-VergeTenantNetworkBlock -Tenant $tenantName -Network "External" `
    -CIDR "192.168.200.0/28"

# 4. Share template VMs
New-VergeSharedObject -VM "Windows-Template" -Tenant $tenantName
New-VergeSharedObject -VM "Linux-Template" -Tenant $tenantName

# 5. Start tenant
Start-VergeTenant -Name $tenantName

Write-Host "Tenant '$tenantName' provisioned and running"
```

### Tenant Maintenance

```powershell
$tenantName = "Customer-ABC"

# Create pre-maintenance snapshot
New-VergeTenantSnapshot -Tenant $tenantName -Name "Pre-Maintenance-$(Get-Date -Format 'yyyyMMdd')"

# Perform maintenance...

# If issues, restore
# Restore-VergeTenantSnapshot -Tenant $tenantName -SnapshotName "Pre-Maintenance-..."
```
