function New-VergeNASNFSShare {
    <#
    .SYNOPSIS
        Creates a new NFS share on a VergeOS volume.

    .DESCRIPTION
        New-VergeNASNFSShare creates an NFS file share on a NAS volume.
        The share can be accessed from Unix/Linux and other NFS clients.

    .PARAMETER Volume
        The name or object of the volume to create the share on.

    .PARAMETER Name
        The name for the new share.

    .PARAMETER SharePath
        The path within the volume to share. Leave empty to share the entire volume.

    .PARAMETER Description
        Optional description for the share.

    .PARAMETER AllowedHosts
        Comma-delimited list of allowed hosts: FQDNs (wildcards allowed),
        IP addresses, IP networks (CIDR), NIS netgroups (@group).
        Required unless -AllowAll is specified.

    .PARAMETER AllowAll
        Allow connections from any host. Use with caution.

    .PARAMETER DataAccess
        Data access mode: ReadOnly or ReadWrite. Default is ReadOnly.

    .PARAMETER Squash
        User/group ID mapping: SquashRoot (default), SquashAll, or NoSquash.

    .PARAMETER AnonymousUID
        User ID for anonymous/squashed users. Default is 65534.

    .PARAMETER AnonymousGID
        Group ID for anonymous/squashed users. Default is 65534.

    .PARAMETER Async
        Enable asynchronous mode for better performance (risk of data loss on crash).

    .PARAMETER Insecure
        Allow connections from ports above 1024.

    .PARAMETER NoACL
        Disable access control lists.

    .PARAMETER FilesystemID
        Filesystem ID for the export. Must be unique per volume.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeNASNFSShare -Volume "FileShare" -Name "exports" -AllowedHosts "192.168.1.0/24"

        Creates an NFS share accessible from the 192.168.1.0/24 subnet.

    .EXAMPLE
        New-VergeNASNFSShare -Volume "FileShare" -Name "public" -AllowAll -DataAccess ReadOnly

        Creates a read-only NFS share accessible from any host.

    .EXAMPLE
        New-VergeNASNFSShare -Volume "FileShare" -Name "secure" -AllowedHosts "10.0.0.5,10.0.0.6" -DataAccess ReadWrite -Squash NoSquash

        Creates a read-write share with no user squashing for specific hosts.

    .OUTPUTS
        Verge.NASNFSShare object representing the created share.

    .NOTES
        Mount the share from Linux: mount -t nfs server:/sharename /mnt/point
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
        [string]$AllowedHosts,

        [Parameter()]
        [switch]$AllowAll,

        [Parameter()]
        [ValidateSet('ReadOnly', 'ReadWrite')]
        [string]$DataAccess = 'ReadOnly',

        [Parameter()]
        [ValidateSet('SquashRoot', 'SquashAll', 'NoSquash')]
        [string]$Squash = 'SquashRoot',

        [Parameter()]
        [string]$AnonymousUID,

        [Parameter()]
        [string]$AnonymousGID,

        [Parameter()]
        [switch]$Async,

        [Parameter()]
        [switch]$Insecure,

        [Parameter()]
        [switch]$NoACL,

        [Parameter()]
        [string]$FilesystemID,

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
        $dataAccessMap = @{
            'ReadOnly'  = 'ro'
            'ReadWrite' = 'rw'
        }

        $squashMap = @{
            'SquashRoot' = 'root_squash'
            'SquashAll'  = 'all_squash'
            'NoSquash'   = 'no_root_squash'
        }
    }

    process {
        try {
            # Validate hosts requirement
            if (-not $AllowAll -and -not $AllowedHosts) {
                throw "Either -AllowedHosts or -AllowAll must be specified"
            }

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
                volume      = $volumeKey
                name        = $Name
                enabled     = $true
                data_access = $dataAccessMap[$DataAccess]
                squash      = $squashMap[$Squash]
            }

            if ($SharePath) {
                $body['share_path'] = $SharePath
            }

            if ($Description) {
                $body['description'] = $Description
            }

            if ($AllowAll) {
                $body['allow_all'] = $true
            }

            if ($AllowedHosts) {
                $body['allowed_hosts'] = $AllowedHosts
            }

            if ($AnonymousUID) {
                $body['anonuid'] = $AnonymousUID
            }

            if ($AnonymousGID) {
                $body['anongid'] = $AnonymousGID
            }

            if ($Async) {
                $body['async'] = $true
            }

            if ($Insecure) {
                $body['insecure'] = $true
            }

            if ($NoACL) {
                $body['no_acl'] = $true
            }

            if ($FilesystemID) {
                $body['fsid'] = $FilesystemID
            }

            $displayName = $volumeName ?? $volumeKey
            if ($PSCmdlet.ShouldProcess("Volume '$displayName'", "Create NFS share '$Name'")) {
                Write-Verbose "Creating NFS share '$Name' on volume '$displayName'"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'volume_nfs_shares' -Body $body -Connection $Server

                # Return the created share
                if ($response.'$key' -or $response.id) {
                    $shareKey = $response.'$key' ?? $response.id
                    Get-VergeNASNFSShare -Key $shareKey -Server $Server
                }
                else {
                    Get-VergeNASNFSShare -Volume $volumeKey -Name $Name -Server $Server
                }
            }
        }
        catch {
            $displayName = $volumeName ?? $volumeKey ?? 'unknown'
            Write-Error -Message "Failed to create NFS share on volume '$displayName': $($_.Exception.Message)" -ErrorId 'NewNFSShareFailed'
        }
    }
}
