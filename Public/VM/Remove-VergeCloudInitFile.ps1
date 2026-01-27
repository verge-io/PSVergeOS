function Remove-VergeCloudInitFile {
    <#
    .SYNOPSIS
        Deletes a cloud-init file from VergeOS.

    .DESCRIPTION
        Remove-VergeCloudInitFile deletes one or more cloud-init files from VergeOS.
        The cmdlet supports pipeline input from Get-VergeCloudInitFile for bulk operations.

    .PARAMETER Key
        The unique key (ID) of the cloud-init file to delete.

    .PARAMETER CloudInitFile
        A cloud-init file object from Get-VergeCloudInitFile. Accepts pipeline input.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeCloudInitFile -Key 27

        Deletes the cloud-init file with Key 27 after confirmation.

    .EXAMPLE
        Remove-VergeCloudInitFile -Key 27 -Confirm:$false

        Deletes the cloud-init file without confirmation prompt.

    .EXAMPLE
        Get-VergeCloudInitFile -Key 27 | Remove-VergeCloudInitFile

        Deletes a cloud-init file using pipeline input.

    .EXAMPLE
        Get-VergeCloudInitFile -VMId 30 | Remove-VergeCloudInitFile

        Deletes all cloud-init files belonging to VM 30.

    .EXAMPLE
        Get-VergeCloudInitFile -Name "*pstest*" | Remove-VergeCloudInitFile -Confirm:$false

        Deletes all cloud-init files with "pstest" in the name without confirmation.

    .OUTPUTS
        None

    .NOTES
        Use caution when deleting cloud-init files that are in use by VMs.
        Deleting these files may affect VM provisioning.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByKey')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByCloudInitFile')]
        [PSTypeName('Verge.CloudInitFile')]
        [PSCustomObject]$CloudInitFile,

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
        # Get files to delete based on parameter set
        $filesToDelete = switch ($PSCmdlet.ParameterSetName) {
            'ByKey' {
                Get-VergeCloudInitFile -Key $Key -Server $Server
            }
            'ByCloudInitFile' {
                $CloudInitFile
            }
        }

        foreach ($file in $filesToDelete) {
            if (-not $file) {
                continue
            }

            # Build display string for confirmation
            $fileDisplay = "$($file.Name) (Key: $($file.Key), Owner: $($file.Owner))"

            # Confirm deletion
            if ($PSCmdlet.ShouldProcess($fileDisplay, 'Remove CloudInit File')) {
                try {
                    Write-Verbose "Deleting cloud-init file '$($file.Name)' (Key: $($file.Key))"
                    $null = Invoke-VergeAPI -Method DELETE -Endpoint "cloudinit_files/$($file.Key)" -Connection $Server

                    Write-Verbose "Cloud-init file '$($file.Name)' deleted successfully"
                }
                catch {
                    $errorMessage = $_.Exception.Message
                    if ($errorMessage -match 'in use' -or $errorMessage -match 'protected') {
                        Write-Error -Message "Cannot delete cloud-init file '$($file.Name)': File is in use or protected." -ErrorId 'CloudInitFileInUse'
                    }
                    else {
                        Write-Error -Message "Failed to delete cloud-init file '$($file.Name)': $errorMessage" -ErrorId 'CloudInitFileDeleteFailed'
                    }
                }
            }
        }
    }
}
