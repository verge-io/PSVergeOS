function Get-VergeTagMember {
    <#
    .SYNOPSIS
        Retrieves tag member assignments from VergeOS.

    .DESCRIPTION
        Get-VergeTagMember retrieves the resources that have been assigned to a tag.
        This shows which VMs, networks, tenants, and other resources have a specific
        tag applied.

    .PARAMETER Tag
        The tag to retrieve members for. Accepts a tag name, key, or Verge.Tag object.

    .PARAMETER Key
        The unique key (ID) of the tag member assignment to retrieve.

    .PARAMETER ResourceType
        Filter by resource type. Valid values include:
        vms, vnets, volumes, tenants, users, groups, nodes, clusters, sites, vnet_rules

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeTagMember -Tag "Production"

        Retrieves all resources tagged with "Production".

    .EXAMPLE
        Get-VergeTag -Name "Production" | Get-VergeTagMember

        Retrieves all resources assigned to the "Production" tag via pipeline.

    .EXAMPLE
        Get-VergeTagMember -Tag "Environment" -ResourceType vms

        Retrieves only VMs tagged with "Environment".

    .EXAMPLE
        Get-VergeTagCategory -Name "Environment" | Get-VergeTag | Get-VergeTagMember

        Retrieves all tag assignments for all tags in the "Environment" category.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.TagMember'

    .NOTES
        Use Add-VergeTagMember to assign tags to resources.
        Use Remove-VergeTagMember to remove tag assignments.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByTag')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByTag', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('TagName', 'TagKey')]
        [object]$Tag,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [Alias('Id', '$key')]
        [int]$Key,

        [Parameter(ParameterSetName = 'ByTag')]
        [ValidateSet('vms', 'vnets', 'volumes', 'tenants', 'users', 'groups', 'nodes', 'clusters', 'sites', 'vnet_rules', 'vmware_containers', 'tenant_nodes')]
        [string]$ResourceType,

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

        # Cache for tag lookups
        $tagCache = @{}
    }

    process {
        try {
            Write-Verbose "Querying tag members from $($Server.Server)"

            # Build query parameters
            $queryParams = @{}
            $filters = [System.Collections.Generic.List[string]]::new()

            if ($PSCmdlet.ParameterSetName -eq 'ByKey') {
                # Filter by key
                $filters.Add("`$key eq $Key")
            }
            else {
                # Resolve tag to key
                $tagKey = $null
                $tagName = $null

                # Handle Verge.Tag object from pipeline
                if ($Tag.PSObject.TypeNames -contains 'Verge.Tag') {
                    $tagKey = $Tag.Key
                    $tagName = $Tag.Name
                    $tagCache["key_$tagKey"] = $tagName
                }
                # Handle integer key
                elseif ($Tag -is [int]) {
                    $tagKey = $Tag
                    $foundTag = Get-VergeTag -Key $tagKey -Server $Server
                    if ($foundTag) {
                        $tagName = $foundTag.Name
                        $tagCache["key_$tagKey"] = $tagName
                    }
                }
                # Handle string (name or key)
                elseif ($Tag -is [string]) {
                    if ($Tag -match '^\d+$') {
                        $tagKey = [int]$Tag
                        $foundTag = Get-VergeTag -Key $tagKey -Server $Server
                        if ($foundTag) {
                            $tagName = $foundTag.Name
                            $tagCache["key_$tagKey"] = $tagName
                        }
                    }
                    else {
                        # Look up tag by name
                        $foundTag = Get-VergeTag -Name $Tag -Server $Server | Select-Object -First 1
                        if ($foundTag) {
                            $tagKey = $foundTag.Key
                            $tagName = $foundTag.Name
                            $tagCache["key_$tagKey"] = $tagName
                        }
                    }
                }

                if (-not $tagKey) {
                    Write-Error -Message "Tag '$Tag' not found" -ErrorId 'TagNotFound' -Category ObjectNotFound
                    return
                }

                $filters.Add("tag eq $tagKey")
            }

            # Apply filters
            if ($filters.Count -gt 0) {
                $queryParams['filter'] = $filters -join ' and '
            }

            # Request all relevant fields using flat_info view for enriched data
            $queryParams['fields'] = @(
                '$key'
                'tag'
                'member'
            ) -join ','

            $response = Invoke-VergeAPI -Method GET -Endpoint 'tag_members' -Query $queryParams -Connection $Server

            # Handle both single object and array responses
            $members = if ($response -is [array]) { $response } else { @($response) }

            foreach ($member in $members) {
                # Skip null entries
                if (-not $member -or -not $member.member) {
                    continue
                }

                # Parse the member reference to get resource type and key
                # API format: vms/123 or vnets/456
                $memberRef = $member.member
                $memberResourceType = $null
                $memberResourceKey = $null
                $memberResourceName = $null

                if ($memberRef -match '^([^/]+)/(\d+)$') {
                    $memberResourceType = $Matches[1]
                    $memberResourceKey = [int]$Matches[2]
                }

                # Filter by resource type if specified
                if ($ResourceType -and $memberResourceType -ne $ResourceType) {
                    continue
                }

                # Get tag name from cache or lookup
                $memberTagKey = $member.tag
                if (-not $tagCache.ContainsKey("key_$memberTagKey")) {
                    $foundTag = Get-VergeTag -Key $memberTagKey -Server $Server -ErrorAction SilentlyContinue
                    if ($foundTag) {
                        $tagCache["key_$memberTagKey"] = $foundTag.Name
                    }
                }
                $memberTagName = $tagCache["key_$memberTagKey"]

                # Create output object
                $output = [PSCustomObject]@{
                    PSTypeName    = 'Verge.TagMember'
                    Key           = [int]$member.'$key'
                    TagKey        = [int]$memberTagKey
                    TagName       = $memberTagName
                    ResourceType  = $memberResourceType
                    ResourceKey   = $memberResourceKey
                    ResourceRef   = $memberRef
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
