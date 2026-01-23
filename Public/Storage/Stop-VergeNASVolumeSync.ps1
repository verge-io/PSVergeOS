function Stop-VergeNASVolumeSync {
    <#
    .SYNOPSIS
        Stops a running volume sync job in VergeOS.

    .DESCRIPTION
        Stop-VergeNASVolumeSync aborts a currently running volume synchronization job.
        The sync will stop at its current progress point.

    .PARAMETER Sync
        A volume sync object from Get-VergeNASVolumeSync.

    .PARAMETER NASService
        The NAS service name or object containing the sync job.

    .PARAMETER Name
        The name of the sync job to stop.

    .PARAMETER Key
        The unique key (ID) of the sync job to stop.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Stop-VergeNASVolumeSync -NASService "MyNAS" -Name "DailyBackup"

        Stops the DailyBackup sync job.

    .EXAMPLE
        Get-VergeNASVolumeSync -Name "DailyBackup" | Stop-VergeNASVolumeSync

        Stops a sync job via pipeline.

    .EXAMPLE
        Stop-VergeNASVolumeSync -Key "abc123def456"

        Stops a sync job by its key.

    .NOTES
        The sync can be restarted with Start-VergeNASVolumeSync.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByNASAndName')]
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

            if ($PSCmdlet.ShouldProcess("Volume sync '$syncName'", 'Stop')) {
                Write-Verbose "Stopping volume sync '$syncName' (key: $syncKey)"

                $body = @{
                    sync   = $syncKey
                    action = 'stop_sync'
                }

                $null = Invoke-VergeAPI -Method POST -Endpoint 'volume_sync_actions' -Body $body -Connection $Server
                Write-Verbose "Volume sync '$syncName' stopped successfully"
            }
        }
        catch {
            $displayName = $syncName ?? $syncKey ?? 'unknown'
            Write-Error -Message "Failed to stop volume sync '$displayName': $($_.Exception.Message)" -ErrorId 'StopVolumeSyncFailed'
        }
    }
}
