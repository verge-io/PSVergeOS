function Set-VergeNASNFSSettings {
    <#
    .SYNOPSIS
        Modifies NFS settings for a NAS service in VergeOS.

    .DESCRIPTION
        Set-VergeNASNFSSettings modifies the NFS configuration for a NAS service,
        including NFSv4 status, allowed hosts, squashing options, and access settings.

    .PARAMETER NASService
        A NAS service object from Get-VergeNASService. Accepts pipeline input.

    .PARAMETER Name
        The name of the NAS service to modify NFS settings for.

    .PARAMETER Key
        The unique key (ID) of the NAS service.

    .PARAMETER EnableNFSv4
        Enable or disable NFSv4 protocol support.

    .PARAMETER AllowedHosts
        Comma-separated list of allowed hosts or networks (e.g., "192.168.1.0/24,10.0.0.5").

    .PARAMETER AllowAll
        Allow all hosts to access NFS exports.

    .PARAMETER Squash
        User/group squashing mode.
        Valid values: RootSquash, AllSquash, NoSquash

    .PARAMETER DataAccess
        Read-only or read-write access.
        Valid values: ReadOnly, ReadWrite

    .PARAMETER AnonUID
        Anonymous user ID for squashed users.

    .PARAMETER AnonGID
        Anonymous group ID for squashed users.

    .PARAMETER NoACL
        Disable ACL support for NFS exports.

    .PARAMETER Insecure
        Allow connections from non-privileged ports (above 1024).

    .PARAMETER Async
        Enable async mode for better performance (less safe).

    .PARAMETER PassThru
        Return the updated NFS settings object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Set-VergeNASNFSSettings -Name "NAS01" -EnableNFSv4 $true

        Enables NFSv4 for the NAS service.

    .EXAMPLE
        Set-VergeNASNFSSettings -Name "NAS01" -Squash NoSquash -DataAccess ReadWrite -PassThru

        Sets no squashing and read-write access, returning the updated settings.

    .EXAMPLE
        Get-VergeNASService -Name "FileServer" | Set-VergeNASNFSSettings -AllowAll $true

        Allows all hosts to access NFS exports via pipeline.

    .EXAMPLE
        Set-VergeNASNFSSettings -Name "NAS01" -AllowedHosts "192.168.1.0/24,10.0.0.0/8"

        Restricts NFS access to specific networks.

    .OUTPUTS
        None by default. Verge.NASNFSSettings when -PassThru is specified.

    .NOTES
        Changes to NFS settings may require the NAS service to be restarted.
        Use Get-VergeNASNFSSettings to view current settings.
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
        [bool]$EnableNFSv4,

        [Parameter()]
        [string]$AllowedHosts,

        [Parameter()]
        [bool]$AllowAll,

        [Parameter()]
        [ValidateSet('RootSquash', 'AllSquash', 'NoSquash')]
        [string]$Squash,

        [Parameter()]
        [ValidateSet('ReadOnly', 'ReadWrite')]
        [string]$DataAccess,

        [Parameter()]
        [int]$AnonUID,

        [Parameter()]
        [int]$AnonGID,

        [Parameter()]
        [bool]$NoACL,

        [Parameter()]
        [bool]$Insecure,

        [Parameter()]
        [bool]$Async,

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

            # Get current NFS settings
            $currentSettings = Get-VergeNASNFSSettings -Key $service.Key -Server $Server
            if (-not $currentSettings) {
                Write-Error -Message "NFS settings not found for NAS service '$($service.Name)'." -ErrorId 'NFSSettingsNotFound'
                continue
            }

            # Build the update body with only changed values
            $body = @{}
            $changes = @()

            if ($PSBoundParameters.ContainsKey('EnableNFSv4')) {
                $body['enable_nfsv4'] = $EnableNFSv4
                $changes += "EnableNFSv4=$EnableNFSv4"
            }

            if ($PSBoundParameters.ContainsKey('AllowedHosts')) {
                $body['allowed_hosts'] = $AllowedHosts
                $changes += "AllowedHosts=$AllowedHosts"
            }

            if ($PSBoundParameters.ContainsKey('AllowAll')) {
                $body['allow_all'] = $AllowAll
                $changes += "AllowAll=$AllowAll"
            }

            if ($PSBoundParameters.ContainsKey('Squash')) {
                $squashMap = @{
                    'RootSquash' = 'root_squash'
                    'AllSquash'  = 'all_squash'
                    'NoSquash'   = 'no_root_squash'
                }
                $body['squash'] = $squashMap[$Squash]
                $changes += "Squash=$Squash"
            }

            if ($PSBoundParameters.ContainsKey('DataAccess')) {
                $accessMap = @{
                    'ReadOnly'  = 'ro'
                    'ReadWrite' = 'rw'
                }
                $body['data_access'] = $accessMap[$DataAccess]
                $changes += "DataAccess=$DataAccess"
            }

            if ($PSBoundParameters.ContainsKey('AnonUID')) {
                $body['anonuid'] = $AnonUID
                $changes += "AnonUID=$AnonUID"
            }

            if ($PSBoundParameters.ContainsKey('AnonGID')) {
                $body['anongid'] = $AnonGID
                $changes += "AnonGID=$AnonGID"
            }

            if ($PSBoundParameters.ContainsKey('NoACL')) {
                $body['no_acl'] = $NoACL
                $changes += "NoACL=$NoACL"
            }

            if ($PSBoundParameters.ContainsKey('Insecure')) {
                $body['insecure'] = $Insecure
                $changes += "Insecure=$Insecure"
            }

            if ($PSBoundParameters.ContainsKey('Async')) {
                $body['async'] = $Async
                $changes += "Async=$Async"
            }

            if ($body.Count -eq 0) {
                Write-Warning "No changes specified for NAS service '$($service.Name)'."
                continue
            }

            $changeDescription = $changes -join ', '

            # Confirm action
            if ($PSCmdlet.ShouldProcess($service.Name, "Update NFS settings ($changeDescription)")) {
                try {
                    Write-Verbose "Updating NFS settings for NAS service '$($service.Name)': $changeDescription"
                    $response = Invoke-VergeAPI -Method PUT -Endpoint "vm_service_nfs/$($currentSettings.Key)" -Body $body -Connection $Server

                    Write-Verbose "NFS settings updated successfully"

                    if ($PassThru) {
                        Get-VergeNASNFSSettings -Key $service.Key -Server $Server
                    }
                }
                catch {
                    Write-Error -Message "Failed to update NFS settings for NAS service '$($service.Name)': $($_.Exception.Message)" -ErrorId 'SetNFSSettingsFailed'
                }
            }
        }
    }
}
