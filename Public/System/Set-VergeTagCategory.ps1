function Set-VergeTagCategory {
    <#
    .SYNOPSIS
        Modifies the configuration of a VergeOS tag category.

    .DESCRIPTION
        Set-VergeTagCategory modifies tag category settings such as name, description,
        and which resource types can be tagged.

    .PARAMETER TagCategory
        A tag category object from Get-VergeTagCategory. Accepts pipeline input.

    .PARAMETER Name
        The name of the tag category to modify.

    .PARAMETER Key
        The key (ID) of the tag category to modify.

    .PARAMETER NewName
        Rename the tag category to this new name.

    .PARAMETER Description
        Set the tag category description.

    .PARAMETER SingleTagSelection
        Enable or disable single tag selection mode.

    .PARAMETER TaggableVMs
        Enable or disable tagging virtual machines.

    .PARAMETER TaggableNetworks
        Enable or disable tagging networks.

    .PARAMETER TaggableVolumes
        Enable or disable tagging volumes.

    .PARAMETER TaggableNetworkRules
        Enable or disable tagging network rules.

    .PARAMETER TaggableVMwareContainers
        Enable or disable tagging VMware containers.

    .PARAMETER TaggableUsers
        Enable or disable tagging users.

    .PARAMETER TaggableTenantNodes
        Enable or disable tagging tenant nodes.

    .PARAMETER TaggableSites
        Enable or disable tagging sites.

    .PARAMETER TaggableNodes
        Enable or disable tagging nodes.

    .PARAMETER TaggableGroups
        Enable or disable tagging groups.

    .PARAMETER TaggableClusters
        Enable or disable tagging clusters.

    .PARAMETER TaggableTenants
        Enable or disable tagging tenants.

    .PARAMETER PassThru
        Return the modified tag category object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Set-VergeTagCategory -Name "Environment" -Description "Production environments"

        Updates the description of a tag category.

    .EXAMPLE
        Get-VergeTagCategory -Name "Department" | Set-VergeTagCategory -TaggableVMs $true -TaggableTenants $true

        Enables VM and tenant tagging for the Department category.

    .EXAMPLE
        Set-VergeTagCategory -Name "OldName" -NewName "NewName" -PassThru

        Renames a tag category and returns the updated object.

    .OUTPUTS
        None by default. Verge.TagCategory when -PassThru is specified.

    .NOTES
        Changes take effect immediately for new tag assignments.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByTagCategory')]
        [PSTypeName('Verge.TagCategory')]
        [PSCustomObject]$TagCategory,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter()]
        [string]$NewName,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [bool]$SingleTagSelection,

        [Parameter()]
        [bool]$TaggableVMs,

        [Parameter()]
        [bool]$TaggableNetworks,

        [Parameter()]
        [bool]$TaggableVolumes,

        [Parameter()]
        [bool]$TaggableNetworkRules,

        [Parameter()]
        [bool]$TaggableVMwareContainers,

        [Parameter()]
        [bool]$TaggableUsers,

        [Parameter()]
        [bool]$TaggableTenantNodes,

        [Parameter()]
        [bool]$TaggableSites,

        [Parameter()]
        [bool]$TaggableNodes,

        [Parameter()]
        [bool]$TaggableGroups,

        [Parameter()]
        [bool]$TaggableClusters,

        [Parameter()]
        [bool]$TaggableTenants,

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
        # Resolve tag category based on parameter set
        $targetCategory = switch ($PSCmdlet.ParameterSetName) {
            'ByName' {
                Get-VergeTagCategory -Name $Name -Server $Server | Select-Object -First 1
            }
            'ByKey' {
                Get-VergeTagCategory -Key $Key -Server $Server
            }
            'ByTagCategory' {
                $TagCategory
            }
        }

        if (-not $targetCategory) {
            Write-Error -Message "Tag category not found" -ErrorId 'TagCategoryNotFound'
            return
        }

        # Build the update body with only specified parameters
        $body = @{}
        $changes = [System.Collections.Generic.List[string]]::new()

        if ($PSBoundParameters.ContainsKey('NewName')) {
            $body['name'] = $NewName
            $changes.Add("Name: $($targetCategory.Name) -> $NewName")
        }

        if ($PSBoundParameters.ContainsKey('Description')) {
            $body['description'] = $Description
            $changes.Add("Description updated")
        }

        if ($PSBoundParameters.ContainsKey('SingleTagSelection')) {
            $body['single_tag_selection'] = $SingleTagSelection
            $changes.Add("Single Tag Selection: $SingleTagSelection")
        }

        if ($PSBoundParameters.ContainsKey('TaggableVMs')) {
            $body['taggable_vms'] = $TaggableVMs
            $changes.Add("Taggable VMs: $TaggableVMs")
        }

        if ($PSBoundParameters.ContainsKey('TaggableNetworks')) {
            $body['taggable_vnets'] = $TaggableNetworks
            $changes.Add("Taggable Networks: $TaggableNetworks")
        }

        if ($PSBoundParameters.ContainsKey('TaggableVolumes')) {
            $body['taggable_volumes'] = $TaggableVolumes
            $changes.Add("Taggable Volumes: $TaggableVolumes")
        }

        if ($PSBoundParameters.ContainsKey('TaggableNetworkRules')) {
            $body['taggable_vnet_rules'] = $TaggableNetworkRules
            $changes.Add("Taggable Network Rules: $TaggableNetworkRules")
        }

        if ($PSBoundParameters.ContainsKey('TaggableVMwareContainers')) {
            $body['taggable_vmware_containers'] = $TaggableVMwareContainers
            $changes.Add("Taggable VMware Containers: $TaggableVMwareContainers")
        }

        if ($PSBoundParameters.ContainsKey('TaggableUsers')) {
            $body['taggable_users'] = $TaggableUsers
            $changes.Add("Taggable Users: $TaggableUsers")
        }

        if ($PSBoundParameters.ContainsKey('TaggableTenantNodes')) {
            $body['taggable_tenant_nodes'] = $TaggableTenantNodes
            $changes.Add("Taggable Tenant Nodes: $TaggableTenantNodes")
        }

        if ($PSBoundParameters.ContainsKey('TaggableSites')) {
            $body['taggable_sites'] = $TaggableSites
            $changes.Add("Taggable Sites: $TaggableSites")
        }

        if ($PSBoundParameters.ContainsKey('TaggableNodes')) {
            $body['taggable_nodes'] = $TaggableNodes
            $changes.Add("Taggable Nodes: $TaggableNodes")
        }

        if ($PSBoundParameters.ContainsKey('TaggableGroups')) {
            $body['taggable_groups'] = $TaggableGroups
            $changes.Add("Taggable Groups: $TaggableGroups")
        }

        if ($PSBoundParameters.ContainsKey('TaggableClusters')) {
            $body['taggable_clusters'] = $TaggableClusters
            $changes.Add("Taggable Clusters: $TaggableClusters")
        }

        if ($PSBoundParameters.ContainsKey('TaggableTenants')) {
            $body['taggable_tenants'] = $TaggableTenants
            $changes.Add("Taggable Tenants: $TaggableTenants")
        }

        # Check if there are any changes to make
        if ($body.Count -eq 0) {
            Write-Warning "No changes specified for tag category '$($targetCategory.Name)'"
            if ($PassThru) {
                Write-Output $targetCategory
            }
            return
        }

        # Build change summary for confirmation
        $changeSummary = $changes -join ', '

        if ($PSCmdlet.ShouldProcess($targetCategory.Name, "Modify Tag Category ($changeSummary)")) {
            try {
                Write-Verbose "Modifying tag category '$($targetCategory.Name)' (Key: $($targetCategory.Key))"
                Write-Verbose "Changes: $changeSummary"

                $response = Invoke-VergeAPI -Method PUT -Endpoint "tag_categories/$($targetCategory.Key)" -Body $body -Connection $Server

                Write-Verbose "Tag category '$($targetCategory.Name)' modified successfully"

                if ($PassThru) {
                    # Return the updated category
                    Start-Sleep -Milliseconds 500
                    Get-VergeTagCategory -Key $targetCategory.Key -Server $Server
                }
            }
            catch {
                Write-Error -Message "Failed to modify tag category '$($targetCategory.Name)': $($_.Exception.Message)" -ErrorId 'TagCategoryModifyFailed'
            }
        }
    }
}
