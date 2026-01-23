function New-VergeNASCIFSShare {
    <#
    .SYNOPSIS
        Creates a new CIFS/SMB share on a VergeOS volume.

    .DESCRIPTION
        New-VergeNASCIFSShare creates a CIFS (SMB) file share on a NAS volume.
        The share can be accessed from Windows and other SMB clients.

    .PARAMETER Volume
        The name or object of the volume to create the share on.

    .PARAMETER Name
        The name for the new share.

    .PARAMETER SharePath
        The path within the volume to share. Leave empty to share the entire volume.

    .PARAMETER Description
        Optional description for the share.

    .PARAMETER Comment
        Short comment about the share (visible to clients).

    .PARAMETER ReadOnly
        If specified, creates a read-only share.

    .PARAMETER GuestOK
        If specified, allows guest access to the share.

    .PARAMETER Browseable
        If specified, makes the share visible in network browsing. Defaults to true.

    .PARAMETER ValidUsers
        Array of usernames allowed to connect to this share.

    .PARAMETER ValidGroups
        Array of group names allowed to connect to this share.

    .PARAMETER ShadowCopy
        If specified, enables shadow copy (Previous Versions) support.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeNASCIFSShare -Volume "FileShare" -Name "shared"

        Creates a CIFS share named "shared" sharing the entire FileShare volume.

    .EXAMPLE
        New-VergeNASCIFSShare -Volume "FileShare" -Name "public" -SharePath "/public" -GuestOK

        Creates a guest-accessible share for a specific path.

    .EXAMPLE
        New-VergeNASCIFSShare -Volume "FileShare" -Name "secure" -ValidUsers @("admin", "manager")

        Creates a share accessible only to specific users.

    .OUTPUTS
        Verge.CIFSShare object representing the created share.

    .NOTES
        Access the share from Windows using \\server\sharename.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [Alias('VolumeName')]
        [object]$Volume,

        [Parameter(Mandatory, Position = 1)]
        [ValidateLength(1, 128)]
        [string]$Name,

        [Parameter()]
        [string]$SharePath,

        [Parameter()]
        [ValidateLength(0, 2048)]
        [string]$Description,

        [Parameter()]
        [ValidateLength(0, 64)]
        [string]$Comment,

        [Parameter()]
        [switch]$ReadOnly,

        [Parameter()]
        [switch]$GuestOK,

        [Parameter()]
        [bool]$Browseable = $true,

        [Parameter()]
        [string[]]$ValidUsers,

        [Parameter()]
        [string[]]$ValidGroups,

        [Parameter()]
        [switch]$ShadowCopy,

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
        try {
            # Resolve volume to key
            $volumeKey = $null
            $volumeName = $null

            if ($Volume -is [string]) {
                $volumeName = $Volume
                $volumeData = Get-VergeNASVolume -Name $Volume -Server $Server
                if (-not $volumeData) {
                    throw "Volume '$Volume' not found"
                }
                $volumeKey = $volumeData.Key
                $volumeName = $volumeData.Name
            }
            elseif ($Volume.Key) {
                $volumeKey = $Volume.Key
                $volumeName = $Volume.Name
            }
            elseif ($Volume -is [int]) {
                $volumeKey = $Volume
            }

            if (-not $volumeKey) {
                throw "Could not resolve volume key"
            }

            # Build request body
            $body = @{
                volume     = $volumeKey
                name       = $Name
                enabled    = $true
                browseable = $Browseable
            }

            if ($SharePath) {
                $body['share_path'] = $SharePath
            }

            if ($Description) {
                $body['description'] = $Description
            }

            if ($Comment) {
                $body['comment'] = $Comment
            }

            if ($ReadOnly) {
                $body['read_only'] = $true
            }

            if ($GuestOK) {
                $body['guest_ok'] = $true
            }

            if ($ValidUsers -and $ValidUsers.Count -gt 0) {
                $body['valid_users'] = $ValidUsers -join "`n"
            }

            if ($ValidGroups -and $ValidGroups.Count -gt 0) {
                $body['valid_groups'] = $ValidGroups -join "`n"
            }

            if ($ShadowCopy) {
                $body['vfs_shadow_copy2'] = $true
            }

            $displayName = $volumeName ?? $volumeKey
            if ($PSCmdlet.ShouldProcess("Volume '$displayName'", "Create CIFS share '$Name'")) {
                Write-Verbose "Creating CIFS share '$Name' on volume '$displayName'"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'volume_cifs_shares' -Body $body -Connection $Server

                # Return the created share
                if ($response.'$key' -or $response.id) {
                    $shareKey = $response.'$key' ?? $response.id
                    Get-VergeNASCIFSShare -Key $shareKey -Server $Server
                }
                else {
                    Get-VergeNASCIFSShare -Volume $volumeKey -Name $Name -Server $Server
                }
            }
        }
        catch {
            $displayName = $volumeName ?? $volumeKey ?? 'unknown'
            Write-Error -Message "Failed to create CIFS share on volume '$displayName': $($_.Exception.Message)" -ErrorId 'NewCIFSShareFailed'
        }
    }
}
