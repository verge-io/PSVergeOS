function New-VergeTagCategory {
    <#
    .SYNOPSIS
        Creates a new tag category in VergeOS.

    .DESCRIPTION
        New-VergeTagCategory creates a new tag category with the specified configuration.
        Tag categories organize tags and define which resource types can be tagged.

    .PARAMETER Name
        The name of the new tag category. Must be unique.

    .PARAMETER Description
        An optional description for the tag category.

    .PARAMETER SingleTagSelection
        When enabled, only one tag from this category can be applied to a resource.
        Default is false (multiple tags allowed).

    .PARAMETER TaggableVMs
        Allow tags in this category to be applied to virtual machines.

    .PARAMETER TaggableNetworks
        Allow tags in this category to be applied to networks.

    .PARAMETER TaggableVolumes
        Allow tags in this category to be applied to volumes.

    .PARAMETER TaggableNetworkRules
        Allow tags in this category to be applied to network rules.

    .PARAMETER TaggableVMwareContainers
        Allow tags in this category to be applied to VMware containers.

    .PARAMETER TaggableUsers
        Allow tags in this category to be applied to users.

    .PARAMETER TaggableTenantNodes
        Allow tags in this category to be applied to tenant nodes.

    .PARAMETER TaggableSites
        Allow tags in this category to be applied to sites.

    .PARAMETER TaggableNodes
        Allow tags in this category to be applied to nodes.

    .PARAMETER TaggableGroups
        Allow tags in this category to be applied to groups.

    .PARAMETER TaggableClusters
        Allow tags in this category to be applied to clusters.

    .PARAMETER TaggableTenants
        Allow tags in this category to be applied to tenants.

    .PARAMETER PassThru
        Return the created tag category object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeTagCategory -Name "Environment" -TaggableVMs

        Creates a tag category for environment tags that can be applied to VMs.

    .EXAMPLE
        New-VergeTagCategory -Name "Department" -Description "Business department" -SingleTagSelection -TaggableVMs -TaggableUsers -PassThru

        Creates a single-selection department category for VMs and users.

    .EXAMPLE
        New-VergeTagCategory -Name "Application" -TaggableVMs -TaggableNetworks -TaggableVolumes

        Creates an application category that can tag VMs, networks, and volumes.

    .OUTPUTS
        None by default. Verge.TagCategory when -PassThru is specified.

    .NOTES
        After creating a category, use New-VergeTag to create tags within it.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [switch]$SingleTagSelection,

        [Parameter()]
        [switch]$TaggableVMs,

        [Parameter()]
        [switch]$TaggableNetworks,

        [Parameter()]
        [switch]$TaggableVolumes,

        [Parameter()]
        [switch]$TaggableNetworkRules,

        [Parameter()]
        [switch]$TaggableVMwareContainers,

        [Parameter()]
        [switch]$TaggableUsers,

        [Parameter()]
        [switch]$TaggableTenantNodes,

        [Parameter()]
        [switch]$TaggableSites,

        [Parameter()]
        [switch]$TaggableNodes,

        [Parameter()]
        [switch]$TaggableGroups,

        [Parameter()]
        [switch]$TaggableClusters,

        [Parameter()]
        [switch]$TaggableTenants,

        [Parameter()]
        [switch]$PassThru,

        [Parameter()]
        [object]$Server
    )

    begin {
        # Resolve connection
        if (-not $Server) {
            $Server = $script:DefaultConnection
        }
        if (-not $Server) {
            throw [System.InvalidOperationException]::new(
                'Not connected to VergeOS. Use Connect-VergeOS to establish a connection.'
            )
        }
    }

    process {
        # Build request body
        $body = @{
            name = $Name
        }

        # Add optional parameters
        if ($Description) {
            $body['description'] = $Description
        }

        if ($SingleTagSelection) {
            $body['single_tag_selection'] = $true
        }

        if ($TaggableVMs) {
            $body['taggable_vms'] = $true
        }

        if ($TaggableNetworks) {
            $body['taggable_vnets'] = $true
        }

        if ($TaggableVolumes) {
            $body['taggable_volumes'] = $true
        }

        if ($TaggableNetworkRules) {
            $body['taggable_vnet_rules'] = $true
        }

        if ($TaggableVMwareContainers) {
            $body['taggable_vmware_containers'] = $true
        }

        if ($TaggableUsers) {
            $body['taggable_users'] = $true
        }

        if ($TaggableTenantNodes) {
            $body['taggable_tenant_nodes'] = $true
        }

        if ($TaggableSites) {
            $body['taggable_sites'] = $true
        }

        if ($TaggableNodes) {
            $body['taggable_nodes'] = $true
        }

        if ($TaggableGroups) {
            $body['taggable_groups'] = $true
        }

        if ($TaggableClusters) {
            $body['taggable_clusters'] = $true
        }

        if ($TaggableTenants) {
            $body['taggable_tenants'] = $true
        }

        if ($PSCmdlet.ShouldProcess($Name, 'Create Tag Category')) {
            try {
                Write-Verbose "Creating tag category '$Name'"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'tag_categories' -Body $body -Connection $Server

                # Get the created category key
                $categoryKey = $response.'$key'
                if (-not $categoryKey -and $response.key) {
                    $categoryKey = $response.key
                }

                Write-Verbose "Tag category '$Name' created with Key: $categoryKey"

                if ($PassThru -and $categoryKey) {
                    # Return the created category
                    Start-Sleep -Milliseconds 500
                    Get-VergeTagCategory -Key $categoryKey -Server $Server
                }
            }
            catch {
                $errorMessage = $_.Exception.Message
                if ($errorMessage -match 'already in use' -or $errorMessage -match 'unique') {
                    throw "A tag category with the name '$Name' already exists."
                }
                throw "Failed to create tag category '$Name': $errorMessage"
            }
        }
    }
}
