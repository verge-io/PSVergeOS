function Remove-VergeNASUser {
    <#
    .SYNOPSIS
        Removes a local user from a NAS service in VergeOS.

    .DESCRIPTION
        Remove-VergeNASUser deletes a local user account from a NAS service.
        This action is permanent and cannot be undone.

    .PARAMETER NASUser
        A NAS user object from Get-VergeNASUser to remove.

    .PARAMETER NASServiceName
        The name of the NAS service containing the user.

    .PARAMETER NASServiceKey
        The unique key (ID) of the NAS service containing the user.

    .PARAMETER Name
        The username of the NAS user to remove.

    .PARAMETER Key
        The unique key (ID) of the NAS user to remove.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeNASUser -NASServiceName "NAS01" -Name "olduser"

        Removes the user "olduser" from NAS01 after confirmation.

    .EXAMPLE
        Remove-VergeNASUser -NASServiceName "NAS01" -Name "tempuser" -Confirm:$false

        Removes the user without confirmation.

    .EXAMPLE
        Get-VergeNASUser -NASServiceName "NAS01" -Name "temp*" | Remove-VergeNASUser

        Removes all users whose names start with "temp" from NAS01.

    .EXAMPLE
        Get-VergeNASService | Get-VergeNASUser -Enabled $false | Remove-VergeNASUser

        Removes all disabled NAS users across all NAS services.

    .OUTPUTS
        None

    .NOTES
        Use Get-VergeNASUser to find users to remove.
        This operation cannot be undone.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByNASNameAndUserName')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [PSTypeName('Verge.NASUser')]
        [PSCustomObject]$NASUser,

        [Parameter(Mandatory, ParameterSetName = 'ByNASNameAndUserName')]
        [Parameter(Mandatory, ParameterSetName = 'ByNASNameAndUserKey')]
        [string]$NASServiceName,

        [Parameter(Mandatory, ParameterSetName = 'ByNASKeyAndUserName')]
        [Parameter(Mandatory, ParameterSetName = 'ByNASKeyAndUserKey')]
        [int]$NASServiceKey,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByNASNameAndUserName')]
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByNASKeyAndUserName')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByNASNameAndUserKey')]
        [Parameter(Mandatory, ParameterSetName = 'ByNASKeyAndUserKey')]
        [Alias('Id', 'UserKey')]
        [string]$Key,

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
        # Resolve the NAS user
        $targetUser = $null

        switch -Wildcard ($PSCmdlet.ParameterSetName) {
            'ByObject' {
                $targetUser = $NASUser
                if (-not $Server -and $NASUser._Connection) {
                    $Server = $NASUser._Connection
                }
            }
            'ByNASName*' {
                $targetService = Get-VergeNASService -Name $NASServiceName -Server $Server
                if (-not $targetService) {
                    Write-Error -Message "NAS service '$NASServiceName' not found." -ErrorId 'NASServiceNotFound'
                    return
                }
                if ($PSCmdlet.ParameterSetName -eq 'ByNASNameAndUserName') {
                    $targetUser = Get-VergeNASUser -NASServiceKey $targetService.Key -Name $Name -Server $Server
                }
                else {
                    $targetUser = Get-VergeNASUser -NASServiceKey $targetService.Key -Key $Key -Server $Server
                }
            }
            'ByNASKey*' {
                if ($PSCmdlet.ParameterSetName -eq 'ByNASKeyAndUserName') {
                    $targetUser = Get-VergeNASUser -NASServiceKey $NASServiceKey -Name $Name -Server $Server
                }
                else {
                    $targetUser = Get-VergeNASUser -NASServiceKey $NASServiceKey -Key $Key -Server $Server
                }
            }
        }

        if (-not $targetUser) {
            $identifier = if ($Name) { $Name } elseif ($Key) { "Key $Key" } else { 'provided object' }
            Write-Error -Message "NAS user '$identifier' not found." -ErrorId 'NASUserNotFound' -Category ObjectNotFound
            return
        }

        $displayName = "$($targetUser.Name) on $($targetUser.NASServiceName)"

        if ($PSCmdlet.ShouldProcess($displayName, 'Remove NAS User')) {
            try {
                Write-Verbose "Removing NAS user '$($targetUser.Name)' (Key: $($targetUser.Key))"
                Invoke-VergeAPI -Method DELETE -Endpoint "vm_service_users/$($targetUser.Key)" -Connection $Server | Out-Null

                Write-Verbose "NAS user '$($targetUser.Name)' removed successfully"
            }
            catch {
                throw "Failed to remove NAS user '$($targetUser.Name)': $($_.Exception.Message)"
            }
        }
    }
}
