function Remove-VergeNetworkRule {
    <#
    .SYNOPSIS
        Deletes a firewall rule from a VergeOS virtual network.

    .DESCRIPTION
        Remove-VergeNetworkRule deletes one or more firewall rules from a network.
        After deleting rules, use Invoke-VergeNetworkApply to apply the changes.

    .PARAMETER Network
        The name or key of the network containing the rule.

    .PARAMETER Name
        The name of the rule to delete. Supports wildcards (* and ?).

    .PARAMETER Key
        The unique key (ID) of the rule to delete.

    .PARAMETER Rule
        A rule object from Get-VergeNetworkRule. Accepts pipeline input.

    .PARAMETER Apply
        Automatically apply rules after deletion.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeNetworkRule -Network "External" -Name "Test Rule"

        Deletes the "Test Rule" from the External network.

    .EXAMPLE
        Remove-VergeNetworkRule -Network "External" -Name "Test*" -Confirm:$false

        Deletes all rules starting with "Test" without confirmation.

    .EXAMPLE
        Get-VergeNetworkRule -Network "External" -Enabled $false | Remove-VergeNetworkRule -Apply

        Removes all disabled rules and applies changes.

    .OUTPUTS
        None

    .NOTES
        System rules cannot be deleted.
        Rule deletions are not active until Invoke-VergeNetworkApply is called, or use -Apply.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByKey')]
        [string]$Network,

        [Parameter(Mandatory, Position = 1, ParameterSetName = 'ByName')]
        [SupportsWildcards()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByRule')]
        [PSTypeName('Verge.NetworkRule')]
        [PSCustomObject]$Rule,

        [Parameter()]
        [switch]$Apply,

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

        # Track networks that need apply
        $networksToApply = [System.Collections.Generic.HashSet[int]]::new()
    }

    process {
        # Get rules to delete
        $rulesToDelete = switch ($PSCmdlet.ParameterSetName) {
            'ByName' {
                Get-VergeNetworkRule -Network $Network -Name $Name -Server $Server
            }
            'ByKey' {
                Get-VergeNetworkRule -Network $Network -Key $Key -Server $Server
            }
            'ByRule' {
                $Rule
            }
        }

        foreach ($targetRule in $rulesToDelete) {
            if (-not $targetRule) {
                continue
            }

            # Check for system rule
            if ($targetRule.SystemRule) {
                Write-Error -Message "Cannot delete system rule '$($targetRule.Name)'" -ErrorId 'CannotDeleteSystemRule'
                continue
            }

            if ($PSCmdlet.ShouldProcess($targetRule.Name, "Remove Rule from $($targetRule.NetworkName)")) {
                try {
                    Write-Verbose "Deleting rule '$($targetRule.Name)' (Key: $($targetRule.Key))"
                    $response = Invoke-VergeAPI -Method DELETE -Endpoint "vnet_rules/$($targetRule.Key)" -Connection $Server

                    Write-Verbose "Rule '$($targetRule.Name)' deleted successfully"

                    # Track network for apply
                    if ($Apply) {
                        $null = $networksToApply.Add($targetRule.NetworkKey)
                    }
                }
                catch {
                    Write-Error -Message "Failed to delete rule '$($targetRule.Name)': $($_.Exception.Message)" -ErrorId 'RuleDeleteFailed'
                }
            }
        }
    }

    end {
        # Apply rules on affected networks
        if ($Apply -and $networksToApply.Count -gt 0) {
            foreach ($networkKey in $networksToApply) {
                Write-Verbose "Applying rules on network (Key: $networkKey)"
                Invoke-VergeNetworkApply -Network $networkKey -Server $Server
            }
        }
    }
}
