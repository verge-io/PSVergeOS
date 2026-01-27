function New-VergeDNSRecord {
    <#
    .SYNOPSIS
        Creates a new DNS record in a VergeOS DNS zone.

    .DESCRIPTION
        New-VergeDNSRecord creates a DNS record in a specified zone.
        After creating records, DNS apply may be required.

    .PARAMETER Zone
        A DNS zone object from Get-VergeDNSZone. Accepts pipeline input.

    .PARAMETER ZoneKey
        The unique key of the DNS zone to create the record in.

    .PARAMETER HostName
        The hostname for the record (e.g., "www", "@" for root, or blank to inherit).

    .PARAMETER Type
        The record type: A, AAAA, CNAME, MX, NS, PTR, SRV, TXT, CAA.

    .PARAMETER Value
        The value for the record (IP address, hostname, or text depending on type).

    .PARAMETER TTL
        Time-to-live for the record (e.g., "1h", "30m", "1d").

    .PARAMETER MXPreference
        Preference value for MX records (lower = higher priority).

    .PARAMETER Weight
        Weight for SRV records.

    .PARAMETER Port
        Port for SRV records.

    .PARAMETER Description
        An optional description for the record.

    .PARAMETER PassThru
        Return the created record object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeDNSZone -Network "Internal" -Domain "example.com" | New-VergeDNSRecord -HostName "www" -Type A -Value "10.0.0.100"

        Creates an A record for www.example.com pointing to 10.0.0.100.

    .EXAMPLE
        New-VergeDNSRecord -ZoneKey 123 -Host "mail" -Type MX -Value "mail.example.com" -MXPreference 10

        Creates an MX record with preference 10.

    .OUTPUTS
        None by default. Verge.DNSRecord when -PassThru is specified.

    .NOTES
        DNS changes may require DNS apply on the network.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByZone')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByZone')]
        [PSTypeName('Verge.DNSZone')]
        [PSCustomObject]$Zone,

        [Parameter(Mandatory, ParameterSetName = 'ByZoneKey')]
        [int]$ZoneKey,

        [Parameter()]
        [string]$HostName = '',

        [Parameter(Mandatory)]
        [ValidateSet('A', 'AAAA', 'CNAME', 'MX', 'NS', 'PTR', 'SRV', 'TXT', 'CAA')]
        [string]$Type,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Value,

        [Parameter()]
        [string]$TTL,

        [Parameter()]
        [int]$MXPreference = 0,

        [Parameter()]
        [int]$Weight = 0,

        [Parameter()]
        [int]$Port = 0,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [switch]$PassThru,

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
        # Get zone key
        $targetZoneKey = if ($PSCmdlet.ParameterSetName -eq 'ByZone') {
            $Zone.Key
        }
        else {
            $ZoneKey
        }

        # Build request body
        $body = @{
            zone  = $targetZoneKey
            host  = $HostName
            type  = $Type
            value = $Value
        }

        if ($TTL) {
            $body['ttl'] = $TTL
        }

        if ($MXPreference -gt 0) {
            $body['mx_preference'] = $MXPreference
        }

        if ($Weight -gt 0) {
            $body['weight'] = $Weight
        }

        if ($Port -gt 0) {
            $body['port'] = $Port
        }

        if ($Description) {
            $body['description'] = $Description
        }

        $displayHost = if ($HostName) { $HostName } else { '@' }

        if ($PSCmdlet.ShouldProcess("$displayHost $Type $Value", "Create DNS Record")) {
            try {
                Write-Verbose "Creating DNS record '$displayHost' $Type -> '$Value' in zone (Key: $targetZoneKey)"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'vnet_dns_zone_records' -Body $body -Connection $Server

                # Get the created record key
                $recordKey = $response.'$key'
                if (-not $recordKey -and $response.key) {
                    $recordKey = $response.key
                }

                Write-Verbose "DNS record created with Key: $recordKey"

                if ($PassThru -and $recordKey) {
                    # Return the created record
                    Start-Sleep -Milliseconds 500
                    Get-VergeDNSRecord -ZoneKey $targetZoneKey -Key $recordKey -Server $Server
                }
            }
            catch {
                throw "Failed to create DNS record: $($_.Exception.Message)"
            }
        }
    }
}
