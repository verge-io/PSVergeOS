function New-VergeUser {
    <#
    .SYNOPSIS
        Creates a new user in VergeOS.

    .DESCRIPTION
        New-VergeUser creates a new user account with the specified configuration.
        The user is created in an enabled state by default.

    .PARAMETER Name
        The username for the new user. Must be unique and 1-128 characters.
        Will be converted to lowercase automatically.

    .PARAMETER Password
        The password for the new user. Can be a SecureString or plain text string.

    .PARAMETER DisplayName
        The display name for the user (shown in the UI).

    .PARAMETER Email
        The email address for the user.

    .PARAMETER Type
        The user type. Valid values: Normal, API, VDI.
        Default is Normal.

    .PARAMETER Enabled
        Whether the user account is enabled. Default is $true.

    .PARAMETER RequirePasswordChange
        Require the user to change their password at next login.

    .PARAMETER PhysicalAccess
        Enable console/SSH access for this user. This grants administrator privileges.

    .PARAMETER TwoFactorEnabled
        Enable two-factor authentication for this user.

    .PARAMETER TwoFactorType
        The type of 2FA to use. Valid values: Email, Authenticator.
        Default is Email.

    .PARAMETER TwoFactorSetupRequired
        Require the user to set up 2FA at next login.

    .PARAMETER SSHKeys
        SSH public keys for the user (one per line or as an array).

    .PARAMETER PassThru
        Return the created user object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeUser -Name "jsmith" -Password (ConvertTo-SecureString "TempPass123!" -AsPlainText -Force) -DisplayName "John Smith" -Email "jsmith@company.com"

        Creates a new normal user account.

    .EXAMPLE
        New-VergeUser -Name "apiuser" -Password "ApiSecret123!" -Type API -PassThru

        Creates a new API user and returns the created user object.

    .EXAMPLE
        New-VergeUser -Name "vdiuser" -Password "VdiPass123!" -Type VDI -TwoFactorEnabled -TwoFactorType Authenticator

        Creates a new VDI user with authenticator-based 2FA enabled.

    .EXAMPLE
        $cred = Get-Credential -UserName "newuser"
        New-VergeUser -Name $cred.UserName -Password $cred.Password -RequirePasswordChange

        Creates a user from a credential object, requiring password change at first login.

    .OUTPUTS
        None by default. Verge.User when -PassThru is specified.

    .NOTES
        Use Get-VergeUser to retrieve users.
        Use Set-VergeUser to modify existing users.
        Use Add-VergeGroupMember to add users to groups.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [ValidateLength(1, 128)]
        [ValidatePattern('^[^/]+$', ErrorMessage = 'Username cannot contain forward slashes')]
        [string]$Name,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [object]$Password,

        [Parameter()]
        [string]$DisplayName,

        [Parameter()]
        [ValidatePattern('^[a-zA-Z0-9.!#$%&''*+/=?^_`{|}~-]+@([a-zA-Z0-9][a-zA-Z0-9_-]{0,61}[a-zA-Z0-9])+(\.[a-zA-Z0-9][a-zA-Z0-9_-]{0,61}[a-zA-Z0-9])*$', ErrorMessage = 'Invalid email address format')]
        [string]$Email,

        [Parameter()]
        [ValidateSet('Normal', 'API', 'VDI')]
        [string]$Type = 'Normal',

        [Parameter()]
        [bool]$Enabled = $true,

        [Parameter()]
        [switch]$RequirePasswordChange,

        [Parameter()]
        [switch]$PhysicalAccess,

        [Parameter()]
        [switch]$TwoFactorEnabled,

        [Parameter()]
        [ValidateSet('Email', 'Authenticator')]
        [string]$TwoFactorType = 'Email',

        [Parameter()]
        [switch]$TwoFactorSetupRequired,

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
        $typeMap = @{
            'Normal' = 'normal'
            'API'    = 'api'
            'VDI'    = 'vdi'
        }

        $twoFactorTypeMap = @{
            'Email'         = 'email'
            'Authenticator' = 'authenticator'
        }
    }

    process {
        # Convert SecureString password if needed
        $plainPassword = if ($Password -is [System.Security.SecureString]) {
            [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
            )
        }
        else {
            $Password.ToString()
        }

        # Convert username to lowercase as required by API
        $userName = $Name.ToLower()

        # Validate 2FA requirements
        if ($TwoFactorEnabled -and -not $Email) {
            throw "Email address is required when enabling two-factor authentication."
        }

        # Build request body
        $body = @{
            name     = $userName
            password = $plainPassword
            type     = $typeMap[$Type]
            enabled  = $Enabled
        }

        # Add optional parameters
        if ($DisplayName) {
            $body['displayname'] = $DisplayName
        }

        if ($Email) {
            $body['email'] = $Email.ToLower()
        }

        if ($RequirePasswordChange) {
            $body['change_password'] = $true
        }

        if ($PhysicalAccess) {
            $body['physical_access'] = $true
        }

        if ($TwoFactorEnabled) {
            if ($TwoFactorType -eq 'Authenticator') {
                # Authenticator requires TOTP setup - user must set up at next login
                $body['two_factor_setup_next_login'] = $true
                $body['two_factor_type'] = $twoFactorTypeMap[$TwoFactorType]
            }
            else {
                # Email-based 2FA can be enabled immediately
                $body['two_factor_authentication'] = $true
                $body['two_factor_type'] = $twoFactorTypeMap[$TwoFactorType]
            }
        }

        if ($TwoFactorSetupRequired) {
            $body['two_factor_setup_next_login'] = $true
        }

        if ($SSHKeys -and $SSHKeys.Count -gt 0) {
            $body['ssh_keys'] = $SSHKeys -join "`n"
        }

        # Confirm action
        $actionDescription = "Create $Type user '$userName'"
        if ($Email) {
            $actionDescription += " ($Email)"
        }

        if ($PSCmdlet.ShouldProcess($userName, 'Create User')) {
            try {
                Write-Verbose "Creating user '$userName'"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'users' -Body $body -Connection $Server

                # Get the created user key
                $userKey = $response.'$key'
                if (-not $userKey -and $response.key) {
                    $userKey = $response.key
                }

                Write-Verbose "User '$userName' created with Key: $userKey"

                if ($PassThru -and $userKey) {
                    # Return the created user
                    Start-Sleep -Milliseconds 500
                    Get-VergeUser -Key $userKey -Server $Server
                }
            }
            catch {
                $errorMessage = $_.Exception.Message
                if ($errorMessage -match 'already in use') {
                    throw "A user with the name '$userName' already exists."
                }
                throw "Failed to create user '$userName': $errorMessage"
            }
        }
    }
}
