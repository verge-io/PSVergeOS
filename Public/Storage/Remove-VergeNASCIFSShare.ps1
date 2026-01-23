function Remove-VergeNASCIFSShare {
    <#
    .SYNOPSIS
        Removes a CIFS/SMB share from VergeOS.

    .DESCRIPTION
        Remove-VergeNASCIFSShare deletes a CIFS (SMB) file share from a volume.
        This does not delete the underlying data on the volume.

    .PARAMETER Key
        The unique key of the share to remove.

    .PARAMETER Share
        A share object from Get-VergeNASCIFSShare.

    .PARAMETER Volume
        The volume name or object, combined with -Name to identify the share.

    .PARAMETER Name
        The name of the share to remove (requires -Volume).

    .PARAMETER Force
        Bypasses the confirmation prompt.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeNASCIFSShare -Volume "FileShare" -Name "old-share"

        Removes a CIFS share by volume and name.

    .EXAMPLE
        Get-VergeNASCIFSShare -Volume "FileShare" | Remove-VergeNASCIFSShare -Force

        Removes all CIFS shares from a volume.

    .NOTES
        Connected clients will be disconnected when the share is removed.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByVolumeAndName')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [string]$Key,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [PSTypeName('Verge.NASCIFSShare')]
        [PSCustomObject]$Share,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByVolumeAndName')]
        [object]$Volume,

        [Parameter(Mandatory, Position = 1, ParameterSetName = 'ByVolumeAndName')]
        [string]$Name,

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
            $shareKey = $null
            $shareName = $null

            switch ($PSCmdlet.ParameterSetName) {
                'ByKey' {
                    $shareKey = $Key
                }
                'ByObject' {
                    $shareKey = $Share.Key ?? $Share.Id
                    $shareName = $Share.Name
                }
                'ByVolumeAndName' {
                    $shareData = Get-VergeNASCIFSShare -Volume $Volume -Name $Name -Server $Server
                    if (-not $shareData) {
                        throw "CIFS share '$Name' not found on volume '$Volume'"
                    }
                    $shareKey = $shareData.Key ?? $shareData.Id
                    $shareName = $shareData.Name
                }
            }

            if (-not $shareKey) {
                throw "Could not resolve share key"
            }

            $displayName = $shareName ?? "Key: $shareKey"
            $shouldProcess = $Force -or $PSCmdlet.ShouldProcess(
                "CIFS share '$displayName'",
                'Remove'
            )

            if ($shouldProcess) {
                Write-Verbose "Removing CIFS share '$displayName'"
                $null = Invoke-VergeAPI -Method DELETE -Endpoint "volume_cifs_shares/$shareKey" -Connection $Server
                Write-Verbose "CIFS share '$displayName' removed successfully"
            }
        }
        catch {
            $displayName = $shareName ?? $shareKey ?? 'unknown'
            Write-Error -Message "Failed to remove CIFS share '$displayName': $($_.Exception.Message)" -ErrorId 'RemoveCIFSShareFailed'
        }
    }
}
