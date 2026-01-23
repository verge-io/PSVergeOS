function Remove-VergeNASNFSShare {
    <#
    .SYNOPSIS
        Removes an NFS share from VergeOS.

    .DESCRIPTION
        Remove-VergeNASNFSShare deletes an NFS share from a volume.
        This operation cannot be undone.

    .PARAMETER Share
        An NFS share object from Get-VergeNASNFSShare.

    .PARAMETER Volume
        The name or object of the volume containing the share.

    .PARAMETER Name
        The name of the share to remove.

    .PARAMETER Key
        The unique key (ID) of the share to remove.

    .PARAMETER Force
        Bypasses the confirmation prompt.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeNASNFSShare -Volume "FileShare" -Name "exports"

        Removes the NFS share after confirmation.

    .EXAMPLE
        Remove-VergeNASNFSShare -Volume "FileShare" -Name "oldexport" -Force

        Removes the share without confirmation.

    .EXAMPLE
        Get-VergeNASNFSShare -Volume "FileShare" | Remove-VergeNASNFSShare -Force

        Removes all NFS shares from the volume.

    .NOTES
        Clients actively connected to the share may experience errors.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByVolumeAndName')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [PSTypeName('Verge.NASNFSShare')]
        [PSCustomObject]$Share,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByVolumeAndName')]
        [object]$Volume,

        [Parameter(Mandatory, Position = 1, ParameterSetName = 'ByVolumeAndName')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [string]$Key,

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
            # Resolve share
            $targetShare = $null

            switch ($PSCmdlet.ParameterSetName) {
                'ByKey' {
                    $targetShare = Get-VergeNASNFSShare -Key $Key -Server $Server
                    if (-not $targetShare) {
                        throw "NFS share with key '$Key' not found"
                    }
                }
                'ByVolumeAndName' {
                    $targetShare = Get-VergeNASNFSShare -Volume $Volume -Name $Name -Server $Server
                    if (-not $targetShare) {
                        throw "NFS share '$Name' not found on volume '$Volume'"
                    }
                }
                'ByObject' {
                    $targetShare = $Share
                    if (-not $Server -and $Share._Connection) {
                        $Server = $Share._Connection
                    }
                }
            }

            if (-not $targetShare) {
                throw "Could not resolve NFS share"
            }

            $shareKey = $targetShare.Key ?? $targetShare.Id
            $shareName = $targetShare.Name

            $shouldProcess = $Force -or $PSCmdlet.ShouldProcess(
                "NFS share '$shareName'",
                'Remove'
            )

            if ($shouldProcess) {
                Write-Verbose "Removing NFS share '$shareName' (key: $shareKey)"
                $null = Invoke-VergeAPI -Method DELETE -Endpoint "volume_nfs_shares/$shareKey" -Connection $Server
                Write-Verbose "NFS share '$shareName' removed successfully"
            }
        }
        catch {
            $displayName = $shareName ?? $shareKey ?? 'unknown'
            Write-Error -Message "Failed to remove NFS share '$displayName': $($_.Exception.Message)" -ErrorId 'RemoveNFSShareFailed'
        }
    }
}
