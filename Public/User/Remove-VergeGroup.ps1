function Remove-VergeGroup {
    <#
    .SYNOPSIS
        Removes a group from VergeOS.

    .DESCRIPTION
        Remove-VergeGroup deletes a group from the VergeOS system.
        This action is permanent and cannot be undone.

    .PARAMETER Name
        The name of the group to remove.

    .PARAMETER Key
        The unique key (ID) of the group to remove.

    .PARAMETER Group
        A group object from Get-VergeGroup to remove.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeGroup -Name "OldGroup"

        Removes the group named OldGroup after confirmation.

    .EXAMPLE
        Remove-VergeGroup -Name "TestGroup" -Confirm:$false

        Removes the group without confirmation.

    .EXAMPLE
        Get-VergeGroup -Name "Temp*" | Remove-VergeGroup

        Removes all groups whose names start with "Temp".

    .OUTPUTS
        None

    .NOTES
        System groups cannot be removed.
        This operation cannot be undone.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [PSTypeName('Verge.Group')]
        [PSCustomObject]$Group,

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
        # Resolve group key
        $groupKey = $null
        $groupName = $null

        switch ($PSCmdlet.ParameterSetName) {
            'ByKey' {
                $groupKey = $Key
                $existingGroup = Get-VergeGroup -Key $Key -Server $Server -ErrorAction SilentlyContinue
                $groupName = if ($existingGroup) { $existingGroup.Name } else { "Key $Key" }
            }
            'ByName' {
                $existingGroup = Get-VergeGroup -Name $Name -Server $Server -ErrorAction SilentlyContinue
                if (-not $existingGroup) {
                    Write-Error -Message "Group not found: $Name" -ErrorId 'GroupNotFound' -Category ObjectNotFound
                    return
                }
                $groupKey = $existingGroup.Key
                $groupName = $Name
            }
            'ByObject' {
                $groupKey = $Group.Key
                $groupName = $Group.Name
                if (-not $Server -and $Group._Connection) {
                    $Server = $Group._Connection
                }
            }
        }

        if (-not $groupKey) {
            Write-Error -Message "Could not resolve group key" -ErrorId 'GroupNotFound' -Category ObjectNotFound
            return
        }

        if ($PSCmdlet.ShouldProcess($groupName, 'Remove Group')) {
            try {
                Write-Verbose "Removing group '$groupName' (Key: $groupKey)"
                Invoke-VergeAPI -Method DELETE -Endpoint "groups/$groupKey" -Connection $Server | Out-Null

                Write-Verbose "Group '$groupName' removed successfully"
            }
            catch {
                throw "Failed to remove group '$groupName': $($_.Exception.Message)"
            }
        }
    }
}
