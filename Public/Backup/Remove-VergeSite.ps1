function Remove-VergeSite {
    <#
    .SYNOPSIS
        Removes a site connection from VergeOS.

    .DESCRIPTION
        Remove-VergeSite deletes a site connection and all associated sync configurations.
        This is a destructive operation and will remove both incoming and outgoing syncs
        associated with the site.

    .PARAMETER Key
        The key (ID) of the site to remove.

    .PARAMETER Name
        The name of the site to remove.

    .PARAMETER Site
        A site object from Get-VergeSite. Accepts pipeline input.

    .PARAMETER Force
        Suppress confirmation prompts.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeSite -Name "DR-Site"

        Removes the site named "DR-Site" after confirmation.

    .EXAMPLE
        Get-VergeSite -Name "Old-*" | Remove-VergeSite -Force

        Removes all sites with names starting with "Old-" without confirmation.

    .EXAMPLE
        Remove-VergeSite -Key 5 -Force

        Removes the site with key 5 without confirmation.

    .NOTES
        Removing a site will also remove all associated sync configurations.
        This operation cannot be undone.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [PSTypeName('Verge.Site')]
        [PSCustomObject]$Site,

        [Parameter()]
        [switch]$Force,

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
        # Resolve the site
        $targetSite = switch ($PSCmdlet.ParameterSetName) {
            'ByObject' { $Site }
            'ByKey' { Get-VergeSite -Key $Key -Server $Server }
            'ByName' { Get-VergeSite -Name $Name -Server $Server }
        }

        if (-not $targetSite) {
            $identifier = if ($Key) { "Key: $Key" } elseif ($Name) { "Name: $Name" } else { "Unknown" }
            Write-Error -Message "Site not found ($identifier)" -ErrorId 'SiteNotFound'
            return
        }

        $siteKey = $targetSite.Key
        $siteName = $targetSite.Name

        # Check confirmation
        if ($Force) {
            $ConfirmPreference = 'None'
        }

        if ($PSCmdlet.ShouldProcess("Site '$siteName' (Key: $siteKey)", 'Remove')) {
            try {
                Write-Verbose "Removing site '$siteName' (Key: $siteKey)"
                $null = Invoke-VergeAPI -Method DELETE -Endpoint "sites/$siteKey" -Connection $Server
                Write-Verbose "Site '$siteName' removed successfully"
            }
            catch {
                Write-Error -Message "Failed to remove site '$siteName': $($_.Exception.Message)" -ErrorId 'RemoveSiteFailed'
            }
        }
    }
}
