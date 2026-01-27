function Get-VergeDNSRecord {
    <#
    .SYNOPSIS
        Retrieves DNS records from a VergeOS DNS zone.

    .DESCRIPTION
        Get-VergeDNSRecord queries DNS records from a specific zone.

    .PARAMETER Zone
        A DNS zone object from Get-VergeDNSZone. Accepts pipeline input.

    .PARAMETER ZoneKey
        The unique key of the DNS zone to query records from.

    .PARAMETER HostName
        Filter by host/name. Supports wildcards (* and ?).

    .PARAMETER Type
        Filter by record type: A, AAAA, CNAME, MX, NS, PTR, SRV, TXT, CAA.

    .PARAMETER Key
        Get a specific record by its unique key.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeDNSZone -Network "Internal" -Domain "example.com" | Get-VergeDNSRecord

        Gets all records in the example.com zone.

    .EXAMPLE
        Get-VergeDNSRecord -ZoneKey 123 -Type A

        Gets all A records from zone with key 123.

    .EXAMPLE
        Get-VergeDNSRecord -ZoneKey 123 -HostName "www*"

        Gets all records starting with "www".

    .OUTPUTS
        Verge.DNSRecord

    .NOTES
        Use New-VergeDNSRecord and Remove-VergeDNSRecord to manage records.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByZone')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByZone')]
        [PSTypeName('Verge.DNSZone')]
        [PSCustomObject]$Zone,

        [Parameter(Mandatory, ParameterSetName = 'ByZoneKey')]
        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$ZoneKey,

        [Parameter()]
        [SupportsWildcards()]
        [string]$HostName,

        [Parameter()]
        [ValidateSet('A', 'AAAA', 'CNAME', 'MX', 'NS', 'PTR', 'SRV', 'TXT', 'CAA')]
        [string]$Type,

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
        # Get zone key
        $targetZoneKey = if ($PSCmdlet.ParameterSetName -eq 'ByZone') {
            $Zone.Key
        }
        else {
            $ZoneKey
        }

        Write-Verbose "Querying DNS records for zone (Key: $targetZoneKey)"

        # Build filter
        $filterParts = @("zone eq $targetZoneKey")

        if ($PSBoundParameters.ContainsKey('Key')) {
            $filterParts += "`$key eq $Key"
        }

        if ($HostName -and -not [WildcardPattern]::ContainsWildcardCharacters($HostName)) {
            $filterParts += "host eq '$HostName'"
        }

        if ($Type) {
            $filterParts += "type eq '$Type'"
        }

        $filter = $filterParts -join ' and '

        # Build query
        $query = @{
            filter = $filter
            fields = '$key,zone,host,type,value,ttl,mx_preference,weight,port,description'
            sort   = 'orderid'
        }

        try {
            $response = Invoke-VergeAPI -Method GET -Endpoint 'vnet_dns_zone_records' -Query $query -Connection $Server

            # Handle response
            $records = if ($null -eq $response) {
                @()
            }
            elseif ($response -is [array]) {
                $response
            }
            elseif ($response.'$key') {
                @($response)
            }
            else {
                @()
            }

            # Apply wildcard filtering if needed
            if ($HostName -and [WildcardPattern]::ContainsWildcardCharacters($HostName)) {
                $records = $records | Where-Object { $_.host -like $HostName }
            }

            foreach ($record in $records) {
                # Create typed output object
                $output = [PSCustomObject]@{
                    PSTypeName   = 'Verge.DNSRecord'
                    Key          = $record.'$key'
                    ZoneKey      = $record.zone
                    Host         = $record.host
                    Type         = $record.type
                    Value        = $record.value
                    TTL          = $record.ttl
                    MXPreference = $record.mx_preference
                    Weight       = $record.weight
                    Port         = $record.port
                    Description  = $record.description
                }

                Write-Output $output
            }
        }
        catch {
            Write-Error -Message "Failed to query DNS records: $($_.Exception.Message)" -ErrorId 'DNSRecordQueryFailed'
        }
    }
}
