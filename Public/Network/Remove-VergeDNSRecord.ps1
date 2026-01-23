function Remove-VergeDNSRecord {
    <#
    .SYNOPSIS
        Deletes a DNS record from a VergeOS DNS zone.

    .DESCRIPTION
        Remove-VergeDNSRecord deletes one or more DNS records from a zone.

    .PARAMETER Record
        A DNS record object from Get-VergeDNSRecord. Accepts pipeline input.

    .PARAMETER ZoneKey
        The unique key of the DNS zone containing the record.

    .PARAMETER Key
        The unique key of the record to delete.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeDNSZone -Network "Internal" -Domain "example.com" | Get-VergeDNSRecord -Host "test" | Remove-VergeDNSRecord

        Deletes all DNS records named "test" from example.com.

    .EXAMPLE
        Remove-VergeDNSRecord -ZoneKey 123 -Key 456 -Confirm:$false

        Deletes record with key 456 without confirmation.

    .OUTPUTS
        None

    .NOTES
        DNS changes may require DNS apply on the network.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByRecord')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByRecord')]
        [PSTypeName('Verge.DNSRecord')]
        [PSCustomObject]$Record,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$ZoneKey,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

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
        # Get record to delete
        $targetRecord = if ($PSCmdlet.ParameterSetName -eq 'ByRecord') {
            $Record
        }
        else {
            Get-VergeDNSRecord -ZoneKey $ZoneKey -Key $Key -Server $Server
        }

        if (-not $targetRecord) {
            Write-Error -Message "DNS record not found" -ErrorId 'RecordNotFound'
            return
        }

        $displayHost = if ($targetRecord.Host) { $targetRecord.Host } else { '@' }
        $displayName = "$displayHost $($targetRecord.Type) $($targetRecord.Value)"

        if ($PSCmdlet.ShouldProcess($displayName, "Remove DNS Record")) {
            try {
                Write-Verbose "Deleting DNS record '$displayName' (Key: $($targetRecord.Key))"
                $response = Invoke-VergeAPI -Method DELETE -Endpoint "vnet_dns_zone_records/$($targetRecord.Key)" -Connection $Server

                Write-Verbose "DNS record '$displayName' deleted successfully"
            }
            catch {
                Write-Error -Message "Failed to delete DNS record '$displayName': $($_.Exception.Message)" -ErrorId 'DNSRecordDeleteFailed'
            }
        }
    }
}
