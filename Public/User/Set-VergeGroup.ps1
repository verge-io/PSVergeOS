function Set-VergeGroup {
    <#
    .SYNOPSIS
        Modifies an existing group in VergeOS.

    .DESCRIPTION
        Set-VergeGroup updates the settings of an existing group.
        Only the specified parameters will be modified.

    .PARAMETER Name
        The name of the group to modify.

    .PARAMETER Key
        The unique key (ID) of the group to modify.

    .PARAMETER Group
        A group object from Get-VergeGroup to modify.

    .PARAMETER NewName
        A new name for the group.

    .PARAMETER Description
        A new description for the group.

    .PARAMETER Email
        A new email address for the group.

    .PARAMETER Enabled
        Enable or disable the group.

    .PARAMETER PassThru
        Return the modified group object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Set-VergeGroup -Name "Developers" -Description "Development team"

        Updates the description of the Developers group.

    .EXAMPLE
        Get-VergeGroup -Name "OldName" | Set-VergeGroup -NewName "NewName" -PassThru

        Renames a group via pipeline.

    .OUTPUTS
        None by default. Verge.Group when -PassThru is specified.

    .NOTES
        Use Get-VergeGroup to retrieve groups.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByName')]
    [OutputType([PSCustomObject])]
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
        [ValidateLength(1, 128)]
        [string]$NewName,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [ValidatePattern('^[a-zA-Z0-9.!#$%&''*+/=?^_`{|}~-]+@([a-zA-Z0-9][a-zA-Z0-9_-]{0,61}[a-zA-Z0-9])+(\.[a-zA-Z0-9][a-zA-Z0-9_-]{0,61}[a-zA-Z0-9])*$', ErrorMessage = 'Invalid email address format')]
        [string]$Email,

        [Parameter()]
        [bool]$Enabled,

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

        # Build request body with only changed parameters
        $body = @{}

        if ($PSBoundParameters.ContainsKey('NewName')) {
            $body['name'] = $NewName
        }

        if ($PSBoundParameters.ContainsKey('Description')) {
            $body['description'] = $Description
        }

        if ($PSBoundParameters.ContainsKey('Email')) {
            $body['email'] = $Email.ToLower()
        }

        if ($PSBoundParameters.ContainsKey('Enabled')) {
            $body['enabled'] = $Enabled
        }

        # Check if there's anything to update
        if ($body.Count -eq 0) {
            Write-Warning "No parameters specified to update for group '$groupName'"
            return
        }

        $changes = $body.Keys -join ', '

        if ($PSCmdlet.ShouldProcess($groupName, "Modify Group ($changes)")) {
            try {
                Write-Verbose "Updating group '$groupName' (Key: $groupKey)"
                Invoke-VergeAPI -Method PUT -Endpoint "groups/$groupKey" -Body $body -Connection $Server | Out-Null

                Write-Verbose "Group '$groupName' updated successfully"

                if ($PassThru) {
                    Start-Sleep -Milliseconds 500
                    Get-VergeGroup -Key $groupKey -Server $Server
                }
            }
            catch {
                throw "Failed to update group '$groupName': $($_.Exception.Message)"
            }
        }
    }
}
