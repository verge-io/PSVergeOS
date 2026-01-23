function Get-VergeIPSecPolicy {
    <#
    .SYNOPSIS
        Retrieves IPSec Phase 2 policies (traffic selectors) from a VergeOS network.

    .DESCRIPTION
        Get-VergeIPSecPolicy returns IPSec Phase 2 policies that define which
        traffic should be encrypted through the IPSec tunnel. These are also
        known as traffic selectors or security associations.

    .PARAMETER Connection
        An IPSec connection object from Get-VergeIPSecConnection. Accepts pipeline input.

    .PARAMETER ConnectionKey
        The key of the IPSec Phase 1 connection.

    .PARAMETER Name
        Filter by policy name. Supports wildcards.

    .PARAMETER Key
        Get a specific policy by its unique key.

    .PARAMETER Server
        The VergeOS connection to use.

    .EXAMPLE
        Get-VergeIPSecConnection -Network "External" -Name "Site-B" | Get-VergeIPSecPolicy

        Gets all Phase 2 policies for the Site-B connection.

    .EXAMPLE
        Get-VergeIPSecPolicy -ConnectionKey 123 -Name "LAN*"

        Gets policies matching the wildcard pattern.

    .OUTPUTS
        Verge.IPSecPolicy

    .NOTES
        Phase 2 policies define local and remote networks for tunnel traffic.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByConnection')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByConnection')]
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByConnectionAndKey')]
        [PSTypeName('Verge.IPSecConnection')]
        [PSCustomObject]$Connection,

        [Parameter(Mandatory, ParameterSetName = 'ByConnectionKey')]
        [Parameter(Mandatory, ParameterSetName = 'ByConnectionKeyAndKey')]
        [int]$ConnectionKey,

        [Parameter(ParameterSetName = 'ByConnection')]
        [Parameter(ParameterSetName = 'ByConnectionKey')]
        [SupportsWildcards()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByConnectionAndKey')]
        [Parameter(Mandatory, ParameterSetName = 'ByConnectionKeyAndKey')]
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

        # Protocol mapping
        $protocolMap = @{
            'esp' = 'ESP (Encrypted)'
            'ah'  = 'AH (Auth Only)'
        }

        # Mode mapping
        $modeMap = @{
            'tunnel'    = 'Tunnel'
            'transport' = 'Transport'
        }
    }

    process {
        # Get Phase 1 key - match only sets that use $Connection object (not $ConnectionKey)
        $useConnectionObject = $PSCmdlet.ParameterSetName -in @('ByConnection', 'ByConnectionAndKey')

        $phase1Key = if ($useConnectionObject) {
            $Connection.Key
        }
        else {
            $ConnectionKey
        }

        $connName = if ($useConnectionObject) {
            $Connection.Name
        }
        else {
            "Connection $ConnectionKey"
        }

        Write-Verbose "Querying IPSec policies for '$connName'"

        try {
            # Build query
            $query = @{
                fields = '$key,phase1,enabled,name,description,mode,local,remote,lifetime,protocol,ciphers,modified'
                sort   = 'name'
            }

            # Add filters
            $filters = @("phase1 eq $phase1Key")

            if ($PSCmdlet.ParameterSetName -like '*AndKey') {
                $filters += "`$key eq $Key"
            }
            elseif ($Name -and -not [WildcardPattern]::ContainsWildcardCharacters($Name)) {
                $filters += "name eq '$Name'"
            }

            $query['filter'] = $filters -join ' and '

            $response = Invoke-VergeAPI -Method GET -Endpoint 'vnet_ipsec_phase2s' -Query $query -Connection $Server

            # Handle response
            $policies = if ($null -eq $response) {
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

            # Apply wildcard filter if needed
            if ($Name -and [WildcardPattern]::ContainsWildcardCharacters($Name)) {
                $policies = $policies | Where-Object { $_.name -like $Name }
            }

            foreach ($policy in $policies) {
                [PSCustomObject]@{
                    PSTypeName      = 'Verge.IPSecPolicy'
                    Key             = $policy.'$key'
                    Phase1Key       = $policy.phase1
                    ConnectionName  = $connName
                    Name            = $policy.name
                    Description     = $policy.description
                    Enabled         = $policy.enabled
                    Mode            = if ($modeMap[$policy.mode]) { $modeMap[$policy.mode] } else { $policy.mode }
                    ModeRaw         = $policy.mode
                    LocalNetwork    = $policy.local
                    RemoteNetwork   = $policy.remote
                    Lifetime        = $policy.lifetime
                    Protocol        = if ($protocolMap[$policy.protocol]) { $protocolMap[$policy.protocol] } else { $policy.protocol }
                    ProtocolRaw     = $policy.protocol
                    Ciphers         = $policy.ciphers
                    Modified        = if ($policy.modified) {
                        [DateTimeOffset]::FromUnixTimeSeconds($policy.modified).LocalDateTime
                    } else { $null }
                }
            }
        }
        catch {
            Write-Error -Message "Failed to query IPSec policies: $($_.Exception.Message)" -ErrorId 'IPSecPolicyQueryFailed'
        }
    }
}
