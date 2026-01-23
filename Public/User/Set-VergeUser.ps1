function Set-VergeUser {
    <#
    .SYNOPSIS
        Modifies an existing user in VergeOS.

    .DESCRIPTION
        Set-VergeUser updates the settings of an existing user account.
        Only the specified parameters will be modified.

    .PARAMETER Name
        The username of the user to modify.

    .PARAMETER Key
        The unique key (ID) of the user to modify.

    .PARAMETER User
        A user object from Get-VergeUser to modify.

    .PARAMETER Password
        A new password for the user. Can be a SecureString or plain text string.

    .PARAMETER DisplayName
        The display name for the user.

    .PARAMETER Email
        The email address for the user.

    .PARAMETER Enabled
        Enable or disable the user account.

    .PARAMETER RequirePasswordChange
        Require the user to change their password at next login.

    .PARAMETER PhysicalAccess
        Enable or disable console/SSH access for this user.

    .PARAMETER TwoFactorEnabled
        Enable or disable two-factor authentication for this user.

    .PARAMETER TwoFactorType
        The type of 2FA to use. Valid values: Email, Authenticator.

    .PARAMETER TwoFactorSetupRequired
        Require the user to set up 2FA at next login.

    .PARAMETER SSHKeys
        SSH public keys for the user (replaces existing keys).

    .PARAMETER PassThru
        Return the modified user object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Set-VergeUser -Name "jsmith" -Email "john.smith@company.com"

        Updates the email address for user jsmith.

    .EXAMPLE
        Set-VergeUser -Name "jsmith" -Password (ConvertTo-SecureString "NewPass123!" -AsPlainText -Force) -RequirePasswordChange

        Changes the user's password and requires them to change it at next login.

    .EXAMPLE
        Get-VergeUser -Name "jsmith" | Set-VergeUser -TwoFactorEnabled $true -TwoFactorType Authenticator -PassThru

        Enables authenticator-based 2FA for the user.

    .EXAMPLE
        Set-VergeUser -Name "jsmith" -Enabled $false

        Disables the user account.

    .OUTPUTS
        None by default. Verge.User when -PassThru is specified.

    .NOTES
        Use Get-VergeUser to retrieve users.
        Use Enable-VergeUser and Disable-VergeUser for simple enable/disable operations.
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
        [object]$Password,

        [Parameter()]
        [string]$DisplayName,

        [Parameter()]
        [ValidatePattern('^[a-zA-Z0-9.!#$%&''*+/=?^_`{|}~-]+@([a-zA-Z0-9][a-zA-Z0-9_-]{0,61}[a-zA-Z0-9])+(\.[a-zA-Z0-9][a-zA-Z0-9_-]{0,61}[a-zA-Z0-9])*$', ErrorMessage = 'Invalid email address format')]
        [string]$Email,

        [Parameter()]
        [bool]$Enabled,

        [Parameter()]
        [bool]$RequirePasswordChange,

        [Parameter()]
        [bool]$PhysicalAccess,

        [Parameter()]
        [bool]$TwoFactorEnabled,

        [Parameter()]
        [ValidateSet('Email', 'Authenticator')]
        [string]$TwoFactorType,

        [Parameter()]
        [bool]$TwoFactorSetupRequired,

        [Parameter()]
        [string[]]$SSHKeys,

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

        # Map friendly names to API values
        $twoFactorTypeMap = @{
            'Email'         = 'email'
            'Authenticator' = 'authenticator'
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

        # Build request body with only changed parameters
        $body = @{}

        if ($Password) {
            # Convert SecureString password if needed
            $plainPassword = if ($Password -is [System.Security.SecureString]) {
                [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
                )
            }
            else {
                $Password.ToString()
            }
            $body['password'] = $plainPassword
        }

        if ($PSBoundParameters.ContainsKey('DisplayName')) {
            $body['displayname'] = $DisplayName
        }

        if ($PSBoundParameters.ContainsKey('Email')) {
            $body['email'] = $Email.ToLower()
        }

        if ($PSBoundParameters.ContainsKey('Enabled')) {
            $body['enabled'] = $Enabled
        }

        if ($PSBoundParameters.ContainsKey('RequirePasswordChange')) {
            $body['change_password'] = $RequirePasswordChange
        }

        if ($PSBoundParameters.ContainsKey('PhysicalAccess')) {
            $body['physical_access'] = $PhysicalAccess
        }

        if ($PSBoundParameters.ContainsKey('TwoFactorEnabled')) {
            $body['two_factor_authentication'] = $TwoFactorEnabled
        }

        if ($PSBoundParameters.ContainsKey('TwoFactorType')) {
            $body['two_factor_type'] = $twoFactorTypeMap[$TwoFactorType]
        }

        if ($PSBoundParameters.ContainsKey('TwoFactorSetupRequired')) {
            $body['two_factor_setup_next_login'] = $TwoFactorSetupRequired
        }

        if ($PSBoundParameters.ContainsKey('SSHKeys')) {
            $body['ssh_keys'] = if ($SSHKeys -and $SSHKeys.Count -gt 0) {
                $SSHKeys -join "`n"
            } else {
                ''
            }
        }

        # Check if there's anything to update
        if ($body.Count -eq 0) {
            Write-Warning "No parameters specified to update for user '$userName'"
            return
        }

        # Build description of changes
        $changes = ($body.Keys | Where-Object { $_ -ne 'password' }) -join ', '
        if ($body.ContainsKey('password')) {
            $changes = if ($changes) { "$changes, password" } else { 'password' }
        }

        if ($PSCmdlet.ShouldProcess($userName, "Modify User ($changes)")) {
            try {
                Write-Verbose "Updating user '$userName' (Key: $userKey)"
                $response = Invoke-VergeAPI -Method PUT -Endpoint "users/$userKey" -Body $body -Connection $Server

                Write-Verbose "User '$userName' updated successfully"

                if ($PassThru) {
                    # Return the updated user
                    Start-Sleep -Milliseconds 500
                    Get-VergeUser -Key $userKey -Server $Server
                }
            }
            catch {
                throw "Failed to update user '$userName': $($_.Exception.Message)"
            }
        }
    }
}
