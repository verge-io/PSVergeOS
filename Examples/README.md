# PSVergeOS Examples

Ready-to-use scripts demonstrating common VergeOS management workflows. These examples show best practices and patterns for automating infrastructure tasks.

## Prerequisites

All examples require:
- PowerShell 7.4 or later
- PSVergeOS module installed
- Active connection to VergeOS (`Connect-VergeOS`)

## Examples

### 01-Connection.ps1
**Getting Started with Connections**

Demonstrates connection and session management:
- Interactive credential-based login
- Token-based authentication for automation
- Self-signed certificate handling
- Managing multiple server connections
- Switching between default connections

```powershell
# Quick example
Connect-VergeOS -Server "vergeos.company.com" -Token $env:VERGE_TOKEN
Get-VergeConnection | Format-Table Server, Username, VergeOSVersion
```

---

### 02-CreateVMWithNetwork.ps1
**Complete VM Deployment Workflow**

End-to-end infrastructure deployment demonstrating:
- Creating an internal network with DHCP and external routing
- Creating a VM with custom CPU, RAM, and boot settings
- Adding drives on different storage tiers
- Mounting an ISO for installation
- Connecting the VM to the network
- Starting the VM and getting console access

This is the pattern to follow for deploying new servers or nested VergeOS environments.

---

### 03-VMLifecycle.ps1
**VM Management Operations**

Comprehensive VM management examples:
- Listing and filtering VMs by name, state, and cluster
- Power operations: start, stop, restart (graceful and forced)
- Creating and managing VM snapshots
- Cloning VMs for templates and testing
- Bulk operations using pipelines
- Maintenance workflows with snapshot protection
- Generating VM inventory reports

```powershell
# Quick example
Get-VergeVM -Name "Prod-*" -PowerState Running | ForEach-Object {
    New-VergeVMSnapshot -VMName $_.Name -Name "Daily-$(Get-Date -Format 'yyyyMMdd')"
}
```

---

### 04-NetworkManagement.ps1
**Network Configuration**

Network administration and security:
- Creating networks with DHCP and routing
- Configuring DHCP host reservations
- Creating and managing firewall rules
- Working with DNS zones and records
- Using IP aliases/groups for rule management
- Network diagnostics (ARP tables, DHCP leases)
- Complete web tier network setup workflow

---

### 05-SystemManagement.ps1
**System Administration**

Infrastructure management operations:
- VergeOS version information and compatibility checks
- Cluster management (create, modify, capacity monitoring)
- Node management and health checks
- Maintenance mode and node reboots
- System statistics and dashboard data
- System settings inspection
- License monitoring
- Hardware discovery (PCI, USB, GPU devices)
- Comprehensive health report generation

---

### 06-NASSimple.ps1
**Basic NAS Setup**

Quick NAS deployment for file sharing:
- Deploy a NAS service on an internal network
- Create volumes with specified sizes
- Verify the configuration
- Basic NAS lifecycle management

This is the starting point for simple file server needs.

---

### 07-NASVolumeSync.ps1
**Volume Synchronization**

Data replication and backup:
- Listing and monitoring volume sync jobs
- Creating sync configurations between volumes
- Starting and stopping sync operations
- Monitoring sync progress and status
- Configuring sync schedules
- Sync best practices for backup strategies

---

### 08-NASAdvanced.ps1
**Advanced NAS Configuration**

Enterprise NAS features:
- CIFS/SMB share management and permissions
- NFS export configuration
- NAS local user management
- CIFS service settings (workgroup, protocols)
- NFS service settings (NFSv4, squashing)
- Active Directory integration preparation
- Volume browsing and file management

---

### 09-TaskManagement.ps1
**Task Monitoring and Control**

Managing long-running operations:
- Listing running and completed tasks
- Filtering tasks by status and type
- Waiting for task completion with timeout
- Canceling running tasks
- Task progress monitoring
- Error handling for failed tasks

```powershell
# Quick example
$task = New-VergeVMClone -SourceVM "Template" -Name "NewVM" -PassThru
Wait-VergeTask -Task $task -Timeout 300
```

---

### 10-AlarmsAndLogs.ps1
**Monitoring and Alerting**

System health and audit:
- Listing and filtering alarms by severity
- Acknowledging and snoozing alarms
- Querying system logs with filters
- Time-based log searches
- Creating health check scripts
- Generating monitoring reports
- Integrating with alerting workflows

---

### 11-RestoreFromCloudSnapshot.ps1
**Disaster Recovery**

Recovery operations from cloud snapshots:
- Listing available cloud snapshots
- Searching for VMs/tenants within snapshots
- Interactive restore workflow
- Restoring VMs from cloud snapshots
- Restoring tenants from cloud snapshots
- DR testing procedures

This is an interactive script that can be run with parameters:
```powershell
./11-RestoreFromCloudSnapshot.ps1 -Name "WebServer01" -Type VM
./11-RestoreFromCloudSnapshot.ps1 -Name "CustomerA" -Type Tenant
```

## Running the Examples

1. **Connect first** - All examples assume an active connection:
   ```powershell
   Connect-VergeOS -Server "your-server" -Credential (Get-Credential)
   ```

2. **Review and customize** - Each example has a configuration section at the top. Update names, networks, and settings for your environment.

3. **Run interactively** - Copy/paste sections to understand each step, or run the entire script.

4. **Check prerequisites** - Some examples require specific resources (networks, ISOs, etc.) to exist.

## Best Practices Demonstrated

- **Error handling** - Examples show proper try/catch patterns
- **Idempotency** - Checks for existing resources before creation
- **Pipeline usage** - Efficient bulk operations with PowerShell pipeline
- **WhatIf support** - Preview changes before execution
- **Verbose logging** - Use `-Verbose` for detailed output
- **Progress indicators** - Long operations show status
- **Cleanup** - Examples include resource removal patterns

## Creating Your Own Scripts

Use these examples as templates:

```powershell
#Requires -Version 7.4
#Requires -Modules PSVergeOS

<#
.SYNOPSIS
    Your script description.
.DESCRIPTION
    Detailed description of what the script does.
#>

# Configuration
$VMName = "MyServer"

# Verify connection
$connection = Get-VergeConnection -Default
if (-not $connection) {
    throw "Not connected. Run Connect-VergeOS first."
}

# Your automation logic here
# ...
```
