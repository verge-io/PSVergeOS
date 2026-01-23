function Disable-VergeUser {
    <#
    .SYNOPSIS
        Disables a user account in VergeOS.

    .DESCRIPTION
        Disable-VergeUser disables a user account, preventing the user
        from logging in. The account is not deleted and can be re-enabled later.

    .PARAMETER Name
        The username of the user to disable.

    .PARAMETER Key
        The unique key (ID) of the user to disable.

    .PARAMETER User
        A user object from Get-VergeUser to disable.

    .PARAMETER PassThru
        Return the disabled user object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Disable-VergeUser -Name "jsmith"

        Disables the user jsmith.

    .EXAMPLE
        Get-VergeUser -Name "temp*" | Disable-VergeUser

        Disables all users whose names start with "temp".

    .OUTPUTS
        None by default. Verge.User when -PassThru is specified.

    .NOTES
        Use Enable-VergeUser to re-enable accounts.
        Use Remove-VergeUser to permanently delete accounts.
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
        [PSTypeName('Verge.User')]
        [PSCustomObject]$User,

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
        # Resolve user key
        $userKey = $null
        $userName = $null

        switch ($PSCmdlet.ParameterSetName) {
            'ByKey' {
                $userKey = $Key
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

        if ($PSCmdlet.ShouldProcess($userName, 'Disable User')) {
            try {
                Write-Verbose "Disabling user '$userName' (Key: $userKey)"

                # Use PUT to update enabled status
                $body = @{ enabled = $false }
                Invoke-VergeAPI -Method PUT -Endpoint "users/$userKey" -Body $body -Connection $Server | Out-Null

                Write-Verbose "User '$userName' disabled successfully"

                if ($PassThru) {
                    Start-Sleep -Milliseconds 500
                    Get-VergeUser -Key $userKey -Server $Server
                }
            }
            catch {
                throw "Failed to disable user '$userName': $($_.Exception.Message)"
            }
        }
    }
}
