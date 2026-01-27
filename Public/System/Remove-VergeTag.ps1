function Remove-VergeTag {
    <#
    .SYNOPSIS
        Deletes a VergeOS tag.

    .DESCRIPTION
        Remove-VergeTag deletes one or more tags from VergeOS.
        This will also remove all tag assignments (tag members) for this tag.
        The cmdlet supports pipeline input from Get-VergeTag for bulk operations.

    .PARAMETER Name
        The name of the tag to delete. Supports wildcards (* and ?).

    .PARAMETER Key
        The unique key (ID) of the tag to delete.

    .PARAMETER Tag
        A tag object from Get-VergeTag. Accepts pipeline input.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeTag -Name "Development"

        Deletes the tag named "Development" after confirmation.

    .EXAMPLE
        Remove-VergeTag -Name "Development" -Confirm:$false

        Deletes the tag without confirmation prompt.

    .EXAMPLE
        Get-VergeTag -Name "Test*" | Remove-VergeTag

        Deletes all tags starting with "Test".

    .EXAMPLE
        Get-VergeTag -Category "Environment" | Remove-VergeTag -Confirm:$false

        Deletes all tags in the "Environment" category without confirmation.

    .OUTPUTS
        None

    .NOTES
        Deleting a tag will remove all tag assignments to resources.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [SupportsWildcards()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByTag')]
        [PSTypeName('Verge.Tag')]
        [PSCustomObject]$Tag,

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
        # Get tags to delete based on parameter set
        $tagsToDelete = switch ($PSCmdlet.ParameterSetName) {
            'ByName' {
                Get-VergeTag -Name $Name -Server $Server
            }
            'ByKey' {
                Get-VergeTag -Key $Key -Server $Server
            }
            'ByTag' {
                $Tag
            }
        }

        foreach ($targetTag in $tagsToDelete) {
            if (-not $targetTag) {
                continue
            }

            # Build display string for confirmation
            $tagDisplay = "$($targetTag.Name) (Category: $($targetTag.CategoryName))"

            # Confirm deletion
            if ($PSCmdlet.ShouldProcess($tagDisplay, 'Remove Tag')) {
                try {
                    Write-Verbose "Deleting tag '$($targetTag.Name)' (Key: $($targetTag.Key))"
                    $response = Invoke-VergeAPI -Method DELETE -Endpoint "tags/$($targetTag.Key)" -Connection $Server

                    Write-Verbose "Tag '$($targetTag.Name)' deleted successfully"
                }
                catch {
                    $errorMessage = $_.Exception.Message
                    Write-Error -Message "Failed to delete tag '$($targetTag.Name)': $errorMessage" -ErrorId 'TagDeleteFailed'
                }
            }
        }
    }
}
