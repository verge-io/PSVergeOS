function New-VergeNASUser {
    <#
    .SYNOPSIS
        Creates a new local user on a NAS service in VergeOS.

    .DESCRIPTION
        New-VergeNASUser creates a new local user account on a NAS service for
        CIFS/SMB authentication. Local users are used when not using Active
        Directory integration.

    .PARAMETER NASService
        A NAS service object from Get-VergeNASService. Accepts pipeline input.

    .PARAMETER NASServiceName
        The name of the NAS service to create the user on.

    .PARAMETER NASServiceKey
        The unique key (ID) of the NAS service.

    .PARAMETER Name
        The username for the new user. Must be unique within the NAS service
        and match pattern: starts with letter, then letters/numbers/underscores/hyphens.
        Maximum 32 characters.

    .PARAMETER Password
        The password for the new user. Can be a SecureString or plain text string.

    .PARAMETER DisplayName
        The display name for the user (shown in the UI).

    .PARAMETER Description
        A description of the user account.

    .PARAMETER HomeShare
        The name of a CIFS share to use as the user's home share.

    .PARAMETER HomeDrive
        The drive letter to map the home share to (e.g., "H").
        Must be a single letter A-Z.

    .PARAMETER Enabled
        Whether the user account is enabled. Default is $true.

    .PARAMETER PassThru
        Return the created user object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeNASUser -NASServiceName "NAS01" -Name "backup" -Password (ConvertTo-SecureString "SecurePass123!" -AsPlainText -Force)

        Creates a new NAS local user named "backup" on the NAS01 service.

    .EXAMPLE
        Get-VergeNASService -Name "FileServer" | New-VergeNASUser -Name "shareuser" -Password "TempPass123!" -DisplayName "Share User" -PassThru

        Creates a user via pipeline and returns the created user object.

    .EXAMPLE
        New-VergeNASUser -NASServiceName "NAS01" -Name "admin" -Password "AdminPass!" -HomeShare "AdminDocs" -HomeDrive "H"

        Creates a user with a home share mapped to drive H.

    .EXAMPLE
        $cred = Get-Credential -UserName "newuser"
        New-VergeNASUser -NASServiceName "NAS01" -Name $cred.UserName -Password $cred.Password

        Creates a user from a credential object.

    .OUTPUTS
        None by default. Verge.NASUser when -PassThru is specified.

    .NOTES
        Use Get-VergeNASUser to retrieve users.
        Use Set-VergeNASUser to modify existing users.
        Use Enable-VergeNASUser/Disable-VergeNASUser to change account status.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByNASName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [PSTypeName('Verge.NASService')]
        [PSCustomObject]$NASService,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByNASName')]
        [string]$NASServiceName,

        [Parameter(Mandatory, ParameterSetName = 'ByNASKey')]
        [int]$NASServiceKey,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [ValidateLength(1, 32)]
        [ValidatePattern('^[a-zA-Z][a-zA-Z0-9_-]*$', ErrorMessage = 'Username must start with a letter and contain only letters, numbers, underscores, and hyphens')]
        [string]$Name,

        [Parameter(Mandatory, Position = 2)]
        [ValidateNotNullOrEmpty()]
        [object]$Password,

        [Parameter()]
        [string]$DisplayName,

        [Parameter()]
        [ValidateLength(0, 2048)]
        [string]$Description,

        [Parameter()]
        [string]$HomeShare,

        [Parameter()]
        [ValidatePattern('^[a-zA-Z]?$', ErrorMessage = 'Home drive must be a single letter A-Z')]
        [string]$HomeDrive,

        [Parameter()]
        [bool]$Enabled = $true,

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
        # Resolve NAS service based on parameter set
        $targetService = switch ($PSCmdlet.ParameterSetName) {
            'ByNASName' {
                Get-VergeNASService -Name $NASServiceName -Server $Server
            }
            'ByNASKey' {
                Get-VergeNASService -Key $NASServiceKey -Server $Server
            }
            'ByObject' {
                $NASService
            }
        }

        if (-not $targetService) {
            $identifier = if ($NASServiceName) { $NASServiceName } elseif ($NASServiceKey) { "Key $NASServiceKey" } else { 'provided object' }
            Write-Error -Message "NAS service '$identifier' not found." -ErrorId 'NASServiceNotFound'
            return
        }

        # Convert SecureString password if needed
        $plainPassword = if ($Password -is [System.Security.SecureString]) {
            [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
            )
        }
        else {
            $Password.ToString()
        }

        # Resolve home share if specified
        $homeShareKey = $null
        if ($HomeShare) {
            # Look up the CIFS share by name for this NAS service
            $shareQueryParams = @{
                filter = "volume#service eq $($targetService.Key) and name eq '$HomeShare'"
                fields = '$key,name'
            }
            Write-Verbose "Looking up home share '$HomeShare'"
            $shareResponse = Invoke-VergeAPI -Method GET -Endpoint 'volume_cifs_shares' -Query $shareQueryParams -Connection $Server

            if ($shareResponse -and $shareResponse.'$key') {
                $homeShareKey = $shareResponse.'$key'
            }
            elseif ($shareResponse -is [array] -and $shareResponse.Count -gt 0) {
                $homeShareKey = $shareResponse[0].'$key'
            }
            else {
                Write-Warning "Home share '$HomeShare' not found on NAS service '$($targetService.Name)'. Creating user without home share."
            }
        }

        # Build request body
        $body = @{
            service  = $targetService.Key
            name     = $Name
            password = $plainPassword
            enabled  = $Enabled
        }

        # Add optional parameters
        if ($DisplayName) {
            $body['displayname'] = $DisplayName
        }

        if ($Description) {
            $body['description'] = $Description
        }

        if ($homeShareKey) {
            $body['home_share'] = $homeShareKey
        }

        if ($HomeDrive) {
            $body['home_drive'] = $HomeDrive.ToUpper()
        }

        if ($PSCmdlet.ShouldProcess("$Name on $($targetService.Name)", 'Create NAS User')) {
            try {
                Write-Verbose "Creating NAS user '$Name' on service '$($targetService.Name)'"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'vm_service_users' -Body $body -Connection $Server

                # Get the created user key
                $userKey = $response.'$key'
                if (-not $userKey -and $response.id) {
                    $userKey = $response.id
                }

                Write-Verbose "NAS user '$Name' created with Key: $userKey"

                if ($PassThru -and $userKey) {
                    # Return the created user
                    Start-Sleep -Milliseconds 500
                    Get-VergeNASUser -NASServiceKey $targetService.Key -Key $userKey -Server $Server
                }
            }
            catch {
                $errorMessage = $_.Exception.Message
                if ($errorMessage -match 'already in use') {
                    throw "A user with the name '$Name' already exists on NAS service '$($targetService.Name)'."
                }
                throw "Failed to create NAS user '$Name': $errorMessage"
            }
        }
    }
}
