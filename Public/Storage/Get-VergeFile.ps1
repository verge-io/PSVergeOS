function Get-VergeFile {
    <#
    .SYNOPSIS
        Lists files in the VergeOS media catalog.

    .DESCRIPTION
        Get-VergeFile retrieves files from the VergeOS media catalog. These files
        can be used as media sources for VM drives (ISO images, disk images) or
        for importing VMs (OVA/OVF/VMDK files).

    .PARAMETER Name
        Filter files by name. Supports wildcards.

    .PARAMETER Type
        Filter files by type. Common types include:
        - iso: ISO images (for CD-ROM drives)
        - ova: OVA packages (for VM import)
        - ovf: OVF files (for VM import)
        - vmdk: VMware disk images
        - qcow2: QEMU disk images
        - vhdx: Hyper-V disk images
        - raw: Raw disk images

    .PARAMETER Key
        Get a specific file by its key (ID).

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeFile

        Lists all files in the media catalog.

    .EXAMPLE
        Get-VergeFile -Type iso

        Lists all ISO files available for mounting.

    .EXAMPLE
        Get-VergeFile -Name "*.iso"

        Lists files with names ending in .iso.

    .EXAMPLE
        Get-VergeFile -Type ova, ovf, vmdk

        Lists all files that can be used for VM import.

    .EXAMPLE
        Get-VergeFile -Name "Ubuntu*" -Type iso

        Lists Ubuntu ISO files.

    .OUTPUTS
        Verge.File objects containing:
        - Key: The file key
        - Name: The filename
        - Type: The file type (iso, ova, vmdk, etc.)
        - SizeGB: The allocated size in GB
        - UsedGB: The actual used size in GB
        - Tier: The storage tier
        - Modified: Last modified date

    .NOTES
        Files in the media catalog can be used as media sources for VM drives
        or as sources for VM import operations.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByFilter')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ParameterSetName = 'ByFilter')]
        [SupportsWildcards()]
        [string]$Name,

        [Parameter(ParameterSetName = 'ByFilter')]
        [ValidateSet('iso', 'img', 'qcow', 'qcow2', 'qed', 'raw', 'vdi', 'vhd', 'vhdx', 'vmdk', 'ova', 'ovf', 'vmx', 'ybvm', 'nvram', 'zip')]
        [string[]]$Type,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

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
            $endpoint = 'files'

            if ($PSCmdlet.ParameterSetName -eq 'ByKey') {
                $endpoint = "files/$Key"
            }

            Write-Verbose "Querying files: $endpoint"
            $response = Invoke-VergeAPI -Method GET -Endpoint $endpoint -Connection $Server

            # Handle single vs array response
            $files = if ($response -is [array]) { $response } else { @($response) }

            foreach ($file in $files) {
                if (-not $file -or -not $file.name) {
                    continue
                }

                # Apply name filter with wildcard support (client-side)
                if ($Name -and $file.name -notlike $Name) {
                    continue
                }

                # Apply type filter (client-side)
                if ($Type -and $Type.Count -gt 0 -and $file.type -notin $Type) {
                    continue
                }

                # Convert bytes to GB
                $allocatedGB = if ($file.allocated_bytes) { [math]::Round($file.allocated_bytes / 1073741824, 3) } else { 0 }
                $usedGB = if ($file.used_bytes) { [math]::Round($file.used_bytes / 1073741824, 3) } else { 0 }
                $fileSizeGB = if ($file.filesize) { [math]::Round($file.filesize / 1073741824, 3) } else { 0 }

                # Convert modified timestamp
                $modified = $null
                if ($file.modified) {
                    $modified = [DateTimeOffset]::FromUnixTimeSeconds($file.modified).LocalDateTime
                }

                [PSCustomObject]@{
                    PSTypeName      = 'Verge.File'
                    Key             = $file.'$key' ?? $file.key
                    Name            = $file.name
                    Type            = $file.type
                    Description     = $file.description
                    SizeGB          = $fileSizeGB
                    AllocatedGB     = $allocatedGB
                    UsedGB          = $usedGB
                    SizeBytes       = $file.filesize
                    AllocatedBytes  = $file.allocated_bytes
                    UsedBytes       = $file.used_bytes
                    Tier            = $file.preferred_tier
                    Modified        = $modified
                    Creator         = $file.creator
                }
            }
        }
        catch {
            Write-Error -Message "Failed to get files: $($_.Exception.Message)" -ErrorId 'GetFilesFailed'
        }
    }
}
