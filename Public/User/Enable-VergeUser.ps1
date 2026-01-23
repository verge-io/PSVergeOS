function Enable-VergeUser {
    <#
    .SYNOPSIS
        Enables a disabled user account in VergeOS.

    .DESCRIPTION
        Enable-VergeUser enables a previously disabled user account,
        allowing the user to log in again.

    .PARAMETER Name
        The username of the user to enable.

    .PARAMETER Key
        The unique key (ID) of the user to enable.

    .PARAMETER User
        A user object from Get-VergeUser to enable.

    .PARAMETER PassThru
        Return the enabled user object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Enable-VergeUser -Name "jsmith"

        Enables the user jsmith.

    .EXAMPLE
        Get-VergeUser -Enabled $false | Enable-VergeUser

        Enables all disabled users.

    .OUTPUTS
        None by default. Verge.User when -PassThru is specified.

    .NOTES
        Use Disable-VergeUser to disable accounts.
        Use Set-VergeUser for other user modifications.
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

        if ($PSCmdlet.ShouldProcess($userName, 'Enable User')) {
            try {
                Write-Verbose "Enabling user '$userName' (Key: $userKey)"

                # Use PUT to update enabled status
                $body = @{ enabled = $true }
                Invoke-VergeAPI -Method PUT -Endpoint "users/$userKey" -Body $body -Connection $Server | Out-Null

                Write-Verbose "User '$userName' enabled successfully"

                if ($PassThru) {
                    Start-Sleep -Milliseconds 500
                    Get-VergeUser -Key $userKey -Server $Server
                }
            }
            catch {
                throw "Failed to enable user '$userName': $($_.Exception.Message)"
            }
        }
    }
}
