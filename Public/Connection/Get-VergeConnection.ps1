function Get-VergeConnection {
    <#
    .SYNOPSIS
        Gets active VergeOS connections.

    .DESCRIPTION
        Get-VergeConnection displays information about active connections
        to VergeOS systems. Use this to see which servers you're connected
        to and which is the default.

    .PARAMETER Server
        Filter connections by server name.

    .PARAMETER Default
        Return only the default connection.

    .EXAMPLE
        Get-VergeConnection

        Lists all active VergeOS connections.

    .EXAMPLE
        Get-VergeConnection -Default

        Returns the current default connection.

    .EXAMPLE
        Get-VergeConnection -Server "prod*"

        Lists connections matching the server name pattern.

    .OUTPUTS
        VergeConnection

    .NOTES
        The default connection is used by cmdlets when no -Server parameter
        is specified. Use Set-VergeConnection to change the default.
    #>
    [CmdletBinding(DefaultParameterSetName = 'All')]
    [OutputType('VergeConnection')]
    param(
        [Parameter(ParameterSetName = 'Server')]
        [SupportsWildcards()]
        [string]$Server,

        [Parameter(ParameterSetName = 'Default')]
        [switch]$Default
    )

    if ($Default) {
        if (-not $script:DefaultConnection) {
            Write-Warning 'No default VergeOS connection. Use Connect-VergeOS to establish a connection.'
            return
        }
        return $script:DefaultConnection
    }

    $connections = $script:VergeConnections

    if ($Server) {
        $connections = $connections | Where-Object { $_.Server -like $Server }
    }

    if ($connections.Count -eq 0) {
        if ($Server) {
            Write-Warning "No connections found matching '$Server'."
        }
        else {
            Write-Warning 'No active VergeOS connections. Use Connect-VergeOS to establish a connection.'
        }
        return
    }

    # Add IsDefault property for display
    foreach ($conn in $connections) {
        $isDefault = ($conn -eq $script:DefaultConnection)
        $conn | Add-Member -NotePropertyName 'IsDefault' -NotePropertyValue $isDefault -Force
    }

    return $connections
}
