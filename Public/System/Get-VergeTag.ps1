function Get-VergeTag {
    <#
    .SYNOPSIS
        Retrieves tags from VergeOS.

    .DESCRIPTION
        Get-VergeTag retrieves one or more tags from a VergeOS system.
        Tags are organized within categories and can be applied to various resources.

    .PARAMETER Name
        The name of the tag to retrieve. Supports wildcards (* and ?).
        If not specified, all tags are returned.

    .PARAMETER Key
        The unique key (ID) of the tag to retrieve.

    .PARAMETER Category
        Filter tags by category. Accepts a category name, key, or Verge.TagCategory object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeTag

        Retrieves all tags from the connected VergeOS system.

    .EXAMPLE
        Get-VergeTag -Name "Production"

        Retrieves a specific tag by name.

    .EXAMPLE
        Get-VergeTag -Name "Dev*"

        Retrieves all tags starting with "Dev".

    .EXAMPLE
        Get-VergeTag -Category "Environment"

        Retrieves all tags in the "Environment" category.

    .EXAMPLE
        Get-VergeTagCategory -Name "Environment" | Get-VergeTag

        Retrieves all tags in the "Environment" category using pipeline.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.Tag'

    .NOTES
        Use New-VergeTag to create tags within a category.
        Use Add-VergeTagMember to apply tags to resources.
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

        [Parameter(ParameterSetName = 'Filter', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('CategoryName', 'CategoryKey')]
        [object]$Category,

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

        # Cache for category lookups
        $categoryCache = @{}
    }

    process {
        try {
            Write-Verbose "Querying tags from $($Server.Server)"

            # Build query parameters
            $queryParams = @{}
            $filters = [System.Collections.Generic.List[string]]::new()

            # Filter by key
            if ($PSCmdlet.ParameterSetName -eq 'ByKey') {
                $filters.Add("`$key eq $Key")
            }
            else {
                # Filter by name
                if ($Name) {
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

                # Filter by category
                if ($Category) {
                    $categoryKey = $null

                    # Handle Verge.TagCategory object from pipeline
                    if ($Category.PSObject.TypeNames -contains 'Verge.TagCategory') {
                        $categoryKey = $Category.Key
                    }
                    # Handle integer key
                    elseif ($Category -is [int]) {
                        $categoryKey = $Category
                    }
                    # Handle string (name or key)
                    elseif ($Category -is [string]) {
                        if ($Category -match '^\d+$') {
                            $categoryKey = [int]$Category
                        }
                        else {
                            # Look up category by name
                            if (-not $categoryCache.ContainsKey($Category)) {
                                $foundCategory = Get-VergeTagCategory -Name $Category -Server $Server | Select-Object -First 1
                                if ($foundCategory) {
                                    $categoryCache[$Category] = $foundCategory.Key
                                }
                            }
                            $categoryKey = $categoryCache[$Category]

                            if (-not $categoryKey) {
                                Write-Error -Message "Tag category '$Category' not found" -ErrorId 'CategoryNotFound'
                                return
                            }
                        }
                    }

                    if ($categoryKey) {
                        $filters.Add("category eq $categoryKey")
                    }
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
                'category'
                'created'
                'modified'
            ) -join ','

            $response = Invoke-VergeAPI -Method GET -Endpoint 'tags' -Query $queryParams -Connection $Server

            # Handle both single object and array responses
            $tags = if ($response -is [array]) { $response } else { @($response) }

            foreach ($tag in $tags) {
                # Skip null entries
                if (-not $tag -or -not $tag.name) {
                    continue
                }

                # Apply wildcard filtering for client-side matching
                if ($Name -and ($Name -match '[\*\?]')) {
                    if ($tag.name -notlike $Name) {
                        continue
                    }
                }

                # Look up category name if needed
                $categoryName = $null
                $categoryKeyValue = $tag.category
                if ($categoryKeyValue) {
                    if (-not $categoryCache.ContainsKey("key_$categoryKeyValue")) {
                        $foundCategory = Get-VergeTagCategory -Key $categoryKeyValue -Server $Server
                        if ($foundCategory) {
                            $categoryCache["key_$categoryKeyValue"] = $foundCategory.Name
                        }
                    }
                    $categoryName = $categoryCache["key_$categoryKeyValue"]
                }

                # Create output object
                $output = [PSCustomObject]@{
                    PSTypeName   = 'Verge.Tag'
                    Key          = [int]$tag.'$key'
                    Name         = $tag.name
                    Description  = $tag.description
                    CategoryKey  = [int]$categoryKeyValue
                    CategoryName = $categoryName
                    Created      = if ($tag.created) { [DateTimeOffset]::FromUnixTimeSeconds($tag.created).LocalDateTime } else { $null }
                    Modified     = if ($tag.modified) { [DateTimeOffset]::FromUnixTimeSeconds($tag.modified).LocalDateTime } else { $null }
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
