function Get-VergeNodeDriver {
    <#
    .SYNOPSIS
        Retrieves node drivers from VergeOS.

    .DESCRIPTION
        Get-VergeNodeDriver retrieves drivers installed on VergeOS nodes.
        This includes GPU drivers, network drivers, and other hardware-specific drivers.

    .PARAMETER Node
        The name of the node to retrieve drivers for. Supports wildcards (* and ?).
        If not specified, drivers for all nodes are returned.

    .PARAMETER NodeObject
        A node object from Get-VergeNode to retrieve drivers for.

    .PARAMETER DriverName
        Filter drivers by driver name. Supports wildcards (* and ?).

    .PARAMETER Status
        Filter drivers by status: Installed, Verifying, or Error.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeNodeDriver

        Retrieves all drivers from all nodes.

    .EXAMPLE
        Get-VergeNodeDriver -Node "node1"

        Retrieves all drivers installed on node1.

    .EXAMPLE
        Get-VergeNodeDriver -DriverName "*nvidia*"

        Retrieves all NVIDIA-related drivers.

    .EXAMPLE
        Get-VergeNode -Name "node1" | Get-VergeNodeDriver

        Retrieves drivers for node1 using pipeline input.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.NodeDriver'

    .NOTES
        Driver installation may require node reboot to complete.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Filter')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ParameterSetName = 'Filter')]
        [SupportsWildcards()]
        [string]$Node,

        [Parameter(Mandatory, ParameterSetName = 'ByNode', ValueFromPipeline)]
        [PSTypeName('Verge.Node')]
        [PSCustomObject]$NodeObject,

        [Parameter()]
        [SupportsWildcards()]
        [string]$DriverName,

        [Parameter()]
        [ValidateSet('Installed', 'Verifying', 'Error')]
        [string]$Status,

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
            Write-Verbose "Querying node drivers from $($Server.Server)"

            # Build query parameters
            $queryParams = @{}
            $filters = [System.Collections.Generic.List[string]]::new()

            # Handle node filter
            if ($PSCmdlet.ParameterSetName -eq 'ByNode') {
                $filters.Add("node eq $($NodeObject.Key)")
                if ($NodeObject._Connection) {
                    $Server = $NodeObject._Connection
                }
            }
            elseif ($Node) {
                # Lookup node by name to get the key
                $nodeObj = Get-VergeNode -Name $Node -Server $Server | Select-Object -First 1
                if ($nodeObj) {
                    $filters.Add("node eq $($nodeObj.Key)")
                }
                else {
                    Write-Warning "Node '$Node' not found"
                    return
                }
            }

            # Filter by driver name
            if ($DriverName) {
                if ($DriverName -match '[\*\?]') {
                    $searchTerm = $DriverName -replace '[\*\?]', ''
                    if ($searchTerm) {
                        $filters.Add("driver_name ct '$searchTerm'")
                    }
                }
                else {
                    $filters.Add("driver_name eq '$DriverName'")
                }
            }

            # Filter by status
            if ($Status) {
                $statusMap = @{
                    'Installed'  = 'complete'
                    'Verifying'  = 'verifying'
                    'Error'      = 'error'
                }
                $filters.Add("status eq '$($statusMap[$Status])'")
            }

            # Apply filters
            if ($filters.Count -gt 0) {
                $queryParams['filter'] = $filters -join ' and '
            }

            # Request fields
            $queryParams['fields'] = @(
                '$key'
                'node'
                'node#name as node_name'
                'driver_file'
                'driver_file#name as driver_file_name'
                'driver_key'
                'driver_name'
                'description'
                'status'
                'status_info'
                'class_filter'
                'vendor_filter'
                'modified'
            ) -join ','

            $response = Invoke-VergeAPI -Method GET -Endpoint 'node_drivers' -Query $queryParams -Connection $Server

            # Handle both single object and array responses
            $drivers = if ($response -is [array]) { $response } else { @($response) }

            foreach ($driver in $drivers) {
                # Skip null entries
                if (-not $driver -or -not $driver.driver_name) {
                    continue
                }

                # Map status to user-friendly string
                $statusDisplay = switch ($driver.status) {
                    'complete'   { 'Installed' }
                    'verifying'  { 'Verifying' }
                    'error'      { 'Error' }
                    default      { $driver.status }
                }

                # Create output object
                $output = [PSCustomObject]@{
                    PSTypeName    = 'Verge.NodeDriver'
                    Key           = [int]$driver.'$key'
                    Node          = $driver.node_name
                    NodeKey       = $driver.node
                    DriverName    = $driver.driver_name
                    DriverKey     = $driver.driver_key
                    DriverFile    = $driver.driver_file_name
                    DriverFileKey = $driver.driver_file
                    Description   = $driver.description
                    Status        = $statusDisplay
                    StatusInfo    = $driver.status_info
                    ClassFilter   = $driver.class_filter
                    VendorFilter  = $driver.vendor_filter
                    Modified      = if ($driver.modified) { [DateTimeOffset]::FromUnixTimeSeconds($driver.modified).LocalDateTime } else { $null }
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
