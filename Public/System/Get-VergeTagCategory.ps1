function Get-VergeTagCategory {
    <#
    .SYNOPSIS
        Retrieves tag categories from VergeOS.

    .DESCRIPTION
        Get-VergeTagCategory retrieves one or more tag categories from a VergeOS system.
        Tag categories organize tags and define which resource types can be tagged.

    .PARAMETER Name
        The name of the tag category to retrieve. Supports wildcards (* and ?).
        If not specified, all tag categories are returned.

    .PARAMETER Key
        The unique key (ID) of the tag category to retrieve.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeTagCategory

        Retrieves all tag categories from the connected VergeOS system.

    .EXAMPLE
        Get-VergeTagCategory -Name "Environment"

        Retrieves a specific tag category by name.

    .EXAMPLE
        Get-VergeTagCategory -Name "App*"

        Retrieves all tag categories starting with "App".

    .EXAMPLE
        Get-VergeTagCategory | Where-Object TaggableVMs -eq $true

        Lists tag categories that can be applied to VMs.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.TagCategory'

    .NOTES
        Use Get-VergeTag to retrieve tags within a category.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Filter')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ParameterSetName = 'Filter')]
        [SupportsWildcards()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey', ValueFromPipelineByPropertyName)]
        [Alias('Id', '$key')]
        [int]$Key,

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
        try {
            Write-Verbose "Querying tag categories from $($Server.Server)"

            # Build query parameters
            $queryParams = @{}
            $filters = [System.Collections.Generic.List[string]]::new()

            # Filter by key
            if ($PSCmdlet.ParameterSetName -eq 'ByKey') {
                $filters.Add("`$key eq $Key")
            }
            elseif ($Name) {
                if ($Name -match '[\*\?]') {
                    $searchTerm = $Name -replace '[\*\?]', ''
                    if ($searchTerm) {
                        $filters.Add("name ct '$searchTerm'")
                    }
                }
                else {
                    $filters.Add("name eq '$Name'")
                }
            }

            # Apply filters
            if ($filters.Count -gt 0) {
                $queryParams['filter'] = $filters -join ' and '
            }

            # Request all relevant fields
            $queryParams['fields'] = @(
                '$key'
                'name'
                'description'
                'single_tag_selection'
                'taggable_vms'
                'taggable_vnets'
                'taggable_volumes'
                'taggable_vnet_rules'
                'taggable_vmware_containers'
                'taggable_users'
                'taggable_tenant_nodes'
                'taggable_sites'
                'taggable_nodes'
                'taggable_groups'
                'taggable_clusters'
                'taggable_tenants'
                'created'
                'modified'
            ) -join ','

            $response = Invoke-VergeAPI -Method GET -Endpoint 'tag_categories' -Query $queryParams -Connection $Server

            # Handle both single object and array responses
            $categories = if ($response -is [array]) { $response } else { @($response) }

            foreach ($category in $categories) {
                # Skip null entries
                if (-not $category -or -not $category.name) {
                    continue
                }

                # Apply wildcard filtering for client-side matching
                if ($Name -and ($Name -match '[\*\?]')) {
                    if ($category.name -notlike $Name) {
                        continue
                    }
                }

                # Create output object
                $output = [PSCustomObject]@{
                    PSTypeName              = 'Verge.TagCategory'
                    Key                     = [int]$category.'$key'
                    Name                    = $category.name
                    Description             = $category.description
                    SingleTagSelection      = [bool]$category.single_tag_selection
                    TaggableVMs             = [bool]$category.taggable_vms
                    TaggableNetworks        = [bool]$category.taggable_vnets
                    TaggableVolumes         = [bool]$category.taggable_volumes
                    TaggableNetworkRules    = [bool]$category.taggable_vnet_rules
                    TaggableVMwareContainers = [bool]$category.taggable_vmware_containers
                    TaggableUsers           = [bool]$category.taggable_users
                    TaggableTenantNodes     = [bool]$category.taggable_tenant_nodes
                    TaggableSites           = [bool]$category.taggable_sites
                    TaggableNodes           = [bool]$category.taggable_nodes
                    TaggableGroups          = [bool]$category.taggable_groups
                    TaggableClusters        = [bool]$category.taggable_clusters
                    TaggableTenants         = [bool]$category.taggable_tenants
                    Created                 = if ($category.created) { [DateTimeOffset]::FromUnixTimeSeconds($category.created).LocalDateTime } else { $null }
                    Modified                = if ($category.modified) { [DateTimeOffset]::FromUnixTimeSeconds($category.modified).LocalDateTime } else { $null }
                }

                # Add hidden properties for pipeline support
                $output | Add-Member -MemberType NoteProperty -Name '_Connection' -Value $Server -Force

                Write-Output $output
            }
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}
