function Get-VergeStorageTier {
    <#
    .SYNOPSIS
        Retrieves storage tier information from VergeOS.

    .DESCRIPTION
        Get-VergeStorageTier retrieves storage tier details from a VergeOS system,
        including capacity, usage statistics, IOPS, throughput, and deduplication ratios.

    .PARAMETER Tier
        Filter by specific tier number (0-5).

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeStorageTier

        Lists all storage tiers with capacity and usage information.

    .EXAMPLE
        Get-VergeStorageTier -Tier 1

        Gets details for storage tier 1.

    .EXAMPLE
        Get-VergeStorageTier | Format-Table Tier, UsedGB, CapacityGB, UsedPercent

        Lists all tiers in a table format with usage statistics.

    .EXAMPLE
        Get-VergeStorageTier | Where-Object { $_.UsedPercent -gt 80 }

        Lists tiers that are more than 80% full.

    .OUTPUTS
        Verge.StorageTier objects containing:
        - Tier: The tier number
        - Description: Tier description
        - CapacityGB: Total capacity in GB
        - UsedGB: Used space in GB
        - AllocatedGB: Allocated space in GB
        - UsedPercent: Percentage of capacity used
        - DedupeRatio: Deduplication ratio
        - ReadOps: Current read operations per second
        - WriteOps: Current write operations per second
        - ReadBytesPerSec: Current read throughput
        - WriteBytesPerSec: Current write throughput

    .NOTES
        Storage tiers in VergeOS represent different performance levels of storage.
        Tier 1 is typically the fastest (SSD/NVMe), while higher tiers may be slower.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [ValidateRange(0, 5)]
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
    }

    process {
        try {
            # Build query parameters
            $queryParams = @{}

            # Request the list view which includes stats
            $queryParams['fields'] = @(
                '$key'
                'tier'
                'description'
                'capacity'
                'used'
                'allocated'
                'used_inflated'
                'dedupe_ratio'
                'modified'
                'stats#reads as total_reads'
                'stats#writes as total_writes'
                'stats#read_bytes as total_read_bytes'
                'stats#write_bytes as total_write_bytes'
                'stats#rops as read_ops'
                'stats#wops as write_ops'
                'stats#rbps as read_bps'
                'stats#wbps as write_bps'
            ) -join ','

            # Filter by tier if specified
            if ($PSBoundParameters.ContainsKey('Tier')) {
                $queryParams['filter'] = "tier eq $Tier"
            }

            Write-Verbose "Querying storage tiers from $($Server.Server)"
            $response = Invoke-VergeAPI -Method GET -Endpoint 'storage_tiers' -Query $queryParams -Connection $Server

            # Handle both single object and array responses
            $tiers = if ($response -is [array]) { $response } else { @($response) }

            foreach ($tierData in $tiers) {
                # Skip null entries
                if (-not $tierData) {
                    continue
                }

                # Convert bytes to GB (storage_tiers uses 4096-byte blocks, already normalized)
                $capacityGB = if ($tierData.capacity) { [math]::Round($tierData.capacity / 1073741824, 2) } else { 0 }
                $usedGB = if ($tierData.used) { [math]::Round($tierData.used / 1073741824, 2) } else { 0 }
                $allocatedGB = if ($tierData.allocated) { [math]::Round($tierData.allocated / 1073741824, 2) } else { 0 }
                $usedInflatedGB = if ($tierData.used_inflated) { [math]::Round($tierData.used_inflated / 1073741824, 2) } else { 0 }

                # Calculate free space
                $freeGB = $capacityGB - $usedGB

                # Calculate used percentage
                $usedPercent = if ($capacityGB -gt 0) {
                    [math]::Round(($usedGB / $capacityGB) * 100, 1)
                } else { 0 }

                # Calculate deduplication savings
                $dedupeRatio = if ($tierData.dedupe_ratio) {
                    [math]::Round($tierData.dedupe_ratio / 100, 2)
                } else { 1.0 }

                # Convert throughput to human-readable
                $readBps = if ($tierData.read_bps) { $tierData.read_bps } else { 0 }
                $writeBps = if ($tierData.write_bps) { $tierData.write_bps } else { 0 }

                # Convert modified timestamp
                $modified = $null
                if ($tierData.modified) {
                    $modified = [DateTimeOffset]::FromUnixTimeSeconds($tierData.modified).LocalDateTime
                }

                [PSCustomObject]@{
                    PSTypeName        = 'Verge.StorageTier'
                    Key               = $tierData.'$key' ?? $tierData.tier
                    Tier              = [int]$tierData.tier
                    Description       = $tierData.description
                    CapacityGB        = $capacityGB
                    UsedGB            = $usedGB
                    FreeGB            = $freeGB
                    AllocatedGB       = $allocatedGB
                    UsedInflatedGB    = $usedInflatedGB
                    UsedPercent       = $usedPercent
                    DedupeRatio       = $dedupeRatio
                    CapacityBytes     = $tierData.capacity
                    UsedBytes         = $tierData.used
                    AllocatedBytes    = $tierData.allocated
                    TotalReads        = $tierData.total_reads
                    TotalWrites       = $tierData.total_writes
                    TotalReadBytes    = $tierData.total_read_bytes
                    TotalWriteBytes   = $tierData.total_write_bytes
                    ReadOps           = $tierData.read_ops
                    WriteOps          = $tierData.write_ops
                    ReadBytesPerSec   = $readBps
                    WriteBytesPerSec  = $writeBps
                    Modified          = $modified
                }
            }
        }
        catch {
            Write-Error -Message "Failed to get storage tiers: $($_.Exception.Message)" -ErrorId 'GetStorageTiersFailed'
        }
    }
}
