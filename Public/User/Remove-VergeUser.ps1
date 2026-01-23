function Remove-VergeUser {
    <#
    .SYNOPSIS
        Removes a user from VergeOS.

    .DESCRIPTION
        Remove-VergeUser deletes a user account from the VergeOS system.
        This action is permanent and cannot be undone.

    .PARAMETER Name
        The username of the user to remove.

    .PARAMETER Key
        The unique key (ID) of the user to remove.

    .PARAMETER User
        A user object from Get-VergeUser to remove.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeUser -Name "jsmith"

        Removes the user jsmith after confirmation.

    .EXAMPLE
        Remove-VergeUser -Name "testuser" -Confirm:$false

        Removes the user testuser without confirmation.

    .EXAMPLE
        Get-VergeUser -Name "temp*" | Remove-VergeUser

        Removes all users whose names start with "temp".

    .OUTPUTS
        None

    .NOTES
        Use Get-VergeUser to find users to remove.
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
        [PSTypeName('Verge.User')]
        [PSCustomObject]$User,

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
        # Resolve user key
        $userKey = $null
        $userName = $null

        switch ($PSCmdlet.ParameterSetName) {
            'ByKey' {
                $userKey = $Key
                # Get the user name for display
                $existingUser = Get-VergeUser -Key $Key -Server $Server -ErrorAction SilentlyContinue
                $userName = if ($existingUser) { $existingUser.Name } else { "Key $Key" }
            }
            'ByName' {
                $existingUser = Get-VergeUser -Name $Name -Server $Server -ErrorAction SilentlyContinue
                if (-not $existingUser) {
                    Write-Error -Message "User not found: $Name" -ErrorId 'UserNotFound' -Category ObjectNotFound
                    return
                }
                $userKey = $existingUser.Key
                $userName = $Name
            }
            'ByObject' {
                $userKey = $User.Key
                $userName = $User.Name
                if (-not $Server -and $User._Connection) {
                    $Server = $User._Connection
                }
            }
        }

        if (-not $userKey) {
            Write-Error -Message "Could not resolve user key" -ErrorId 'UserNotFound' -Category ObjectNotFound
            return
        }

        if ($PSCmdlet.ShouldProcess($userName, 'Remove User')) {
            try {
                Write-Verbose "Removing user '$userName' (Key: $userKey)"
                Invoke-VergeAPI -Method DELETE -Endpoint "users/$userKey" -Connection $Server | Out-Null

                Write-Verbose "User '$userName' removed successfully"
            }
            catch {
                throw "Failed to remove user '$userName': $($_.Exception.Message)"
            }
        }
    }
}
