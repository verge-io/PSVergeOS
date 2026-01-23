function Get-VergeSystemSetting {
    <#
    .SYNOPSIS
        Retrieves system settings from VergeOS.

    .DESCRIPTION
        Get-VergeSystemSetting retrieves one or more system settings from a VergeOS system.
        Settings are key-value pairs that control system behavior.

    .PARAMETER Key
        The key name of the setting to retrieve. Supports wildcards (* and ?).
        If not specified, all settings are returned.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeSystemSetting

        Retrieves all system settings.

    .EXAMPLE
        Get-VergeSystemSetting -Key "ui_*"

        Retrieves all UI-related settings.

    .EXAMPLE
        Get-VergeSystemSetting -Key "max_connections"

        Retrieves the max_connections setting.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.SystemSetting'

    .NOTES
        System settings control various aspects of VergeOS behavior.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [SupportsWildcards()]
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
            Write-Verbose "Querying system settings from $($Server.Server)"

            # Build query parameters
            $queryParams = @{}
            $filters = [System.Collections.Generic.List[string]]::new()

            # Filter by key
            if ($Key) {
                if ($Key -match '[\*\?]') {
                    $searchTerm = $Key -replace '[\*\?]', ''
                    if ($searchTerm) {
                        $filters.Add("key ct '$searchTerm'")
                    }
                }
                else {
                    $filters.Add("key eq '$Key'")
                }
            }

            # Apply filters
            if ($filters.Count -gt 0) {
                $queryParams['filter'] = $filters -join ' and '
            }

            # Request fields (note: settings uses 'key' as the keyfield, so $key is the string key)
            $queryParams['fields'] = @(
                'key'
                'value'
                'default_value'
                'description'
            ) -join ','

            $response = Invoke-VergeAPI -Method GET -Endpoint 'settings' -Query $queryParams -Connection $Server

            # Handle both single object and array responses
            $settings = if ($response -is [array]) { $response } else { @($response) }

            foreach ($setting in $settings) {
                # Skip null entries
                if (-not $setting -or -not $setting.key) {
                    continue
                }

                # Create output object
                $output = [PSCustomObject]@{
                    PSTypeName    = 'Verge.SystemSetting'
                    Key           = $setting.key
                    Value         = $setting.value
                    DefaultValue  = $setting.default_value
                    Description   = $setting.description
                    IsModified    = ($setting.value -ne $setting.default_value)
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
