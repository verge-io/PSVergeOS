function Set-VergeTag {
    <#
    .SYNOPSIS
        Modifies the configuration of a VergeOS tag.

    .DESCRIPTION
        Set-VergeTag modifies tag settings such as name and description.
        Tags can be identified by name, key, or piped from Get-VergeTag.

    .PARAMETER Tag
        A tag object from Get-VergeTag. Accepts pipeline input.

    .PARAMETER Name
        The name of the tag to modify.

    .PARAMETER Key
        The key (ID) of the tag to modify.

    .PARAMETER NewName
        Rename the tag to this new name.

    .PARAMETER Description
        Set the tag description.

    .PARAMETER PassThru
        Return the modified tag object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Set-VergeTag -Name "Production" -Description "Production workloads"

        Updates the description of a tag.

    .EXAMPLE
        Get-VergeTag -Name "Dev" | Set-VergeTag -NewName "Development" -PassThru

        Renames a tag using pipeline input.

    .EXAMPLE
        Set-VergeTag -Key 1 -NewName "Prod" -Description "Production environment"

        Modifies a tag by its key.

    .OUTPUTS
        None by default. Verge.Tag when -PassThru is specified.

    .NOTES
        Tag names must be unique within their category.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByTag')]
        [PSTypeName('Verge.Tag')]
        [PSCustomObject]$Tag,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter()]
        [string]$NewName,

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
        # Resolve tag based on parameter set
        $targetTag = switch ($PSCmdlet.ParameterSetName) {
            'ByName' {
                Get-VergeTag -Name $Name -Server $Server | Select-Object -First 1
            }
            'ByKey' {
                Get-VergeTag -Key $Key -Server $Server
            }
            'ByTag' {
                $Tag
            }
        }

        if (-not $targetTag) {
            Write-Error -Message "Tag not found" -ErrorId 'TagNotFound'
            return
        }

        # Build the update body with only specified parameters
        $body = @{}
        $changes = [System.Collections.Generic.List[string]]::new()

        if ($PSBoundParameters.ContainsKey('NewName')) {
            $body['name'] = $NewName
            $changes.Add("Name: $($targetTag.Name) -> $NewName")
        }

        if ($PSBoundParameters.ContainsKey('Description')) {
            $body['description'] = $Description
            $changes.Add("Description updated")
        }

        # Check if there are any changes to make
        if ($body.Count -eq 0) {
            Write-Warning "No changes specified for tag '$($targetTag.Name)'"
            if ($PassThru) {
                Write-Output $targetTag
            }
            return
        }

        # Build change summary for confirmation
        $changeSummary = $changes -join ', '
        $tagDisplay = "$($targetTag.Name) (Category: $($targetTag.CategoryName))"

        if ($PSCmdlet.ShouldProcess($tagDisplay, "Modify Tag ($changeSummary)")) {
            try {
                Write-Verbose "Modifying tag '$($targetTag.Name)' (Key: $($targetTag.Key))"
                Write-Verbose "Changes: $changeSummary"

                $response = Invoke-VergeAPI -Method PUT -Endpoint "tags/$($targetTag.Key)" -Body $body -Connection $Server

                Write-Verbose "Tag '$($targetTag.Name)' modified successfully"

                if ($PassThru) {
                    # Return the updated tag
                    Start-Sleep -Milliseconds 500
                    Get-VergeTag -Key $targetTag.Key -Server $Server
                }
            }
            catch {
                $errorMessage = $_.Exception.Message
                if ($errorMessage -match 'already in use' -or $errorMessage -match 'unique') {
                    throw "A tag with the name '$NewName' already exists in category '$($targetTag.CategoryName)'."
                }
                Write-Error -Message "Failed to modify tag '$($targetTag.Name)': $errorMessage" -ErrorId 'TagModifyFailed'
            }
        }
    }
}
