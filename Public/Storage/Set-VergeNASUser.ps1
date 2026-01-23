function Set-VergeNASUser {
    <#
    .SYNOPSIS
        Modifies an existing local user on a NAS service in VergeOS.

    .DESCRIPTION
        Set-VergeNASUser updates the settings of an existing NAS local user account.
        Only the specified parameters will be modified. The username cannot be changed
        after creation.

    .PARAMETER NASUser
        A NAS user object from Get-VergeNASUser to modify.

    .PARAMETER NASServiceName
        The name of the NAS service containing the user.

    .PARAMETER NASServiceKey
        The unique key (ID) of the NAS service containing the user.

    .PARAMETER Name
        The username of the NAS user to modify.

    .PARAMETER Key
        The unique key (ID) of the NAS user to modify.

    .PARAMETER Password
        A new password for the user. Can be a SecureString or plain text string.

    .PARAMETER DisplayName
        The display name for the user.

    .PARAMETER Description
        A description of the user account.

    .PARAMETER HomeShare
        The name of a CIFS share to use as the user's home share.
        Use empty string to remove the home share.

    .PARAMETER HomeDrive
        The drive letter to map the home share to (e.g., "H").
        Must be a single letter A-Z. Use empty string to remove.

    .PARAMETER Enabled
        Enable or disable the user account.

    .PARAMETER PassThru
        Return the modified user object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Set-VergeNASUser -NASServiceName "NAS01" -Name "backup" -Password (ConvertTo-SecureString "NewPass123!" -AsPlainText -Force)

        Changes the password for the backup user.

    .EXAMPLE
        Get-VergeNASUser -NASServiceName "NAS01" -Name "shareuser" | Set-VergeNASUser -DisplayName "Share Service User" -PassThru

        Updates the display name via pipeline and returns the modified user.

    .EXAMPLE
        Set-VergeNASUser -NASServiceName "NAS01" -Name "admin" -HomeShare "AdminDocs" -HomeDrive "Z"

        Sets the home share and drive letter for the admin user.

    .EXAMPLE
        Set-VergeNASUser -NASServiceName "NAS01" -Name "olduser" -Enabled $false

        Disables the user account.

    .OUTPUTS
        None by default. Verge.NASUser when -PassThru is specified.

    .NOTES
        Use Get-VergeNASUser to retrieve users.
        Use Enable-VergeNASUser and Disable-VergeNASUser for simple enable/disable operations.
        The username cannot be changed after creation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByNASNameAndUserName')]
    [OutputType([PSCustomObject])]
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
        [object]$Password,

        [Parameter()]
        [string]$DisplayName,

        [Parameter()]
        [ValidateLength(0, 2048)]
        [string]$Description,

        [Parameter()]
        [AllowEmptyString()]
        [string]$HomeShare,

        [Parameter()]
        [ValidatePattern('^[a-zA-Z]?$', ErrorMessage = 'Home drive must be a single letter A-Z or empty')]
        [AllowEmptyString()]
        [string]$HomeDrive,

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
        # Resolve the NAS user
        $targetUser = $null
        $targetService = $null

        switch -Wildcard ($PSCmdlet.ParameterSetName) {
            'ByObject' {
                $targetUser = $NASUser
                if (-not $Server -and $NASUser._Connection) {
                    $Server = $NASUser._Connection
                }
                # Get the service for home share resolution
                $targetService = Get-VergeNASService -Key $NASUser.NASServiceKey -Server $Server
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
                $targetService = Get-VergeNASService -Key $NASServiceKey -Server $Server
                if (-not $targetService) {
                    Write-Error -Message "NAS service with key '$NASServiceKey' not found." -ErrorId 'NASServiceNotFound'
                    return
                }
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

        if ($PSBoundParameters.ContainsKey('Description')) {
            $body['description'] = $Description
        }

        if ($PSBoundParameters.ContainsKey('HomeShare')) {
            if ([string]::IsNullOrEmpty($HomeShare)) {
                # Clear the home share
                $body['home_share'] = $null
            }
            else {
                # Look up the CIFS share by name
                $shareQueryParams = @{
                    filter = "volume#service eq $($targetService.Key) and name eq '$HomeShare'"
                    fields = '$key,name'
                }
                Write-Verbose "Looking up home share '$HomeShare'"
                $shareResponse = Invoke-VergeAPI -Method GET -Endpoint 'volume_cifs_shares' -Query $shareQueryParams -Connection $Server

                $homeShareKey = $null
                if ($shareResponse -and $shareResponse.'$key') {
                    $homeShareKey = $shareResponse.'$key'
                }
                elseif ($shareResponse -is [array] -and $shareResponse.Count -gt 0) {
                    $homeShareKey = $shareResponse[0].'$key'
                }

                if (-not $homeShareKey) {
                    Write-Error -Message "Home share '$HomeShare' not found on NAS service '$($targetService.Name)'." -ErrorId 'HomeShareNotFound'
                    return
                }
                $body['home_share'] = $homeShareKey
            }
        }

        if ($PSBoundParameters.ContainsKey('HomeDrive')) {
            $body['home_drive'] = if ($HomeDrive) { $HomeDrive.ToUpper() } else { '' }
        }

        if ($PSBoundParameters.ContainsKey('Enabled')) {
            $body['enabled'] = $Enabled
        }

        # Check if there's anything to update
        if ($body.Count -eq 0) {
            Write-Warning "No parameters specified to update for NAS user '$($targetUser.Name)'"
            return
        }

        # Build description of changes
        $changes = ($body.Keys | Where-Object { $_ -ne 'password' }) -join ', '
        if ($body.ContainsKey('password')) {
            $changes = if ($changes) { "$changes, password" } else { 'password' }
        }

        if ($PSCmdlet.ShouldProcess("$($targetUser.Name) on $($targetUser.NASServiceName)", "Modify NAS User ($changes)")) {
            try {
                Write-Verbose "Updating NAS user '$($targetUser.Name)' (Key: $($targetUser.Key))"
                Invoke-VergeAPI -Method PUT -Endpoint "vm_service_users/$($targetUser.Key)" -Body $body -Connection $Server | Out-Null

                Write-Verbose "NAS user '$($targetUser.Name)' updated successfully"

                if ($PassThru) {
                    # Return the updated user
                    Start-Sleep -Milliseconds 500
                    Get-VergeNASUser -NASServiceKey $targetUser.NASServiceKey -Key $targetUser.Key -Server $Server
                }
            }
            catch {
                throw "Failed to update NAS user '$($targetUser.Name)': $($_.Exception.Message)"
            }
        }
    }
}
