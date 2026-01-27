function New-VergeTag {
    <#
    .SYNOPSIS
        Creates a new tag in VergeOS.

    .DESCRIPTION
        New-VergeTag creates a new tag within a specified category.
        Tags can then be applied to various resources using Add-VergeTagMember.

    .PARAMETER Name
        The name of the new tag. Must be unique within the category.

    .PARAMETER Category
        The category for the tag. Accepts a category name, key, or Verge.TagCategory object.

    .PARAMETER Description
        An optional description for the tag.

    .PARAMETER PassThru
        Return the created tag object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeTag -Name "Production" -Category "Environment"

        Creates a "Production" tag in the "Environment" category.

    .EXAMPLE
        New-VergeTag -Name "Development" -Category "Environment" -Description "Development environment" -PassThru

        Creates a tag with description and returns the created object.

    .EXAMPLE
        Get-VergeTagCategory -Name "Environment" | ForEach-Object {
            New-VergeTag -Name "Production" -Category $_
            New-VergeTag -Name "Staging" -Category $_
            New-VergeTag -Name "Development" -Category $_
        }

        Creates multiple tags in a category using pipeline.

    .OUTPUTS
        None by default. Verge.Tag when -PassThru is specified.

    .NOTES
        After creating a tag, use Add-VergeTagMember to apply it to resources.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory, Position = 1, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('CategoryName', 'CategoryKey')]
        [object]$Category,

        [Parameter()]
        [string]$Description,

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
        # Resolve category to key
        $categoryKey = $null
        $categoryName = $null

        # Handle Verge.TagCategory object from pipeline
        if ($Category.PSObject.TypeNames -contains 'Verge.TagCategory') {
            $categoryKey = $Category.Key
            $categoryName = $Category.Name
        }
        # Handle integer key
        elseif ($Category -is [int]) {
            $categoryKey = $Category
            $foundCategory = Get-VergeTagCategory -Key $categoryKey -Server $Server
            if ($foundCategory) {
                $categoryName = $foundCategory.Name
            }
        }
        # Handle string (name or key)
        elseif ($Category -is [string]) {
            if ($Category -match '^\d+$') {
                $categoryKey = [int]$Category
                $foundCategory = Get-VergeTagCategory -Key $categoryKey -Server $Server
                if ($foundCategory) {
                    $categoryName = $foundCategory.Name
                }
            }
            else {
                # Look up category by name
                $foundCategory = Get-VergeTagCategory -Name $Category -Server $Server | Select-Object -First 1
                if ($foundCategory) {
                    $categoryKey = $foundCategory.Key
                    $categoryName = $foundCategory.Name
                }
            }
        }

        if (-not $categoryKey) {
            throw "Tag category '$Category' not found. Use Get-VergeTagCategory to list available categories."
        }

        # Build request body
        $body = @{
            name     = $Name
            category = $categoryKey
        }

        # Add optional parameters
        if ($Description) {
            $body['description'] = $Description
        }

        if ($PSCmdlet.ShouldProcess("$Name (in category: $categoryName)", 'Create Tag')) {
            try {
                Write-Verbose "Creating tag '$Name' in category '$categoryName' (Key: $categoryKey)"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'tags' -Body $body -Connection $Server

                # Get the created tag key
                $tagKey = $response.'$key'
                if (-not $tagKey -and $response.key) {
                    $tagKey = $response.key
                }

                Write-Verbose "Tag '$Name' created with Key: $tagKey"

                if ($PassThru -and $tagKey) {
                    # Return the created tag
                    Start-Sleep -Milliseconds 500
                    Get-VergeTag -Key $tagKey -Server $Server
                }
            }
            catch {
                $errorMessage = $_.Exception.Message
                if ($errorMessage -match 'already in use' -or $errorMessage -match 'unique') {
                    throw "A tag with the name '$Name' already exists in category '$categoryName'."
                }
                throw "Failed to create tag '$Name': $errorMessage"
            }
        }
    }
}
