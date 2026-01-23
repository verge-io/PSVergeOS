function Start-VergeSiteSync {
    <#
    .SYNOPSIS
        Starts (enables) an outgoing site sync in VergeOS.

    .DESCRIPTION
        Start-VergeSiteSync enables an outgoing site sync, allowing it to actively
        replicate cloud snapshots to the remote site.

    .PARAMETER Key
        The key (ID) of the sync to start.

    .PARAMETER Name
        The name of the sync to start.

    .PARAMETER SiteSync
        A site sync object from Get-VergeSiteSync. Accepts pipeline input.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Start-VergeSiteSync -Name "DR-Sync"

        Starts the sync named "DR-Sync".

    .EXAMPLE
        Get-VergeSiteSync -SiteName "DR-Site" | Start-VergeSiteSync

        Starts all syncs for the specified site.

    .EXAMPLE
        Start-VergeSiteSync -Key 1

        Starts the sync with key 1.

    .NOTES
        Use Stop-VergeSiteSync to disable a sync.
        Use Get-VergeSiteSync to see the current status of syncs.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [PSTypeName('Verge.SiteSync')]
        [PSCustomObject]$SiteSync,

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
        # Resolve the sync
        $targetSync = switch ($PSCmdlet.ParameterSetName) {
            'ByObject' { $SiteSync }
            'ByKey' { Get-VergeSiteSync -Key $Key -Server $Server }
            'ByName' { Get-VergeSiteSync -Name $Name -Server $Server }
        }

        if (-not $targetSync) {
            $identifier = if ($Key) { "Key: $Key" } elseif ($Name) { "Name: $Name" } else { "Unknown" }
            Write-Error -Message "Site sync not found ($identifier)" -ErrorId 'SiteSyncNotFound'
            return
        }

        $syncKey = $targetSync.Key
        $syncName = $targetSync.Name

        if ($PSCmdlet.ShouldProcess("Site Sync '$syncName' (Key: $syncKey)", 'Start')) {
            try {
                Write-Verbose "Starting site sync '$syncName' (Key: $syncKey)"

                $body = @{
                    site_syncs_outgoing = $syncKey
                    action = 'enable'
                }

                $response = Invoke-VergeAPI -Method POST -Endpoint 'site_syncs_outgoing_actions' -Body $body -Connection $Server

                Write-Verbose "Site sync '$syncName' started successfully"

                # Return updated sync
                Get-VergeSiteSync -Key $syncKey -Server $Server
            }
            catch {
                Write-Error -Message "Failed to start site sync '$syncName': $($_.Exception.Message)" -ErrorId 'StartSiteSyncFailed'
            }
        }
    }
}
