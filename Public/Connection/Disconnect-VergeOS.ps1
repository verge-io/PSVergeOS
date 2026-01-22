function Disconnect-VergeOS {
    <#
    .SYNOPSIS
        Closes a connection to a VergeOS system.

    .DESCRIPTION
        Disconnect-VergeOS closes and removes a VergeOS connection.
        If the connection was the default, another connection becomes
        the default (if available).

    .PARAMETER Server
        The server name of the connection to close.

    .PARAMETER Connection
        The connection object to close.

    .PARAMETER All
        Close all active connections.

    .EXAMPLE
        Disconnect-VergeOS

        Disconnects from the default VergeOS connection.

    .EXAMPLE
        Disconnect-VergeOS -Server "prod.vergeos.local"

        Disconnects from a specific server.

    .EXAMPLE
        Disconnect-VergeOS -All

        Disconnects from all VergeOS systems.

    .NOTES
        If the disconnected connection was the default, another connection
        automatically becomes the default (if any remain).
    #>
    [CmdletBinding(DefaultParameterSetName = 'Default', SupportsShouldProcess)]
    param(
        [Parameter(ParameterSetName = 'Server')]
        [string]$Server,

        [Parameter(ParameterSetName = 'Connection', ValueFromPipeline)]
        $Connection,

        [Parameter(ParameterSetName = 'All')]
        [switch]$All
    )

    process {
        if ($All) {
            if ($PSCmdlet.ShouldProcess('All connections', 'Disconnect')) {
                foreach ($conn in $script:VergeConnections) {
                    $conn.Disconnect()
                    Write-Verbose "Disconnected from $($conn.Server)"
                }
                $script:VergeConnections.Clear()
                $script:DefaultConnection = $null
            }
            return
        }

        # Determine which connection to disconnect
        $targetConnection = $null

        if ($PSCmdlet.ParameterSetName -eq 'Server') {
            $targetConnection = $script:VergeConnections | Where-Object { $_.Server -eq $Server }
            if (-not $targetConnection) {
                Write-Error -Message "No connection found for server '$Server'" -ErrorId 'ConnectionNotFound'
                return
            }
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'Connection') {
            $targetConnection = $Connection
        }
        else {
            # Default - use the default connection
            $targetConnection = $script:DefaultConnection
            if (-not $targetConnection) {
                Write-Warning 'No active VergeOS connection to disconnect.'
                return
            }
        }

        if ($PSCmdlet.ShouldProcess($targetConnection.Server, 'Disconnect')) {
            # Invalidate the session
            $targetConnection.Disconnect()

            # Remove from connection list
            $script:VergeConnections.Remove($targetConnection) | Out-Null

            # Update default connection if needed
            if ($script:DefaultConnection -eq $targetConnection) {
                $script:DefaultConnection = $script:VergeConnections | Select-Object -First 1
                if ($script:DefaultConnection) {
                    Write-Verbose "Default connection changed to $($script:DefaultConnection.Server)"
                }
            }

            Write-Verbose "Disconnected from $($targetConnection.Server)"
        }
    }
}
