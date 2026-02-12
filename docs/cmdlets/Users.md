---
title: Users & Groups Cmdlets
description: Cmdlets for managing user accounts, groups, permissions, and API keys
tags: [user, group, permission, api-key, rbac, get-vergeuser, new-vergeuser, get-vergegroup, grant-vergepermission, access-control, onboarding]
categories: [Users]
---

# Users & Groups Cmdlets

Cmdlets for managing users, groups, and permissions.

## Overview

User cmdlets provide management of VergeOS user accounts, groups, and access permissions including API key management.

## User Management

### Get-VergeUser

Lists user accounts.

**Syntax:**
```powershell
Get-VergeUser [-Name <String>] [-Type <String>] [-Enabled <Boolean>]
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Name` | String | No | Username (supports wildcards) |
| `-Type` | String | No | normal, api, vdi |
| `-Enabled` | Boolean | No | Filter by enabled status |

**Examples:**

```powershell
# List all users
Get-VergeUser

# Find specific user
Get-VergeUser -Name "jsmith"

# List API users only
Get-VergeUser -Type api

# List disabled accounts
Get-VergeUser -Enabled $false
```

---

### New-VergeUser

Creates a user account.

**Syntax:**
```powershell
New-VergeUser -Username <String> -Password <SecureString> [-DisplayName <String>]
    [-Email <String>] [-Type <String>] [-PassThru]
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Username` | String | Yes | Login username |
| `-Password` | SecureString | Yes | User password |
| `-DisplayName` | String | No | Full name |
| `-Email` | String | No | Email address |
| `-Type` | String | No | normal, api, vdi (default: normal) |

**Examples:**

```powershell
# Create a user
$password = Read-Host -AsSecureString -Prompt "Password"
New-VergeUser -Username "jsmith" -Password $password -DisplayName "John Smith" `
    -Email "jsmith@company.com"

# Create API user
New-VergeUser -Username "automation-svc" -Password $password -Type api
```

---

### Set-VergeUser

Modifies user settings.

**Syntax:**
```powershell
Set-VergeUser -Username <String> [-Password <SecureString>] [-DisplayName <String>]
    [-Email <String>] [-PassThru]
```

**Examples:**

```powershell
# Update email
Set-VergeUser -Username "jsmith" -Email "john.smith@company.com"

# Reset password
$newPassword = Read-Host -AsSecureString -Prompt "New Password"
Set-VergeUser -Username "jsmith" -Password $newPassword
```

---

### Remove-VergeUser

Deletes a user account.

```powershell
Remove-VergeUser -Username "olduser"
```

---

### Enable-VergeUser

Enables a disabled user account.

```powershell
Enable-VergeUser -Username "jsmith"
```

---

### Disable-VergeUser

Disables a user account without deleting it.

```powershell
Disable-VergeUser -Username "jsmith"
```

## API Keys

### Get-VergeAPIKey

Lists API keys for a user.

**Syntax:**
```powershell
Get-VergeAPIKey [-Username <String>]
```

**Examples:**

```powershell
# List all API keys
Get-VergeAPIKey

# List keys for specific user
Get-VergeAPIKey -Username "automation-svc"
```

---

### New-VergeAPIKey

Creates an API key.

**Syntax:**
```powershell
New-VergeAPIKey -Username <String> -Name <String> [-ExpiresAt <DateTime>] [-PassThru]
```

**Examples:**

```powershell
# Create API key
$key = New-VergeAPIKey -Username "automation-svc" -Name "CI-Pipeline" -PassThru
Write-Host "Token: $($key.Token)"  # Save this - shown only once

# Create key with expiration
New-VergeAPIKey -Username "contractor" -Name "Project-Key" `
    -ExpiresAt (Get-Date).AddMonths(3)
```

---

### Remove-VergeAPIKey

Revokes an API key.

```powershell
Remove-VergeAPIKey -Username "automation-svc" -Name "Old-Key"
```

## Group Management

### Get-VergeGroup

Lists groups.

**Syntax:**
```powershell
Get-VergeGroup [-Name <String>]
```

---

### New-VergeGroup

Creates a group.

**Syntax:**
```powershell
New-VergeGroup -Name <String> [-Description <String>] [-PassThru]
```

**Examples:**

```powershell
# Create a group
New-VergeGroup -Name "Administrators" -Description "Full system access"
New-VergeGroup -Name "Operators" -Description "Day-to-day operations"
```

---

### Set-VergeGroup

Modifies group settings.

---

### Remove-VergeGroup

Deletes a group.

---

### Get-VergeGroupMember

Lists members of a group.

**Syntax:**
```powershell
Get-VergeGroupMember -Group <String>
```

---

### Add-VergeGroupMember

Adds a user to a group.

**Syntax:**
```powershell
Add-VergeGroupMember -Group <String> -Username <String>
```

**Examples:**

```powershell
# Add user to group
Add-VergeGroupMember -Group "Administrators" -Username "jsmith"
```

---

### Remove-VergeGroupMember

Removes a user from a group.

```powershell
Remove-VergeGroupMember -Group "Administrators" -Username "oldadmin"
```

## Permissions

### Get-VergePermission

Lists permissions.

**Syntax:**
```powershell
Get-VergePermission [-User <String>] [-Group <String>]
```

**Examples:**

```powershell
# List all permissions
Get-VergePermission

# Permissions for specific user
Get-VergePermission -User "jsmith"

# Permissions for a group
Get-VergePermission -Group "Operators"
```

---

### Grant-VergePermission

Grants a permission to a user or group.

**Syntax:**
```powershell
Grant-VergePermission -User <String> -Permission <String> [-Resource <String>]
Grant-VergePermission -Group <String> -Permission <String> [-Resource <String>]
```

**Examples:**

```powershell
# Grant VM management to user
Grant-VergePermission -User "operator1" -Permission "vm.manage"

# Grant network access to group
Grant-VergePermission -Group "NetworkAdmins" -Permission "network.full"
```

---

### Revoke-VergePermission

Removes a permission.

```powershell
Revoke-VergePermission -User "olduser" -Permission "vm.manage"
```

## Common Workflows

### Onboard New Administrator

```powershell
# Create user
$password = Read-Host -AsSecureString -Prompt "Password"
New-VergeUser -Username "newadmin" -Password $password `
    -DisplayName "New Admin" -Email "newadmin@company.com"

# Add to administrators group
Add-VergeGroupMember -Group "Administrators" -Username "newadmin"

# Create API key for automation
$key = New-VergeAPIKey -Username "newadmin" -Name "CLI-Access" -PassThru
Write-Host "API Token (save this): $($key.Token)"
```

### Offboard User

```powershell
$username = "departinguser"

# Revoke API keys
Get-VergeAPIKey -Username $username | ForEach-Object {
    Remove-VergeAPIKey -Username $username -Name $_.Name
}

# Remove from all groups
Get-VergeGroup | ForEach-Object {
    $members = Get-VergeGroupMember -Group $_.Name
    if ($members.Username -contains $username) {
        Remove-VergeGroupMember -Group $_.Name -Username $username
    }
}

# Disable account (or Remove-VergeUser to delete)
Disable-VergeUser -Username $username
```

### Audit User Access

```powershell
# Generate user access report
Get-VergeUser | ForEach-Object {
    $permissions = Get-VergePermission -User $_.Username
    [PSCustomObject]@{
        Username = $_.Username
        DisplayName = $_.DisplayName
        Type = $_.Type
        Enabled = $_.Enabled
        PermissionCount = $permissions.Count
    }
} | Format-Table
```
