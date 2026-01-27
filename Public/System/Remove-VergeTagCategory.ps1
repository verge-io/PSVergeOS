function Remove-VergeTagCategory {
    <#
    .SYNOPSIS
        Deletes a VergeOS tag category.

    .DESCRIPTION
        Remove-VergeTagCategory deletes one or more tag categories from VergeOS.
        This will also delete all tags within the category (cascade delete).
        The cmdlet supports pipeline input from Get-VergeTagCategory for bulk operations.

    .PARAMETER Name
        The name of the tag category to delete. Supports wildcards (* and ?).

    .PARAMETER Key
        The unique key (ID) of the tag category to delete.

    .PARAMETER TagCategory
        A tag category object from Get-VergeTagCategory. Accepts pipeline input.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeTagCategory -Name "Test-Category"

        Deletes the tag category named "Test-Category" after confirmation.

    .EXAMPLE
        Remove-VergeTagCategory -Name "Test-Category" -Confirm:$false

        Deletes the tag category without confirmation prompt.

    .EXAMPLE
        Get-VergeTagCategory -Name "PSTest-*" | Remove-VergeTagCategory

        Deletes all tag categories starting with "PSTest-".

    .OUTPUTS
        None

    .NOTES
        Deleting a tag category will also delete all tags within the category.
        Tag assignments to resources will be removed.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [SupportsWildcards()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByTagCategory')]
        [PSTypeName('Verge.TagCategory')]
        [PSCustomObject]$TagCategory,

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
        # Get tag categories to delete based on parameter set
        $categoriesToDelete = switch ($PSCmdlet.ParameterSetName) {
            'ByName' {
                Get-VergeTagCategory -Name $Name -Server $Server
            }
            'ByKey' {
                Get-VergeTagCategory -Key $Key -Server $Server
            }
            'ByTagCategory' {
                $TagCategory
            }
        }

        foreach ($targetCategory in $categoriesToDelete) {
            if (-not $targetCategory) {
                continue
            }

            # Confirm deletion
            if ($PSCmdlet.ShouldProcess($targetCategory.Name, 'Remove Tag Category')) {
                try {
                    Write-Verbose "Deleting tag category '$($targetCategory.Name)' (Key: $($targetCategory.Key))"
                    $response = Invoke-VergeAPI -Method DELETE -Endpoint "tag_categories/$($targetCategory.Key)" -Connection $Server

                    Write-Verbose "Tag category '$($targetCategory.Name)' deleted successfully"
                }
                catch {
                    $errorMessage = $_.Exception.Message
                    Write-Error -Message "Failed to delete tag category '$($targetCategory.Name)': $errorMessage" -ErrorId 'TagCategoryDeleteFailed'
                }
            }
        }
    }
}
