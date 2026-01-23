function Set-VergeTenant {
    <#
    .SYNOPSIS
        Modifies settings for an existing VergeOS tenant.

    .DESCRIPTION
        Set-VergeTenant updates the configuration of an existing tenant.
        Only the parameters specified will be modified.

    .PARAMETER Name
        The name of the tenant to modify.

    .PARAMETER Key
        The unique key (ID) of the tenant to modify.

    .PARAMETER Tenant
        A tenant object from Get-VergeTenant. Accepts pipeline input.

    .PARAMETER NewName
        A new name for the tenant.

    .PARAMETER Description
        The description for the tenant.

    .PARAMETER URL
        The URL associated with the tenant.

    .PARAMETER Note
        A note for the tenant.

    .PARAMETER ExposeCloudSnapshots
        Whether the tenant can request snapshots from system snapshots.

    .PARAMETER AllowBranding
        Whether the tenant can customize colors and their logo.

    .PARAMETER PassThru
        Return the modified tenant object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Set-VergeTenant -Name "Customer01" -Description "Updated description"

        Updates the description for the tenant.

    .EXAMPLE
        Set-VergeTenant -Name "Customer01" -NewName "CustomerOne"

        Renames the tenant.

    .EXAMPLE
        Get-VergeTenant -Name "Customer01" | Set-VergeTenant -AllowBranding $true

        Enables branding for the tenant using pipeline input.

    .EXAMPLE
        Set-VergeTenant -Name "Customer01" -Note "Production environment" -PassThru

        Updates the note and returns the modified tenant object.

    .OUTPUTS
        None by default. Verge.Tenant when -PassThru is specified.

    .NOTES
        The tenant must be stopped to change certain settings.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByTenant')]
        [PSTypeName('Verge.Tenant')]
        [PSCustomObject]$Tenant,

        [Parameter()]
        [ValidateLength(1, 120)]
        [string]$NewName,

        [Parameter()]
        [AllowEmptyString()]
        [ValidateLength(0, 2048)]
        [string]$Description,

        [Parameter()]
        [AllowEmptyString()]
        [string]$URL,

        [Parameter()]
        [AllowEmptyString()]
        [ValidateLength(0, 1024)]
        [string]$Note,

        [Parameter()]
        [bool]$ExposeCloudSnapshots,

        [Parameter()]
        [bool]$AllowBranding,

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
        # Resolve tenant based on parameter set
        $targetTenant = switch ($PSCmdlet.ParameterSetName) {
            'ByName' {
                Get-VergeTenant -Name $Name -Server $Server
            }
            'ByKey' {
                Get-VergeTenant -Key $Key -Server $Server
            }
            'ByTenant' {
                $Tenant
            }
        }

        foreach ($t in $targetTenant) {
            if (-not $t) {
                continue
            }

            # Check if tenant is a snapshot
            if ($t.IsSnapshot) {
                Write-Error -Message "Cannot modify tenant '$($t.Name)': Tenant is a snapshot" -ErrorId 'CannotModifySnapshot'
                continue
            }

            # Build request body with only specified parameters
            $body = @{}

            if ($PSBoundParameters.ContainsKey('NewName')) {
                $body['name'] = $NewName
            }

            if ($PSBoundParameters.ContainsKey('Description')) {
                $body['description'] = $Description
            }

            if ($PSBoundParameters.ContainsKey('URL')) {
                $body['url'] = $URL
            }

            if ($PSBoundParameters.ContainsKey('Note')) {
                $body['note'] = $Note
            }

            if ($PSBoundParameters.ContainsKey('ExposeCloudSnapshots')) {
                $body['expose_cloud_snapshots'] = $ExposeCloudSnapshots
            }

            if ($PSBoundParameters.ContainsKey('AllowBranding')) {
                $body['allow_branding'] = $AllowBranding
            }

            # Check if there's anything to update
            if ($body.Count -eq 0) {
                Write-Warning "No changes specified for tenant '$($t.Name)'"
                if ($PassThru) {
                    Write-Output $t
                }
                continue
            }

            # Confirm action
            $changes = ($body.Keys | ForEach-Object { "$_=$($body[$_])" }) -join ', '
            if ($PSCmdlet.ShouldProcess("$($t.Name)", "Modify Tenant: $changes")) {
                try {
                    Write-Verbose "Modifying tenant '$($t.Name)' (Key: $($t.Key))"
                    $response = Invoke-VergeAPI -Method PUT -Endpoint "tenants/$($t.Key)" -Body $body -Connection $Server

                    Write-Verbose "Tenant '$($t.Name)' modified successfully"

                    if ($PassThru) {
                        # Return the updated tenant
                        Start-Sleep -Milliseconds 500
                        Get-VergeTenant -Key $t.Key -Server $Server
                    }
                }
                catch {
                    $errorMessage = $_.Exception.Message
                    if ($errorMessage -match 'already in use') {
                        throw "A tenant with the name '$NewName' already exists."
                    }
                    Write-Error -Message "Failed to modify tenant '$($t.Name)': $errorMessage" -ErrorId 'TenantModifyFailed'
                }
            }
        }
    }
}
