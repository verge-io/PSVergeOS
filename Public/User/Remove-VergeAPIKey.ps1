function Remove-VergeAPIKey {
    <#
    .SYNOPSIS
        Removes an API key from VergeOS.

    .DESCRIPTION
        Remove-VergeAPIKey deletes an API key from the system.
        This action is permanent and the key will no longer be usable.

    .PARAMETER Key
        The unique key (ID) of the API key to remove.

    .PARAMETER APIKey
        An API key object from Get-VergeAPIKey to remove.

    .PARAMETER Name
        The name of the API key to remove (requires -User parameter).

    .PARAMETER User
        The username or user object when removing by name.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeAPIKey -Key 5

        Removes the API key with ID 5.

    .EXAMPLE
        Get-VergeAPIKey -User "apiuser" | Remove-VergeAPIKey

        Removes all API keys for the apiuser.

    .EXAMPLE
        Remove-VergeAPIKey -User "admin" -Name "old-key" -Confirm:$false

        Removes a specific API key by name without confirmation.

    .OUTPUTS
        None

    .NOTES
        This operation cannot be undone.
        Any applications using this API key will lose access.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByKey')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [Alias('Id', '$key')]
        [int]$Key,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [PSTypeName('Verge.APIKey')]
        [PSCustomObject]$APIKey,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [object]$User,

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
        # Resolve API key
        $apiKeyId = $null
        $keyName = $null

        switch ($PSCmdlet.ParameterSetName) {
            'ByKey' {
                $apiKeyId = $Key
                $existingKey = Get-VergeAPIKey -Key $Key -Server $Server -ErrorAction SilentlyContinue
                $keyName = if ($existingKey) { $existingKey.Name } else { "Key $Key" }
            }
            'ByObject' {
                $apiKeyId = $APIKey.Key
                $keyName = $APIKey.Name
                if (-not $Server -and $APIKey._Connection) {
                    $Server = $APIKey._Connection
                }
            }
            'ByName' {
                # Resolve user first
                $resolvedUserKey = $null
                if ($User -is [PSCustomObject] -and $User.PSObject.TypeNames -contains 'Verge.User') {
                    $resolvedUserKey = $User.Key
                }
                elseif ($User -is [int]) {
                    $resolvedUserKey = $User
                }
                elseif ($User -is [string]) {
                    $existingUser = Get-VergeUser -Name $User -Server $Server -ErrorAction SilentlyContinue
                    if ($existingUser) {
                        $resolvedUserKey = $existingUser.Key
                    }
                    else {
                        Write-Error -Message "User not found: $User" -ErrorId 'UserNotFound' -Category ObjectNotFound
                        return
                    }
                }

                # Find API key by name
                $existingKey = Get-VergeAPIKey -UserKey $resolvedUserKey -Name $Name -Server $Server -ErrorAction SilentlyContinue
                if ($existingKey) {
                    $apiKeyId = $existingKey.Key
                    $keyName = $existingKey.Name
                }
                else {
                    Write-Error -Message "API key not found: $Name" -ErrorId 'APIKeyNotFound' -Category ObjectNotFound
                    return
                }
            }
        }

        if (-not $apiKeyId) {
            Write-Error -Message "Could not resolve API key" -ErrorId 'APIKeyNotFound' -Category ObjectNotFound
            return
        }

        if ($PSCmdlet.ShouldProcess($keyName, 'Remove API Key')) {
            try {
                Write-Verbose "Removing API key '$keyName' (Key: $apiKeyId)"
                Invoke-VergeAPI -Method DELETE -Endpoint "user_api_keys/$apiKeyId" -Connection $Server | Out-Null

                Write-Verbose "API key '$keyName' removed successfully"
            }
            catch {
                throw "Failed to remove API key '$keyName': $($_.Exception.Message)"
            }
        }
    }
}
