function Get-VergeGroup {
    <#
    .SYNOPSIS
        Retrieves groups from VergeOS.

    .DESCRIPTION
        Get-VergeGroup retrieves one or more groups from a VergeOS system.
        You can filter groups by name or enabled status. Supports wildcards for
        name filtering.

    .PARAMETER Name
        The name of the group to retrieve. Supports wildcards (* and ?).
        If not specified, all groups are returned.

    .PARAMETER Key
        The unique key (ID) of the group to retrieve.

    .PARAMETER Enabled
        Filter groups by enabled status. Use $true or $false.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeGroup

        Retrieves all groups from the connected VergeOS system.

    .EXAMPLE
        Get-VergeGroup -Name "Administrators"

        Retrieves the Administrators group.

    .EXAMPLE
        Get-VergeGroup -Name "Dev*"

        Retrieves all groups whose names start with "Dev".

    .EXAMPLE
        Get-VergeGroup -Enabled $true

        Retrieves all enabled groups.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.Group'

    .NOTES
        Use New-VergeGroup to create groups.
        Use Add-VergeGroupMember to add users to groups.
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

        [Parameter(ParameterSetName = 'Filter')]
        [bool]$Enabled,

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
        # Build query parameters
        $queryParams = @{}

        # Build filter string
        $filters = [System.Collections.Generic.List[string]]::new()

        # Filter by key
        if ($PSCmdlet.ParameterSetName -eq 'ByKey') {
            $filters.Add("`$key eq $Key")
        }
        else {
            # Filter by name (with wildcard support)
            if ($Name) {
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

            # Filter by enabled status
            if ($PSBoundParameters.ContainsKey('Enabled')) {
                $enabledValue = if ($Enabled) { 'true' } else { 'false' }
                $filters.Add("enabled eq $enabledValue")
            }
        }

        # Apply filters
        if ($filters.Count -gt 0) {
            $queryParams['filter'] = $filters -join ' and '
        }

        # Select fields
        $queryParams['fields'] = @(
            '$key'
            'name'
            'description'
            'enabled'
            'created'
            'email'
            'id'
            'identity'
            'system_group'
            'creator'
            'count(members) as member_count'
        ) -join ','

        try {
            Write-Verbose "Querying groups from $($Server.Server)"
            $response = Invoke-VergeAPI -Method GET -Endpoint 'groups' -Query $queryParams -Connection $Server

            # Handle both single object and array responses
            $groups = if ($response -is [array]) { $response } else { @($response) }

            foreach ($group in $groups) {
                # Skip null entries
                if (-not $group -or -not $group.name) {
                    continue
                }

                # Convert timestamps
                $createdDate = if ($group.created -and $group.created -gt 0) {
                    [DateTimeOffset]::FromUnixTimeSeconds($group.created).LocalDateTime
                } else { $null }

                # Create output object
                $output = [PSCustomObject]@{
                    PSTypeName    = 'Verge.Group'
                    Key           = [int]$group.'$key'
                    Name          = $group.name
                    Description   = $group.description
                    Enabled       = [bool]$group.enabled
                    Email         = $group.email
                    Identifier    = $group.id
                    Identity      = $group.identity
                    IsSystemGroup = [bool]$group.system_group
                    MemberCount   = [int]$group.member_count
                    Created       = $createdDate
                    Creator       = $group.creator
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
