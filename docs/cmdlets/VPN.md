---
title: VPN Cmdlets
description: Cmdlets for configuring IPSec and WireGuard VPN connections and peers
tags: [vpn, ipsec, wireguard, tunnel, site-to-site, remote-access, get-vergeipsecconnection, new-vergeipsecconnection, get-vergewireguard, new-vergewireguard, peer, encryption]
categories: [VPN]
---

# VPN Cmdlets

Cmdlets for configuring IPSec and WireGuard VPN connections.

## Overview

VPN cmdlets enable configuration of site-to-site and remote access VPN connections using IPSec or WireGuard protocols.

## IPSec Cmdlets

### Get-VergeIPSecConnection

Lists IPSec VPN connections.

**Syntax:**
```powershell
Get-VergeIPSecConnection [-Network <String>] [-Name <String>]
```

**Examples:**

```powershell
# List all IPSec connections
Get-VergeIPSecConnection

# Filter by network
Get-VergeIPSecConnection -Network "External"
```

---

### New-VergeIPSecConnection

Creates an IPSec VPN connection.

**Syntax:**
```powershell
New-VergeIPSecConnection -Network <String> -Name <String> -RemoteGateway <String>
    -LocalSubnets <String[]> -RemoteSubnets <String[]> -PreSharedKey <String>
    [-IKEVersion <String>] [-PassThru]
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-Network` | String | Yes | Network to add connection to |
| `-Name` | String | Yes | Connection name |
| `-RemoteGateway` | String | Yes | Remote VPN endpoint IP |
| `-LocalSubnets` | String[] | Yes | Local subnets to tunnel |
| `-RemoteSubnets` | String[] | Yes | Remote subnets to tunnel |
| `-PreSharedKey` | String | Yes | Shared secret |
| `-IKEVersion` | String | No | ikev1, ikev2 (default: ikev2) |

**Examples:**

```powershell
# Create site-to-site VPN
New-VergeIPSecConnection -Network "External" -Name "Branch-Office" `
    -RemoteGateway "203.0.113.1" `
    -LocalSubnets @("10.0.0.0/24") `
    -RemoteSubnets @("192.168.1.0/24") `
    -PreSharedKey "YourSecretKey"
```

---

### Set-VergeIPSecConnection

Modifies an IPSec connection.

---

### Remove-VergeIPSecConnection

Deletes an IPSec connection.

---

### Get-VergeIPSecPolicy

Lists IPSec encryption policies.

---

### New-VergeIPSecPolicy

Creates an IPSec policy.

---

### Remove-VergeIPSecPolicy

Deletes an IPSec policy.

## WireGuard Cmdlets

### Get-VergeWireGuard

Lists WireGuard interfaces.

**Syntax:**
```powershell
Get-VergeWireGuard [-Network <String>] [-Name <String>]
```

---

### New-VergeWireGuard

Creates a WireGuard interface.

**Syntax:**
```powershell
New-VergeWireGuard -Network <String> -Name <String> -ListenPort <Int32>
    -Address <String> [-PassThru]
```

**Examples:**

```powershell
# Create WireGuard interface
New-VergeWireGuard -Network "External" -Name "WG-VPN" `
    -ListenPort 51820 -Address "10.200.0.1/24"
```

---

### Set-VergeWireGuard

Modifies a WireGuard interface.

---

### Remove-VergeWireGuard

Deletes a WireGuard interface.

---

### Get-VergeWireGuardPeer

Lists WireGuard peers.

---

### New-VergeWireGuardPeer

Adds a WireGuard peer.

**Syntax:**
```powershell
New-VergeWireGuardPeer -WireGuard <Object> -Name <String> -PublicKey <String>
    -AllowedIPs <String[]> [-Endpoint <String>] [-PersistentKeepalive <Int32>]
```

**Examples:**

```powershell
# Add a peer
New-VergeWireGuardPeer -WireGuard "WG-VPN" -Name "Remote-Office" `
    -PublicKey "peer-public-key-base64" `
    -AllowedIPs @("10.200.0.2/32", "192.168.10.0/24") `
    -Endpoint "remote.example.com:51820" `
    -PersistentKeepalive 25
```

---

### Remove-VergeWireGuardPeer

Removes a WireGuard peer.
