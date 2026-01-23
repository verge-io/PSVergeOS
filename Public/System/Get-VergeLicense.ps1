function Get-VergeLicense {
    <#
    .SYNOPSIS
        Retrieves license information from VergeOS.

    .DESCRIPTION
        Get-VergeLicense retrieves one or more licenses from a VergeOS system.
        Returns license details including name, description, validity dates,
        features, and auto-renewal status.

    .PARAMETER Name
        The name of the license to retrieve. Supports wildcards (* and ?).
        If not specified, all licenses are returned.

    .PARAMETER Key
        The unique key (ID) of the license to retrieve.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeLicense

        Retrieves all licenses from the connected VergeOS system.

    .EXAMPLE
        Get-VergeLicense -Name "Production*"

        Retrieves licenses with names starting with "Production".

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.License'

    .NOTES
        Contact VergeOS support for license-related inquiries.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Filter')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ParameterSetName = 'Filter')]
        [SupportsWildcards()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey', ValueFromPipelineByPropertyName)]
        [Alias('Id', '$key')]
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
        try {
            Write-Verbose "Querying licenses from $($Server.Server)"

            # Build query parameters
            $queryParams = @{}
            $filters = [System.Collections.Generic.List[string]]::new()

            # Filter by key
            if ($PSCmdlet.ParameterSetName -eq 'ByKey') {
                $filters.Add("`$key eq $Key")
            }
            elseif ($Name) {
                if ($Name -match '[\*\?]') {
                    $searchTerm = $Name -replace '[\*\?]', ''
                    if ($searchTerm) {
                        $filters.Add("name ct '$searchTerm'")
                    }
                }
                else {
                    $filters.Add("name eq '$Name'")
                }
            }

            # Apply filters
            if ($filters.Count -gt 0) {
                $queryParams['filter'] = $filters -join ' and '
            }

            # Request fields
            $queryParams['fields'] = @(
                '$key'
                'name'
                'description'
                'added'
                'added_by'
                'issued'
                'valid_from'
                'valid_until'
                'features'
                'allow_branding'
                'auto_renewal'
                'note'
            ) -join ','

            $response = Invoke-VergeAPI -Method GET -Endpoint 'licenses' -Query $queryParams -Connection $Server

            # Handle both single object and array responses
            $licenses = if ($response -is [array]) { $response } else { @($response) }

            foreach ($license in $licenses) {
                # Skip null entries
                if (-not $license -or (-not $license.name -and -not $license.'$key')) {
                    continue
                }

                # Determine validity status
                $now = [DateTimeOffset]::Now.ToUnixTimeSeconds()
                $isValid = $true
                if ($license.valid_from -and $now -lt $license.valid_from) {
                    $isValid = $false
                }
                if ($license.valid_until -and $now -gt $license.valid_until) {
                    $isValid = $false
                }

                # Parse features JSON if present
                $featuresObj = $null
                if ($license.features) {
                    if ($license.features -is [string]) {
                        try {
                            $featuresObj = $license.features | ConvertFrom-Json
                        }
                        catch {
                            $featuresObj = $license.features
                        }
                    }
                    else {
                        $featuresObj = $license.features
                    }
                }

                # Create output object
                $output = [PSCustomObject]@{
                    PSTypeName     = 'Verge.License'
                    Key            = [int]$license.'$key'
                    Name           = $license.name
                    Description    = $license.description
                    IsValid        = $isValid
                    Features       = $featuresObj
                    AllowBranding  = [bool]$license.allow_branding
                    AutoRenewal    = [bool]$license.auto_renewal
                    AddedBy        = $license.added_by
                    Note           = $license.note
                    Added          = if ($license.added) { [DateTimeOffset]::FromUnixTimeSeconds($license.added).LocalDateTime } else { $null }
                    Issued         = if ($license.issued) { [DateTimeOffset]::FromUnixTimeSeconds($license.issued).LocalDateTime } else { $null }
                    ValidFrom      = if ($license.valid_from) { [DateTimeOffset]::FromUnixTimeSeconds($license.valid_from).LocalDateTime } else { $null }
                    ValidUntil     = if ($license.valid_until) { [DateTimeOffset]::FromUnixTimeSeconds($license.valid_until).LocalDateTime } else { $null }
                }

                # Add hidden properties for pipeline support
                $output | Add-Member -MemberType NoteProperty -Name '_Connection' -Value $Server -Force

                Write-Output $output
            }
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}
