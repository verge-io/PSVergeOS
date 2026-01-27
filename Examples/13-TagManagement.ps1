<#
.SYNOPSIS
    Examples for VergeOS tag management and resource organization.

.DESCRIPTION
    This script demonstrates tag management capabilities:
    - Creating and managing tag categories
    - Creating and managing tags within categories
    - Assigning tags to resources (VMs, networks, tenants)
    - Removing tag assignments
    - Querying resources by tags
    - Common tagging workflows and reporting

.NOTES
    Prerequisites:
    - PowerShell 7.4 or later
    - PSVergeOS module installed
    - Connected to a VergeOS system
#>

# Import the module
Import-Module PSVergeOS

#region Tag Categories
# ============================================================================
# MANAGING TAG CATEGORIES
# ============================================================================

# List all tag categories
Get-VergeTagCategory

# Get a specific tag category by name
Get-VergeTagCategory -Name "Environment"

# View tag categories with their taggable resource types
Get-VergeTagCategory | Format-Table Name, TaggableVMs, TaggableNetworks, TaggableTenants, SingleTagSelection

# Create a tag category for environment classification
New-VergeTagCategory -Name "Environment" `
    -Description "Deployment environment classification" `
    -TaggableVMs `
    -TaggableNetworks `
    -TaggableTenants `
    -SingleTagSelection

# Create a category that allows multiple tags per resource
New-VergeTagCategory -Name "Application" `
    -Description "Application or service tags" `
    -TaggableVMs

# Create a category for cost allocation
New-VergeTagCategory -Name "CostCenter" `
    -Description "Cost center for billing allocation" `
    -TaggableVMs `
    -TaggableTenants `
    -SingleTagSelection `
    -PassThru

# Update a tag category to enable additional resource types
Set-VergeTagCategory -Name "Environment" -TaggableNodes $true -TaggableClusters $true

# Update category description
Set-VergeTagCategory -Name "Application" -Description "Application and service identification"

# List categories that can tag VMs
Get-VergeTagCategory | Where-Object TaggableVMs | Format-Table Name, Description

#endregion

#region Tags
# ============================================================================
# MANAGING TAGS WITHIN CATEGORIES
# ============================================================================

# List all tags
Get-VergeTag

# List tags in a specific category
Get-VergeTag -Category "Environment"

# Get tags using pipeline from category
Get-VergeTagCategory -Name "Environment" | Get-VergeTag

# Find tags by name pattern
Get-VergeTag -Name "Prod*"

# Create environment tags
New-VergeTag -Name "Production" -Category "Environment" -Description "Production workloads"
New-VergeTag -Name "Staging" -Category "Environment" -Description "Pre-production testing"
New-VergeTag -Name "Development" -Category "Environment" -Description "Development and testing"
New-VergeTag -Name "DR" -Category "Environment" -Description "Disaster recovery resources"

# Create application tags
New-VergeTag -Name "WebServer" -Category "Application" -Description "Web server tier"
New-VergeTag -Name "Database" -Category "Application" -Description "Database tier"
New-VergeTag -Name "AppServer" -Category "Application" -Description "Application server tier"
New-VergeTag -Name "LoadBalancer" -Category "Application" -Description "Load balancer"

# Create cost center tags
New-VergeTag -Name "IT-Operations" -Category "CostCenter" -Description "IT Operations budget"
New-VergeTag -Name "Engineering" -Category "CostCenter" -Description "Engineering budget"
New-VergeTag -Name "Marketing" -Category "CostCenter" -Description "Marketing budget"

# Update tag description
Set-VergeTag -Name "Production" -Description "Production environment - critical workloads"

# View tags with their category information
Get-VergeTag | Format-Table Name, CategoryName, Description

#endregion

#region Assigning Tags to Resources
# ============================================================================
# ASSIGNING TAGS TO VMs, NETWORKS, AND TENANTS
# ============================================================================

# Assign a tag to a VM by name
Add-VergeTagMember -Tag "Production" -VM "WebServer01"

