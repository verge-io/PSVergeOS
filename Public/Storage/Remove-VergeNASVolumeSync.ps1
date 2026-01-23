function Remove-VergeNASVolumeSync {
    <#
    .SYNOPSIS
        Removes a volume sync job from VergeOS.

    .DESCRIPTION
        Remove-VergeNASVolumeSync deletes a volume synchronization job.
        This operation cannot be undone.

    .PARAMETER Sync
        A volume sync object from Get-VergeNASVolumeSync.

    .PARAMETER NASService
        The NAS service name or object containing the sync job.

    .PARAMETER Name
        The name of the sync job to remove.

    .PARAMETER Key
        The unique key (ID) of the sync job to remove.

    .PARAMETER Force
        Bypasses the confirmation prompt.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeNASVolumeSync -NASService "MyNAS" -Name "OldSync"

        Removes the sync job after confirmation.

    .EXAMPLE
        Remove-VergeNASVolumeSync -NASService "MyNAS" -Name "OldSync" -Force

        Removes the sync job without confirmation.

    .EXAMPLE
        Get-VergeNASVolumeSync -Name "Test*" | Remove-VergeNASVolumeSync -Force

        Removes all sync jobs starting with "Test".

    .NOTES
        Running syncs should be stopped before removal.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByNASAndName')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [PSTypeName('Verge.NASVolumeSync')]
        [PSCustomObject]$Sync,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByNASAndName')]
        [object]$NASService,

        [Parameter(Mandatory, Position = 1, ParameterSetName = 'ByNASAndName')]
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
            # Resolve sync job
            $targetSync = $null

            switch ($PSCmdlet.ParameterSetName) {
                'ByKey' {
                    $targetSync = Get-VergeNASVolumeSync -Key $Key -Server $Server
                    if (-not $targetSync) {
                        throw "Volume sync with key '$Key' not found"
                    }
                }
                'ByNASAndName' {
                    $targetSync = Get-VergeNASVolumeSync -NASService $NASService -Name $Name -Server $Server
                    if (-not $targetSync) {
                        throw "Volume sync '$Name' not found on NAS '$NASService'"
                    }
                }
                'ByObject' {
                    $targetSync = $Sync
                    if (-not $Server -and $Sync._Connection) {
                        $Server = $Sync._Connection
                    }
                }
            }

            if (-not $targetSync) {
                throw "Could not resolve volume sync job"
            }

            $syncKey = $targetSync.Key ?? $targetSync.Id
            $syncName = $targetSync.Name

            $shouldProcess = $Force -or $PSCmdlet.ShouldProcess(
                "Volume sync '$syncName'",
                'Remove'
            )

            if ($shouldProcess) {
                Write-Verbose "Removing volume sync '$syncName' (key: $syncKey)"
                $null = Invoke-VergeAPI -Method DELETE -Endpoint "volume_syncs/$syncKey" -Connection $Server
                Write-Verbose "Volume sync '$syncName' removed successfully"
            }
        }
        catch {
            $displayName = $syncName ?? $syncKey ?? 'unknown'
            Write-Error -Message "Failed to remove volume sync '$displayName': $($_.Exception.Message)" -ErrorId 'RemoveVolumeSyncFailed'
        }
    }
}
