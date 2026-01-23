function Send-VergeFile {
    <#
    .SYNOPSIS
        Uploads a file to the VergeOS media catalog.

    .DESCRIPTION
        Send-VergeFile uploads a local file (ISO, disk image, etc.) to the VergeOS
        files catalog where it can be used as a media source for VM drives.

        The upload uses chunked transfer for large files, displaying progress
        as the upload proceeds.

    .PARAMETER Path
        The local path to the file to upload.

    .PARAMETER Name
        The name to give the file in VergeOS. Defaults to the local filename.

    .PARAMETER Description
        Optional description for the uploaded file.

    .PARAMETER Tier
        The preferred storage tier (1-5) for the uploaded file.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Send-VergeFile -Path "C:\ISOs\ubuntu-22.04.iso"

        Uploads an ISO file to VergeOS using its original filename.

    .EXAMPLE
        Send-VergeFile -Path "/home/admin/server.iso" -Name "Ubuntu-Server-22.04.iso" -Tier 2

        Uploads a file with a custom name to tier 2 storage.

    .EXAMPLE
        Get-ChildItem *.iso | Send-VergeFile -Tier 1

        Uploads multiple ISO files to tier 1.

    .OUTPUTS
        Verge.File object representing the uploaded file.

    .NOTES
        Large files may take significant time to upload depending on network speed.
        The cmdlet shows progress during upload.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName', 'FilePath')]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$Path,

        [Parameter()]
        [ValidateLength(1, 255)]
        [string]$Name,

        [Parameter()]
        [ValidateLength(0, 2048)]
        [string]$Description,

        [Parameter()]
        [ValidateRange(1, 5)]
        [int]$Tier,

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

        # Chunk size for uploads (256 KB - matches verge-cli)
        $script:ChunkSize = 262144
    }

    process {
        try {
            # Resolve full path
            $fullPath = Resolve-Path -Path $Path -ErrorAction Stop
            $fileInfo = Get-Item -Path $fullPath

            # Use provided name or default to filename
            $uploadName = if ($Name) { $Name } else { $fileInfo.Name }
            $fileSize = $fileInfo.Length

            $fileSizeMB = [math]::Round($fileSize / 1048576, 2)
            Write-Verbose "Uploading '$($fileInfo.Name)' ($fileSizeMB MB) to VergeOS as '$uploadName'"

            if ($PSCmdlet.ShouldProcess("File '$uploadName' ($fileSizeMB MB)", 'Upload to VergeOS')) {
                # Build authorization header
                $authType = if ($Server.AuthType) { $Server.AuthType } else { 'Basic' }
                $authHeader = "$authType $($Server.Token)"

                # Step 1: Create file entry with POST containing JSON metadata
                $uploadUrl = "$($Server.ApiBaseUrl)/files"

                $createBody = @{
                    allocated_bytes = $fileSize.ToString()
                    name            = $uploadName
                }

                if ($Description) {
                    $createBody['description'] = $Description
                }
                if ($Tier) {
                    $createBody['preferred_tier'] = $Tier
                }

                $createBodyJson = $createBody | ConvertTo-Json -Compress

                Write-Verbose "Creating file entry at: $uploadUrl"
                Write-Verbose "Request body: $createBodyJson"

                $createParams = @{
                    Method      = 'POST'
                    Uri         = $uploadUrl
                    Headers     = @{
                        'Authorization' = $authHeader
                        'Content-Type'  = 'application/json'
                    }
                    Body        = $createBodyJson
                    ErrorAction = 'Stop'
                }

                if ($Server.SkipCertificateCheck) {
                    $createParams['SkipCertificateCheck'] = $true
                }

                $createResponse = Invoke-RestMethod @createParams

                # Extract file ID from response
                $fileId = $null
                if ($createResponse.'$key') {
                    $fileId = $createResponse.'$key'
                }
                elseif ($createResponse.location) {
                    # Extract from location path
                    $fileId = ($createResponse.location -split '/')[-1]
                }

                if (-not $fileId) {
                    throw "Could not determine file ID from upload response"
                }

                Write-Verbose "File entry created with ID: $fileId"

                # Step 2: Upload file in chunks using PUT
                $totalChunks = [math]::Ceiling($fileSize / $script:ChunkSize)
                $uploadedChunks = 0

                $fileStream = [System.IO.File]::OpenRead($fullPath)
                try {
                    $offset = [int64]0

                    while ($offset -lt $fileSize) {
                        $bytesToRead = [math]::Min($script:ChunkSize, $fileSize - $offset)

                        # Create a fresh buffer for each chunk
                        $buffer = New-Object byte[] $bytesToRead
                        $bytesRead = $fileStream.Read($buffer, 0, $bytesToRead)

                        if ($bytesRead -eq 0) {
                            break
                        }

                        # Build chunk URL with filepos parameter
                        $chunkUrl = "$uploadUrl/$fileId`?filepos=$offset"

                        # Use WebRequest for more reliable streaming
                        $chunkParams = @{
                            Method      = 'PUT'
                            Uri         = $chunkUrl
                            Headers     = @{
                                'Authorization' = $authHeader
                                'Content-Type'  = 'application/octet-stream'
                            }
                            Body        = $buffer
                            ErrorAction = 'Stop'
                        }

                        if ($Server.SkipCertificateCheck) {
                            $chunkParams['SkipCertificateCheck'] = $true
                        }

                        $null = Invoke-WebRequest @chunkParams

                        $offset += $bytesRead
                        $uploadedChunks++

                        # Update progress
                        $percentComplete = [math]::Round(($uploadedChunks / $totalChunks) * 100)
                        $uploadedMB = [math]::Round($offset / 1048576, 2)
                        Write-Progress -Activity "Uploading $uploadName" `
                            -Status "$uploadedMB MB of $fileSizeMB MB ($percentComplete%)" `
                            -PercentComplete $percentComplete
                    }
                }
                finally {
                    $fileStream.Close()
                    $fileStream.Dispose()
                    Write-Progress -Activity "Uploading $uploadName" -Completed
                }

                Write-Verbose "Upload completed successfully"

                # Return the file info
                Get-VergeFile -Key $fileId -Server $Server
            }
        }
        catch {
            $fileName = if ($uploadName) { $uploadName } else { $Path }
            Write-Error -Message "Failed to upload file '$fileName': $($_.Exception.Message)" -ErrorId 'SendVergeFileFailed'
        }
    }
}
