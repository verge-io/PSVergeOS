function Enable-VergeNASUser {
    <#
    .SYNOPSIS
        Enables a disabled local user on a NAS service in VergeOS.

    .DESCRIPTION
        Enable-VergeNASUser enables a previously disabled local user account,
        allowing the user to authenticate to CIFS/SMB shares again.

    .PARAMETER NASUser
        A NAS user object from Get-VergeNASUser to enable.

    .PARAMETER NASServiceName
        The name of the NAS service containing the user.

    .PARAMETER NASServiceKey
        The unique key (ID) of the NAS service containing the user.

    .PARAMETER Name
        The username of the NAS user to enable.

    .PARAMETER Key
        The unique key (ID) of the NAS user to enable.

    .PARAMETER PassThru
        Return the enabled user object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Enable-VergeNASUser -NASServiceName "NAS01" -Name "backup"

        Enables the backup user on NAS01.

    .EXAMPLE
        Get-VergeNASUser -NASServiceName "NAS01" -Enabled $false | Enable-VergeNASUser

        Enables all disabled users on NAS01.

    .EXAMPLE
        Enable-VergeNASUser -NASServiceName "NAS01" -Name "shareuser" -PassThru

        Enables the user and returns the updated user object.

    .OUTPUTS
        None by default. Verge.NASUser when -PassThru is specified.

    .NOTES
        Use Disable-VergeNASUser to disable accounts.
        Use Set-VergeNASUser for other user modifications.
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

        if ($PSCmdlet.ShouldProcess($displayName, 'Enable NAS User')) {
            try {
                Write-Verbose "Enabling NAS user '$($targetUser.Name)' (Key: $($targetUser.Key))"

                $body = @{ enabled = $true }
                Invoke-VergeAPI -Method PUT -Endpoint "vm_service_users/$($targetUser.Key)" -Body $body -Connection $Server | Out-Null

                Write-Verbose "NAS user '$($targetUser.Name)' enabled successfully"

                if ($PassThru) {
                    Start-Sleep -Milliseconds 500
                    Get-VergeNASUser -NASServiceKey $targetUser.NASServiceKey -Key $targetUser.Key -Server $Server
                }
            }
            catch {
                throw "Failed to enable NAS user '$($targetUser.Name)': $($_.Exception.Message)"
            }
        }
    }
}
