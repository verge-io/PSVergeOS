function Get-VergeNetworkStatistics {
    <#
    .SYNOPSIS
        Retrieves traffic statistics for a VergeOS virtual network.

    .DESCRIPTION
        Get-VergeNetworkStatistics returns current traffic statistics including
        transmit/receive rates, packet counts, and total bytes transferred.

    .PARAMETER Network
        The name or key of the network to get statistics for.

    .PARAMETER NetworkObject
        A network object from Get-VergeNetwork. Accepts pipeline input.

    .PARAMETER IncludeHistory
        Include historical statistics (short-term monitoring data).

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeNetworkStatistics -Network "External"

        Gets current traffic statistics for the External network.

    .EXAMPLE
        Get-VergeNetwork -PowerState Running | Get-VergeNetworkStatistics

        Gets statistics for all running networks.

    .OUTPUTS
        Verge.NetworkStatistics

    .NOTES
        Statistics are only available for running networks.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByNetworkName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByNetworkName')]
        [string]$Network,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByNetworkObject')]
        [PSTypeName('Verge.Network')]
        [PSCustomObject]$NetworkObject,

        [Parameter()]
        [switch]$IncludeHistory,

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
        # Resolve network
        $targetNetwork = $null
        if ($PSCmdlet.ParameterSetName -eq 'ByNetworkObject') {
            $targetNetwork = $NetworkObject
        }
        else {
            if ($Network -match '^\d+$') {
                $targetNetwork = Get-VergeNetwork -Key ([int]$Network) -Server $Server
            }
            else {
                $targetNetwork = Get-VergeNetwork -Name $Network -Server $Server
            }
        }

        if (-not $targetNetwork) {
            Write-Error -Message "Network '$Network' not found" -ErrorId 'NetworkNotFound'
            return
        }

        Write-Verbose "Querying statistics for network '$($targetNetwork.Name)'"

        # Query network with NIC stats fields
        $query = @{
            filter = "`$key eq $($targetNetwork.Key)"
            fields = @(
                '$key',
                'name',
                'nic#stats#txbps as tx_bps',
                'nic#stats#rxbps as rx_bps',
                'nic#stats#tx_pckts as tx_packets',
                'nic#stats#rx_pckts as rx_packets',
                'nic#stats#tx_bytes as tx_bytes',
                'nic#stats#rx_bytes as rx_bytes',
                'nic_dmz#stats#txbps as dmz_tx_bps',
                'nic_dmz#stats#rxbps as dmz_rx_bps',
                'nic_dmz#stats#tx_pckts as dmz_tx_packets',
                'nic_dmz#stats#rx_pckts as dmz_rx_packets',
                'nic_dmz#stats#tx_bytes as dmz_tx_bytes',
                'nic_dmz#stats#rx_bytes as dmz_rx_bytes'
            ) -join ','
        }

        try {
            $response = Invoke-VergeAPI -Method GET -Endpoint 'vnets' -Query $query -Connection $Server

            # Handle response
            $statsData = if ($null -eq $response) {
                $null
            }
            elseif ($response -is [array]) {
                $response | Select-Object -First 1
            }
            else {
                $response
            }

            if (-not $statsData) {
                Write-Warning "No statistics available for network '$($targetNetwork.Name)'"
                return
            }

            # Helper to format bytes
            $formatBytes = {
                param($bytes)
                if ($null -eq $bytes -or $bytes -eq 0) { return '0 B' }
                $units = @('B', 'KB', 'MB', 'GB', 'TB')
                $unitIndex = 0
                $size = [double]$bytes
                while ($size -ge 1024 -and $unitIndex -lt $units.Count - 1) {
                    $size /= 1024
                    $unitIndex++
                }
                return "{0:N2} {1}" -f $size, $units[$unitIndex]
            }

            # Create typed output object
            $output = [PSCustomObject]@{
                PSTypeName       = 'Verge.NetworkStatistics'
                NetworkKey       = $targetNetwork.Key
                NetworkName      = $targetNetwork.Name
                PowerState       = $targetNetwork.PowerState
                # Router interface
                TxBytesPerSec    = $statsData.tx_bps
                RxBytesPerSec    = $statsData.rx_bps
                TxPacketsPerSec  = $statsData.tx_packets
                RxPacketsPerSec  = $statsData.rx_packets
                TxBytesTotal     = $statsData.tx_bytes
                RxBytesTotal     = $statsData.rx_bytes
                TxTotalFormatted = & $formatBytes $statsData.tx_bytes
                RxTotalFormatted = & $formatBytes $statsData.rx_bytes
                # DMZ interface
                DMZTxBytesPerSec   = $statsData.dmz_tx_bps
                DMZRxBytesPerSec   = $statsData.dmz_rx_bps
                DMZTxPacketsPerSec = $statsData.dmz_tx_packets
                DMZRxPacketsPerSec = $statsData.dmz_rx_packets
                DMZTxBytesTotal    = $statsData.dmz_tx_bytes
                DMZRxBytesTotal    = $statsData.dmz_rx_bytes
            }

            # Get historical data if requested
            if ($IncludeHistory) {
                $historyQuery = @{
                    filter = "vnet eq $($targetNetwork.Key)"
                    fields = 'timestamp,sent,dropped,quality,latency_usec_avg,latency_usec_peak'
                    sort   = '-timestamp'
                    limit  = 60
                }

                $historyResponse = Invoke-VergeAPI -Method GET -Endpoint 'vnet_monitor_stats_history_short' -Query $historyQuery -Connection $Server

                $history = if ($null -eq $historyResponse) {
                    @()
                }
                elseif ($historyResponse -is [array]) {
                    $historyResponse
                }
                elseif ($historyResponse.'$key') {
                    @($historyResponse)
                }
                else {
                    @()
                }

                $historyObjects = foreach ($h in $history) {
                    [PSCustomObject]@{
                        Timestamp      = [DateTimeOffset]::FromUnixTimeSeconds($h.timestamp).LocalDateTime
                        Sent           = $h.sent
                        Dropped        = $h.dropped
                        Quality        = $h.quality
                        LatencyAvgMs   = [math]::Round($h.latency_usec_avg / 1000, 2)
                        LatencyPeakMs  = [math]::Round($h.latency_usec_peak / 1000, 2)
                    }
                }

                $output | Add-Member -MemberType NoteProperty -Name 'MonitorHistory' -Value $historyObjects
            }

            Write-Output $output
        }
        catch {
            Write-Error -Message "Failed to query network statistics: $($_.Exception.Message)" -ErrorId 'StatisticsQueryFailed'
        }
    }
}
