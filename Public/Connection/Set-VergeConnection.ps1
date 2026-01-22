function Set-VergeConnection {
    <#
    .SYNOPSIS
        Sets the default VergeOS connection.

    .DESCRIPTION
        Set-VergeConnection changes which connection is used by default
        when cmdlets are executed without specifying a -Server parameter.

    .PARAMETER Server
        The server name of the connection to set as default.

    .PARAMETER Connection
        The connection object to set as default.

    .PARAMETER PassThru
        Return the connection object after setting it as default.

    .EXAMPLE
        Set-VergeConnection -Server "prod.vergeos.local"

        Sets the connection to prod.vergeos.local as the default.

    .EXAMPLE
        $conn | Set-VergeConnection

        Sets the piped connection as the default.

    .OUTPUTS
        VergeConnection (when -PassThru is specified)

    .NOTES
        Only connections that have been established with Connect-VergeOS
        can be set as the default.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Server')]
    [OutputType('VergeConnection')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Server', Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Server,

        [Parameter(Mandatory, ParameterSetName = 'Connection', ValueFromPipeline)]
        $Connection,

        [Parameter()]
        [switch]$PassThru
    )

    process {
        $targetConnection = $null

        if ($PSCmdlet.ParameterSetName -eq 'Server') {
            $targetConnection = $script:VergeConnections | Where-Object { $_.Server -eq $Server }
            if (-not $targetConnection) {
                Write-Error -Message "No connection found for server '$Server'. Use Connect-VergeOS first." -ErrorId 'ConnectionNotFound'
                return
            }
        }
        else {
            $targetConnection = $Connection

            # Verify the connection is in our list
            if ($targetConnection -notin $script:VergeConnections) {
                Write-Error -Message "The specified connection is not in the active connections list." -ErrorId 'ConnectionNotRegistered'
                return
            }
        }

        $script:DefaultConnection = $targetConnection
        Write-Verbose "Default connection set to $($targetConnection.Server)"

        if ($PassThru) {
            return $targetConnection
        }
    }
}
