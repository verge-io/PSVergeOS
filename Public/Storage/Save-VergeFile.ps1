function Save-VergeFile {
    <#
    .SYNOPSIS
        Downloads a file from the VergeOS media catalog.

    .DESCRIPTION
        Save-VergeFile downloads a file from the VergeOS files catalog to a local path.
        This can be used to export ISOs, disk images, or other files.

    .PARAMETER Name
        The name of the file to download from VergeOS.

    .PARAMETER Key
        The key (ID) of the file to download.

    .PARAMETER File
        A file object from Get-VergeFile.

    .PARAMETER Destination
        The local path where the file should be saved. Can be a directory or full file path.
        Defaults to the current directory.

    .PARAMETER Force
        Overwrite the destination file if it already exists.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Save-VergeFile -Name "ubuntu-22.04.iso" -Destination "C:\Downloads"

        Downloads the ISO to C:\Downloads\ubuntu-22.04.iso

    .EXAMPLE
        Get-VergeFile -Type iso | Save-VergeFile -Destination "/backup/isos"

        Downloads all ISO files to the backup directory.

    .EXAMPLE
        Save-VergeFile -Name "server.qcow2" -Destination "./server-backup.qcow2" -Force

        Downloads a disk image, overwriting if it exists.

    .OUTPUTS
        System.IO.FileInfo object for the downloaded file.

    .NOTES
        Large files may take significant time to download depending on network speed.
        Ensure sufficient disk space at the destination.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByName')]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [PSTypeName('Verge.File')]
        [PSCustomObject]$File,

        [Parameter(Position = 1)]
        [string]$Destination = '.',

        [Parameter()]
        [switch]$Force,

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
            # Resolve file info
            $fileInfo = $null
            $fileName = $null
            $fileKey = $null

            switch ($PSCmdlet.ParameterSetName) {
                'ByName' {
                    $fileName = $Name
                    $fileInfo = Get-VergeFile -Name $Name -Server $Server
                    if (-not $fileInfo) {
                        throw "File '$Name' not found"
                    }
                    $fileKey = $fileInfo.Key
                    $fileName = $fileInfo.Name
                }
                'ByKey' {
                    $fileKey = $Key
                    $fileInfo = Get-VergeFile -Key $Key -Server $Server
                    if (-not $fileInfo) {
                        throw "File with key $Key not found"
                    }
                    $fileName = $fileInfo.Name
                }
                'ByObject' {
                    $fileKey = $File.Key
                    $fileName = $File.Name
                    $fileInfo = $File
                }
            }

            if (-not $fileKey) {
                throw "Could not resolve file key"
            }

            # Determine output path
            $outputPath = $Destination
            if (Test-Path -Path $Destination -PathType Container) {
                $outputPath = Join-Path -Path $Destination -ChildPath $fileName
            }
            elseif (-not (Test-Path -Path (Split-Path -Path $Destination -Parent))) {
                throw "Destination directory does not exist: $(Split-Path -Path $Destination -Parent)"
            }

            # Check if file exists
            if ((Test-Path -Path $outputPath) -and -not $Force) {
                throw "File already exists at '$outputPath'. Use -Force to overwrite."
            }

            # Build download URL
            # Format: /api/v4/files/{key}?download=1&asname={filename}
            $encodedFileName = [System.Uri]::EscapeDataString($fileName)
            $downloadUrl = "$($Server.ApiBaseUrl)/files/$fileKey`?download=1&asname=$encodedFileName"

            $fileSizeMB = if ($fileInfo.SizeGB) { [math]::Round($fileInfo.SizeGB * 1024, 2) } else { 'unknown' }
            Write-Verbose "Downloading '$fileName' ($fileSizeMB MB) to '$outputPath'"

            if ($PSCmdlet.ShouldProcess("File '$fileName'", "Download to '$outputPath'")) {
                # Build authorization header
                $authType = if ($Server.AuthType) { $Server.AuthType } else { 'Basic' }
                $authHeader = "$authType $($Server.Token)"

                $requestParams = @{
                    Method  = 'GET'
                    Uri     = $downloadUrl
                    Headers = @{
                        'Authorization' = $authHeader
                    }
                    OutFile = $outputPath
                }

                if ($Server.SkipCertificateCheck) {
                    $requestParams['SkipCertificateCheck'] = $true
                }

                Write-Verbose "Downloading from: $downloadUrl"

                # Perform download
                Invoke-WebRequest @requestParams -ErrorAction Stop

                Write-Verbose "Download completed successfully"

                # Return file info
                Get-Item -Path $outputPath
            }
        }
        catch {
            $displayName = $fileName ?? $Name ?? $Key ?? 'unknown'
            Write-Error -Message "Failed to download file '$displayName': $($_.Exception.Message)" -ErrorId 'SaveVergeFileFailed'
        }
    }
}
