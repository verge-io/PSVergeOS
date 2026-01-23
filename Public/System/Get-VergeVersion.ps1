function Get-VergeVersion {
    <#
    .SYNOPSIS
        Retrieves VergeOS system version information.

    .DESCRIPTION
        Get-VergeVersion retrieves version information from a VergeOS system,
        including the VergeOS version, kernel version, vSAN version, and other
        component versions. By default returns information from the first online node.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeVersion

        Retrieves version information from the connected VergeOS system.

    .EXAMPLE
        Get-VergeVersion | Format-List

        Displays all version details in list format.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.Version'

    .NOTES
        Version information is retrieved from the first online node in the cluster.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
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
            Write-Verbose "Querying version information from $($Server.Server)"

            # Get version info from nodes - we want the first online node
            $queryParams = @{
                fields = @(
                    '$key'
                    'name'
                    'yb_version'
                    'os_version'
                    'kernel_version'
                    'appserver_version'
                    'vsan_version'
                    'qemu_version'
                    'machine#status#running as running'
                ) -join ','
                sort   = '+$key'
                limit  = '1'
            }

            $response = Invoke-VergeAPI -Method GET -Endpoint 'nodes' -Query $queryParams -Connection $Server

            # Handle response
            $node = if ($response -is [array]) { $response[0] } else { $response }

            if (-not $node) {
                throw [System.InvalidOperationException]::new('No nodes found in the VergeOS system.')
            }

            # Create output object
            $output = [PSCustomObject]@{
                PSTypeName        = 'Verge.Version'
                VergeOSVersion    = $node.yb_version
                OSVersion         = $node.os_version
                KernelVersion     = $node.kernel_version
                AppServerVersion  = $node.appserver_version
                vSANVersion       = $node.vsan_version
                QEMUVersion       = $node.qemu_version
                SourceNode        = $node.name
                Server            = $Server.Server
            }

            # Add hidden connection property
            $output | Add-Member -MemberType NoteProperty -Name '_Connection' -Value $Server -Force

            Write-Output $output
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}
