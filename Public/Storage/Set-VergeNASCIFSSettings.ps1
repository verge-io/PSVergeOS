function Set-VergeNASCIFSSettings {
    <#
    .SYNOPSIS
        Modifies CIFS/SMB settings for a NAS service in VergeOS.

    .DESCRIPTION
        Set-VergeNASCIFSSettings modifies the CIFS/SMB configuration for a NAS service,
        including workgroup, minimum protocol version, guest user mapping, and
        extended ACL support.

    .PARAMETER NASService
        A NAS service object from Get-VergeNASService. Accepts pipeline input.

    .PARAMETER Name
        The name of the NAS service to modify CIFS settings for.

    .PARAMETER Key
        The unique key (ID) of the NAS service.

    .PARAMETER Workgroup
        The NetBIOS workgroup name for the CIFS server.

    .PARAMETER MinProtocol
        The minimum SMB protocol version clients must use.
        Valid values: None, SMB2, SMB2_02, SMB2_10, SMB3, SMB3_00, SMB3_02, SMB3_11

    .PARAMETER GuestMapping
        How to handle invalid user/password combinations.
        Valid values: Never, BadUser, BadPassword, BadUID

    .PARAMETER ExtendedACLSupport
        Enable or disable extended ACL support.

    .PARAMETER PassThru
        Return the updated CIFS settings object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Set-VergeNASCIFSSettings -Name "NAS01" -MinProtocol SMB3

        Sets the minimum protocol to SMB3 for the NAS service.

    .EXAMPLE
        Set-VergeNASCIFSSettings -Name "NAS01" -Workgroup "MYWORKGROUP" -PassThru

        Sets the workgroup and returns the updated settings.

    .EXAMPLE
        Get-VergeNASService -Name "FileServer" | Set-VergeNASCIFSSettings -ExtendedACLSupport $true

        Enables extended ACL support via pipeline.

    .EXAMPLE
        Set-VergeNASCIFSSettings -Name "NAS01" -GuestMapping Never

        Configures the service to reject invalid passwords (no guest access).

    .OUTPUTS
        None by default. Verge.NASCIFSSettings when -PassThru is specified.

    .NOTES
        Changes to CIFS settings may require the NAS service to be restarted.
        Use Get-VergeNASCIFSSettings to view current settings.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [PSTypeName('Verge.NASService')]
        [PSCustomObject]$NASService,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter()]
        [ValidateLength(0, 63)]
        [string]$Workgroup,

        [Parameter()]
        [ValidateSet('None', 'SMB2', 'SMB2_02', 'SMB2_10', 'SMB3', 'SMB3_00', 'SMB3_02', 'SMB3_11')]
        [string]$MinProtocol,

        [Parameter()]
        [ValidateSet('Never', 'BadUser', 'BadPassword', 'BadUID')]
        [string]$GuestMapping,

        [Parameter()]
        [bool]$ExtendedACLSupport,

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
        $targetServices = switch ($PSCmdlet.ParameterSetName) {
            'ByName' {
                Get-VergeNASService -Name $Name -Server $Server
            }
            'ByKey' {
                Get-VergeNASService -Key $Key -Server $Server
            }
            'ByObject' {
                $NASService
            }
        }

        foreach ($service in $targetServices) {
            if (-not $service) {
                if ($PSCmdlet.ParameterSetName -eq 'ByName') {
                    Write-Error -Message "NAS service '$Name' not found." -ErrorId 'NASServiceNotFound'
                }
                continue
            }

            # Get current CIFS settings
            $currentSettings = Get-VergeNASCIFSSettings -Key $service.Key -Server $Server
            if (-not $currentSettings) {
                Write-Error -Message "CIFS settings not found for NAS service '$($service.Name)'." -ErrorId 'CIFSSettingsNotFound'
                continue
            }

            # Build the update body with only changed values
            $body = @{}
            $changes = @()

            if ($PSBoundParameters.ContainsKey('Workgroup')) {
                $body['workgroup'] = $Workgroup.ToLower()
                $changes += "Workgroup=$Workgroup"
            }

            if ($PSBoundParameters.ContainsKey('MinProtocol')) {
                $protocolMap = @{
                    'None'    = 'none'
                    'SMB2'    = 'SMB2'
                    'SMB2_02' = 'SMB2_02'
                    'SMB2_10' = 'SMB2_10'
                    'SMB3'    = 'SMB3'
                    'SMB3_00' = 'SMB3_00'
                    'SMB3_02' = 'SMB3_02'
                    'SMB3_11' = 'SMB3_11'
                }
                $body['server_min_protocol'] = $protocolMap[$MinProtocol]
                $changes += "MinProtocol=$MinProtocol"
            }

            if ($PSBoundParameters.ContainsKey('GuestMapping')) {
                $guestMap = @{
                    'Never'       = 'never'
                    'BadUser'     = 'bad user'
                    'BadPassword' = 'bad password'
                    'BadUID'      = 'bad uid'
                }
                $body['map_to_guest'] = $guestMap[$GuestMapping]
                $changes += "GuestMapping=$GuestMapping"
            }

            if ($PSBoundParameters.ContainsKey('ExtendedACLSupport')) {
                $body['extended_acl_support'] = $ExtendedACLSupport
                $changes += "ExtendedACLSupport=$ExtendedACLSupport"
            }

            if ($body.Count -eq 0) {
                Write-Warning "No changes specified for NAS service '$($service.Name)'."
                continue
            }

            $changeDescription = $changes -join ', '

            # Confirm action
            if ($PSCmdlet.ShouldProcess($service.Name, "Update CIFS settings ($changeDescription)")) {
                try {
                    Write-Verbose "Updating CIFS settings for NAS service '$($service.Name)': $changeDescription"
                    $response = Invoke-VergeAPI -Method PUT -Endpoint "vm_service_cifs/$($currentSettings.Key)" -Body $body -Connection $Server

                    Write-Verbose "CIFS settings updated successfully"

                    if ($PassThru) {
                        Get-VergeNASCIFSSettings -Key $service.Key -Server $Server
                    }
                }
                catch {
                    Write-Error -Message "Failed to update CIFS settings for NAS service '$($service.Name)': $($_.Exception.Message)" -ErrorId 'SetCIFSSettingsFailed'
                }
            }
        }
    }
}