# Assign a tag to a VM and get the result
$assignment = Add-VergeTagMember -Tag "Production" -VM "WebServer01" -PassThru
$assignment | Format-Table TagName, ResourceType, ResourceKey

# Assign tags to multiple VMs using pipeline
Get-VergeVM -Name "Web*" | Add-VergeTagMember -Tag "WebServer"
Get-VergeVM -Name "DB*" | Add-VergeTagMember -Tag "Database"

# Assign multiple tags to a single VM
$vm = Get-VergeVM -Name "WebServer01"
Add-VergeTagMember -Tag "Production" -VM $vm
Add-VergeTagMember -Tag "WebServer" -VM $vm
Add-VergeTagMember -Tag "IT-Operations" -VM $vm

# Assign a tag to a network
Add-VergeTagMember -Tag "Production" -Network "DMZ"

# Assign a tag to a tenant
Add-VergeTagMember -Tag "Production" -Tenant "CustomerA"

# Assign tag using generic resource type and key
Add-VergeTagMember -Tag "Production" -ResourceType vms -ResourceKey 123

# Bulk tagging: Tag all VMs in a cluster as Production
Get-VergeVM -Cluster "Prod-Cluster" | ForEach-Object {
    Add-VergeTagMember -Tag "Production" -VM $_
}

#endregion

#region Viewing Tag Assignments
# ============================================================================
# QUERYING TAG ASSIGNMENTS
# ============================================================================

# List all resources with a specific tag
Get-VergeTagMember -Tag "Production"

# List only VMs with a tag
Get-VergeTagMember -Tag "Production" -ResourceType vms

# List networks with a tag
Get-VergeTagMember -Tag "Production" -ResourceType vnets

# Get tag assignments using pipeline
Get-VergeTag -Name "Production" | Get-VergeTagMember

# List all tag assignments for tags in a category
Get-VergeTagCategory -Name "Environment" | Get-VergeTag | Get-VergeTagMember

# View assignments in table format
Get-VergeTagMember -Tag "Production" | Format-Table TagName, ResourceType, ResourceKey, ResourceRef

# Count resources by tag
Get-VergeTag -Category "Environment" | ForEach-Object {
    $members = Get-VergeTagMember -Tag $_.Name
    [PSCustomObject]@{
        Tag      = $_.Name
        Category = $_.CategoryName
        Count    = $members.Count
    }
} | Format-Table

#endregion

#region Removing Tag Assignments
# ============================================================================
# REMOVING TAGS FROM RESOURCES
# ============================================================================

# Remove a tag from a VM by specifying tag and VM
Remove-VergeTagMember -Tag "Development" -VM "WebServer01"

# Remove without confirmation prompt (for scripts)
Remove-VergeTagMember -Tag "Development" -VM "WebServer01" -Confirm:$false

# Remove by tag member key
Remove-VergeTagMember -Key 42 -Confirm:$false

# Remove tag from network
Remove-VergeTagMember -Tag "Production" -Network "DMZ" -Confirm:$false

# Remove all tag assignments for a tag using pipeline
Get-VergeTagMember -Tag "Staging" | Remove-VergeTagMember -Confirm:$false

# Remove specific resource type assignments
Get-VergeTagMember -Tag "Production" -ResourceType vms |
    Where-Object { $_.ResourceKey -eq 123 } |
    Remove-VergeTagMember -Confirm:$false

#endregion

#region Removing Tags and Categories
# ============================================================================
# DELETING TAGS AND TAG CATEGORIES
# ============================================================================

# Remove a tag (this also removes all tag assignments)
Remove-VergeTag -Name "OldTag"

# Remove without confirmation
Remove-VergeTag -Name "Temporary" -Confirm:$false

# Remove all tags in a category
Get-VergeTag -Category "OldCategory" | Remove-VergeTag -Confirm:$false

# Remove a tag category (must have no tags)
Remove-VergeTagCategory -Name "UnusedCategory"

# Safe category removal workflow
$categoryName = "CategoryToRemove"
$tags = Get-VergeTag -Category $categoryName

