function Get-VergeNASVolumeFile {
    <#
    .SYNOPSIS
        Lists files and directories in a NAS volume.

    .DESCRIPTION
        Get-VergeNASVolumeFile browses the contents of a NAS volume, listing
        files and directories at the specified path.

    .PARAMETER Volume
        The volume name or object to browse.

    .PARAMETER Path
        The directory path to list. Defaults to root (/).

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeNASVolumeFile -Volume "FileShare"

        Lists files at the root of the FileShare volume.

    .EXAMPLE
        Get-VergeNASVolumeFile -Volume "FileShare" -Path "/documents"

        Lists files in the documents directory.

    .EXAMPLE
        Get-VergeNASVolume -Name "FileShare" | Get-VergeNASVolumeFile -Path "/backup"

        Lists files via pipeline.

    .OUTPUTS
        Verge.NASVolumeFile objects containing:
        - Name: File or directory name
        - Type: 'File' or 'Directory'
        - Size: File size in bytes
        - Modified: Last modified time
        - Permissions: Unix permissions string
        - Owner: File owner
        - Group: File group

    .NOTES
        The volume must be enabled to browse files.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [Alias('VolumeName')]
        [object]$Volume,

        [Parameter(Position = 1)]
        [string]$Path = '/',

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
            # Resolve volume
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

            if (-not $volumeKey) {
                throw "Could not resolve volume key"
            }

            # Normalize path - API uses empty string for root, not /
            $dir = $Path
            if ($dir -eq '/') {
                $dir = ''
            }
            elseif ($dir.StartsWith('/')) {
                $dir = $dir.Substring(1)
            }

            Write-Verbose "Browsing volume '$volumeName' at path '$Path'"

            # Create browse request - params is an object, not JSON string
            # Based on actual API payload from browser devtools
            $body = @{
                volume = $volumeKey
                query  = 'get-dir'
                params = @{
                    dir     = $dir
                    limit   = 1000
                    offset  = $null
                    filter  = @{
                        extensions = ''
                    }
                    volume  = $volumeKey
                    sort    = ''
                }
            }

            $response = Invoke-VergeAPI -Method POST -Endpoint 'volume_browser' -Body $body -Connection $Server

            if (-not $response) {
                throw "No response from volume browser"
            }

            $browseKey = $response.'$key' ?? $response.id

            # Poll for results (browser operations are async)
            $maxAttempts = 30
            $attempt = 0
            $result = $null
            $completed = $false

            while ($attempt -lt $maxAttempts) {
                Start-Sleep -Milliseconds 500
                $attempt++

                # Must explicitly request the result field - it's not returned by default
                $statusResponse = Invoke-VergeAPI -Method GET -Endpoint "volume_browser/$browseKey`?fields=id,status,result" -Connection $Server

                if ($statusResponse.status -eq 'complete') {
                    $result = $statusResponse.result
                    $completed = $true
                    break
                }
                elseif ($statusResponse.status -eq 'error') {
                    throw "Browse operation failed: $($statusResponse.result)"
                }

                Write-Verbose "Waiting for browse results (attempt $attempt/$maxAttempts)..."
            }

            if (-not $completed) {
                throw "Browse operation timed out"
            }

            # Handle empty directory (result is null)
            if ($null -eq $result) {
                Write-Verbose "Directory is empty at path '$Path'"
                return
            }

            # Parse result (it's JSON string in some cases)
            if ($result -is [string]) {
                $result = $result | ConvertFrom-Json
            }

            # Process directory entries - result is usually the array directly
            # Important: Check if result is an array first before trying .entries property
            # (accessing .property on an array in PowerShell accesses each element's property)
            $entries = if ($result -is [array]) {
                $result
            } elseif ($result.entries) {
                $result.entries
            } else {
                $result
            }

            if (-not $entries -or $entries.Count -eq 0) {
                Write-Verbose "No entries found at path '$Path'"
                return
            }

            foreach ($entry in $entries) {
                # Determine type - API returns "file" or "directory"
                $fileType = if ($entry.type -eq 'directory' -or $entry.type -eq 'd' -or $entry.is_dir) {
                    'Directory'
                } else {
                    'File'
                }

                # Convert modified time if present (API uses 'date' field)
                $modified = $null
                $timestamp = $entry.date ?? $entry.mtime
                if ($timestamp) {
                    $modified = [DateTimeOffset]::FromUnixTimeSeconds($timestamp).LocalDateTime
                }

                [PSCustomObject]@{
                    PSTypeName    = 'Verge.NASVolumeFile'
                    Name          = $entry.name
                    FullPath      = if ($Path -eq '/') { "/$($entry.name)" } else { "$Path/$($entry.name)" }
                    Type          = $fileType
                    Size          = $entry.size
                    SizeDisplay   = Format-FileSize -Bytes $entry.size
                    Modified      = $modified
                    Permissions   = $entry.perms ?? $entry.mode
                    Owner         = $entry.owner ?? $entry.uid
                    Group         = $entry.group ?? $entry.gid
                    VolumeName    = $volumeName
                    VolumeKey     = $volumeKey
                    _Connection   = $Server
                }
            }
        }
        catch {
            $displayName = $volumeName ?? $volumeKey ?? 'unknown'
            Write-Error -Message "Failed to browse volume '$displayName': $($_.Exception.Message)" -ErrorId 'GetVolumeFileFailed'
        }
    }
}

function Format-FileSize {
    param([long]$Bytes)

    if ($null -eq $Bytes -or $Bytes -eq 0) {
        return '0 B'
    }

    $sizes = 'B', 'KB', 'MB', 'GB', 'TB', 'PB'
    $order = 0
    $size = [double]$Bytes

    while ($size -ge 1024 -and $order -lt $sizes.Count - 1) {
        $order++
        $size = $size / 1024
    }

    if ($order -eq 0) {
        return "$Bytes B"
    }

    return "{0:N2} {1}" -f $size, $sizes[$order]
}
