function Remove-VergeFile {
    <#
    .SYNOPSIS
        Removes a file from the VergeOS media catalog.

    .DESCRIPTION
        Remove-VergeFile deletes a file from the VergeOS files catalog.
        This permanently removes the file from storage.

    .PARAMETER Name
        The name of the file to remove.

    .PARAMETER Key
        The key (ID) of the file to remove.

    .PARAMETER File
        A file object from Get-VergeFile.

    .PARAMETER Force
        Bypasses the confirmation prompt.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeFile -Name "old-ubuntu.iso"

        Removes a file by name (with confirmation).

    .EXAMPLE
        Remove-VergeFile -Key 123 -Force

        Removes a file by key without confirmation.

    .EXAMPLE
        Get-VergeFile -Name "*test*" | Remove-VergeFile -Force

        Removes all files matching the pattern.

    .NOTES
        Files that are referenced by VM drives cannot be deleted until the reference is removed.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [PSTypeName('Verge.File')]
        [PSCustomObject]$File,

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
            $fileKey = $null
            $fileName = $null

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
                    if ($fileInfo) {
                        $fileName = $fileInfo.Name
                    }
                }
                'ByObject' {
                    $fileKey = $File.Key
                    $fileName = $File.Name
                }
            }

            if (-not $fileKey) {
                throw "Could not resolve file key"
            }

            $displayName = $fileName ?? "Key: $fileKey"
            $shouldProcess = $Force -or $PSCmdlet.ShouldProcess(
                "File '$displayName'",
                'Remove'
            )

            if ($shouldProcess) {
                Write-Verbose "Removing file '$displayName'"
                $null = Invoke-VergeAPI -Method DELETE -Endpoint "files/$fileKey" -Connection $Server
                Write-Verbose "File '$displayName' removed successfully"
            }
        }
        catch {
            $displayName = $fileName ?? $fileKey ?? 'unknown'
            Write-Error -Message "Failed to remove file '$displayName': $($_.Exception.Message)" -ErrorId 'RemoveVergeFileFailed'
        }
    }
}