if ($tags) {
    Write-Warning "Category '$categoryName' has $($tags.Count) tags. Remove tags first."
    # Get-VergeTag -Category $categoryName | Remove-VergeTag -Confirm:$false
} else {
    Remove-VergeTagCategory -Name $categoryName -Confirm:$false
    Write-Host "Category '$categoryName' removed."
}

#endregion

#region Common Tagging Workflows
# ============================================================================
# PRACTICAL TAGGING WORKFLOWS
# ============================================================================

# Workflow: Set up a complete tagging structure for a new environment
function Initialize-VergeTagStructure {
    <#
    .SYNOPSIS
        Creates a standard tagging structure for resource organization.
    #>

    # Create Environment category
    $envCategory = Get-VergeTagCategory -Name "Environment"
    if (-not $envCategory) {
        New-VergeTagCategory -Name "Environment" `
            -Description "Deployment environment" `
            -TaggableVMs -TaggableNetworks -TaggableTenants `
            -SingleTagSelection

        @("Production", "Staging", "Development", "DR") | ForEach-Object {
            New-VergeTag -Name $_ -Category "Environment"
        }
        Write-Host "Created Environment category with tags"
    }

    # Create Application category
    $appCategory = Get-VergeTagCategory -Name "Application"
    if (-not $appCategory) {
        New-VergeTagCategory -Name "Application" `
            -Description "Application tier" `
            -TaggableVMs

        @("Web", "App", "Database", "Cache", "Queue") | ForEach-Object {
            New-VergeTag -Name $_ -Category "Application"
        }
        Write-Host "Created Application category with tags"
    }

    # Create Owner category
    $ownerCategory = Get-VergeTagCategory -Name "Owner"
    if (-not $ownerCategory) {
        New-VergeTagCategory -Name "Owner" `
            -Description "Team or individual responsible" `
            -TaggableVMs -TaggableTenants `
            -SingleTagSelection
        Write-Host "Created Owner category (add team tags as needed)"
    }
}

# Initialize-VergeTagStructure

# Workflow: Tag all untagged VMs with a default environment
function Set-DefaultEnvironmentTag {
    param(
        [string]$DefaultTag = "Development"
    )

    $allVMs = Get-VergeVM
    $envTags = Get-VergeTag -Category "Environment"

    foreach ($vm in $allVMs) {
        # Check if VM has any environment tag
        $hasEnvTag = $false
        foreach ($tag in $envTags) {
            $members = Get-VergeTagMember -Tag $tag.Name -ResourceType vms
            if ($members | Where-Object { $_.ResourceKey -eq $vm.Key }) {
                $hasEnvTag = $true
                break
            }
        }

        if (-not $hasEnvTag) {
            Write-Host "Tagging VM '$($vm.Name)' with '$DefaultTag'"
            Add-VergeTagMember -Tag $DefaultTag -VM $vm
        }
    }
}

# Set-DefaultEnvironmentTag -DefaultTag "Development"

# Workflow: Migrate VMs from one tag to another
function Move-VergeVMTag {
    param(
        [string]$FromTag,
        [string]$ToTag
    )

    $members = Get-VergeTagMember -Tag $FromTag -ResourceType vms

    foreach ($member in $members) {
        Write-Host "Moving VM $($member.ResourceKey) from '$FromTag' to '$ToTag'"
        Remove-VergeTagMember -Key $member.Key -Confirm:$false
        Add-VergeTagMember -Tag $ToTag -ResourceType vms -ResourceKey $member.ResourceKey
    }
}

# Move-VergeVMTag -FromTag "Development" -ToTag "Staging"

#endregion

#region Tag-Based Reporting
# ============================================================================
# REPORTING AND INVENTORY BY TAGS
# ============================================================================

# Generate VM inventory grouped by environment tag
function Get-VMsByEnvironment {
    $envTags = Get-VergeTag -Category "Environment"

    foreach ($tag in $envTags) {
        $members = Get-VergeTagMember -Tag $tag.Name -ResourceType vms

        [PSCustomObject]@{
            Environment = $tag.Name
            VMCount     = $members.Count
            VMKeys      = ($members.ResourceKey -join ', ')
        }
    }
}

