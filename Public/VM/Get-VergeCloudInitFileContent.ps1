function Get-VergeCloudInitFileContent {
    <#
    .SYNOPSIS
        Retrieves the contents of a cloud-init file from VergeOS.

    .DESCRIPTION
        Get-VergeCloudInitFileContent retrieves the raw contents of a cloud-init file.
        This is useful when you need to view or export the actual file content.

    .PARAMETER Key
        The unique key (ID) of the cloud-init file.

    .PARAMETER CloudInitFile
        A cloud-init file object from Get-VergeCloudInitFile. Accepts pipeline input.

    .PARAMETER AsBytes
        Return the contents as a byte array instead of a string.
        Useful for binary content or when encoding matters.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeCloudInitFileContent -Key 25

        Returns the contents of cloud-init file 25 as a string.

    .EXAMPLE
        Get-VergeCloudInitFile -VMId 30 -Name "/user-data" | Get-VergeCloudInitFileContent

        Gets the contents of the user-data file for VM 30 using pipeline input.

    .EXAMPLE
        $content = Get-VergeCloudInitFileContent -Key 25
        $content | Out-File -FilePath "./backup-user-data.yaml"

        Exports the cloud-init file content to a local file.

    .EXAMPLE
        Get-VergeCloudInitFile -VMId 30 | ForEach-Object {
            $content = $_ | Get-VergeCloudInitFileContent
            "$($_.Name): $($content.Length) bytes"
        }

        Lists all cloud-init files for a VM with their content sizes.

    .OUTPUTS
        System.String by default, or System.Byte[] when -AsBytes is specified.

    .NOTES
        Cloud-init files have a maximum size of 65536 bytes (64KB).
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByKey')]
    [OutputType([string], [byte[]])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByCloudInitFile')]
        [PSTypeName('Verge.CloudInitFile')]
        [PSCustomObject]$CloudInitFile,

        [Parameter()]
        [switch]$AsBytes,

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
            # Resolve the file key
            $fileKey = switch ($PSCmdlet.ParameterSetName) {
                'ByKey' { $Key }
                'ByCloudInitFile' { $CloudInitFile.Key }
            }

            if (-not $fileKey) {
                throw "Unable to determine cloud-init file key."
            }

            Write-Verbose "Retrieving contents for cloud-init file Key: $fileKey"

            # Build download URL
            $downloadUrl = "$($Server.ApiBaseUrl)/cloudinit_files/$fileKey`?download=1"

            # Build authorization header
            $authType = if ($Server.AuthType) { $Server.AuthType } else { 'Basic' }
            $authHeader = "$authType $($Server.Token)"

            $requestParams = @{
                Method  = 'GET'
                Uri     = $downloadUrl
                Headers = @{
                    'Authorization' = $authHeader
                }
            }

            if ($Server.SkipCertificateCheck) {
                $requestParams['SkipCertificateCheck'] = $true
            }

            Write-Verbose "Downloading from: $downloadUrl"

            # Perform download
            $response = Invoke-WebRequest @requestParams -ErrorAction Stop

            # Return content in requested format
            if ($AsBytes) {
                Write-Output $response.Content
            }
            else {
                # Convert bytes to string (UTF-8)
                if ($response.Content -is [byte[]]) {
                    $content = [System.Text.Encoding]::UTF8.GetString($response.Content)
                }
                else {
                    $content = $response.Content
                }
                Write-Output $content
            }
        }
        catch {
            $displayKey = $fileKey ?? $Key ?? 'unknown'
            Write-Error -Message "Failed to get contents for cloud-init file '$displayKey': $($_.Exception.Message)" -ErrorId 'GetCloudInitFileContentFailed'
        }
    }
}