Get-VMsByEnvironment | Format-Table -AutoSize

# Detailed VM report with tags
function Get-VMTagReport {
    $vms = Get-VergeVM
    $allTags = Get-VergeTag

    foreach ($vm in $vms) {
        $vmTags = @()

        foreach ($tag in $allTags) {
            $members = Get-VergeTagMember -Tag $tag.Name -ResourceType vms
            if ($members | Where-Object { $_.ResourceKey -eq $vm.Key }) {
                $vmTags += "$($tag.CategoryName):$($tag.Name)"
            }
        }

        [PSCustomObject]@{
            VMName     = $vm.Name
            PowerState = $vm.PowerState
            CPUCores   = $vm.CPUCores
            RAM_GB     = [math]::Round($vm.RAM / 1024, 1)
            Tags       = $vmTags -join '; '
        }
    }
}

Get-VMTagReport | Format-Table -AutoSize

# Export tag report to CSV
# Get-VMTagReport | Export-Csv "vm-tag-report.csv" -NoTypeInformation

# Find untagged VMs (VMs without any environment tag)
function Get-UntaggedVMs {
    param(
        [string]$Category = "Environment"
    )

    $vms = Get-VergeVM
    $categoryTags = Get-VergeTag -Category $Category

    $taggedVMKeys = @()
    foreach ($tag in $categoryTags) {
        $members = Get-VergeTagMember -Tag $tag.Name -ResourceType vms
        $taggedVMKeys += $members.ResourceKey
    }

    $vms | Where-Object { $_.Key -notin $taggedVMKeys } |
        Select-Object Name, PowerState, Cluster, Created
}

Write-Host "`nUntagged VMs (no Environment tag):"
Get-UntaggedVMs -Category "Environment" | Format-Table

# Resource count summary by tag
function Get-TagSummary {
    $tags = Get-VergeTag

    foreach ($tag in $tags) {
        $members = Get-VergeTagMember -Tag $tag.Name

        $summary = $members | Group-Object ResourceType | ForEach-Object {
            "$($_.Name): $($_.Count)"
        }

        [PSCustomObject]@{
            Tag         = $tag.Name
            Category    = $tag.CategoryName
            TotalCount  = $members.Count
            Breakdown   = $summary -join ', '
        }
    }
}

Get-TagSummary | Format-Table -AutoSize

#endregion

#region Tag Compliance Checking
# ============================================================================
# TAG COMPLIANCE AND VALIDATION
# ============================================================================

# Check if all Production VMs have required tags
function Test-ProductionTagCompliance {
    $requiredCategories = @("Environment", "Application", "CostCenter")

    $prodMembers = Get-VergeTagMember -Tag "Production" -ResourceType vms
    $nonCompliant = @()

    foreach ($member in $prodMembers) {
        $vmKey = $member.ResourceKey
        $missingCategories = @()

        foreach ($category in $requiredCategories) {
            $categoryTags = Get-VergeTag -Category $category
            $hasTag = $false

            foreach ($tag in $categoryTags) {
                $tagMembers = Get-VergeTagMember -Tag $tag.Name -ResourceType vms
                if ($tagMembers | Where-Object { $_.ResourceKey -eq $vmKey }) {
                    $hasTag = $true
                    break
                }
            }

            if (-not $hasTag) {
                $missingCategories += $category
            }
        }

        if ($missingCategories.Count -gt 0) {
            $vm = Get-VergeVM -Key $vmKey
            $nonCompliant += [PSCustomObject]@{
                VMName           = $vm.Name
                VMKey            = $vmKey
                MissingCategories = $missingCategories -join ', '
            }
        }
    }

    if ($nonCompliant.Count -eq 0) {
        Write-Host "All Production VMs are compliant with tagging requirements." -ForegroundColor Green
    } else {
        Write-Host "Non-compliant Production VMs:" -ForegroundColor Yellow
        $nonCompliant | Format-Table -AutoSize
    }

    return $nonCompliant
}

# Test-ProductionTagCompliance

#endregion
