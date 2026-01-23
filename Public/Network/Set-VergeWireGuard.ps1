function Set-VergeWireGuard {
    <#
    .SYNOPSIS
        Modifies an existing WireGuard VPN interface on a VergeOS network.

    .DESCRIPTION
        Set-VergeWireGuard updates the configuration of an existing
        WireGuard VPN interface.

    .PARAMETER WireGuard
        A WireGuard interface object from Get-VergeWireGuard. Accepts pipeline input.

    .PARAMETER Key
        The unique key of the interface to modify.

    .PARAMETER Name
        New name for the interface.

    .PARAMETER IPAddress
        New tunnel IP address in CIDR notation.

    .PARAMETER ListenPort
        New UDP listen port.

    .PARAMETER MTU
        New MTU value. 0 for auto-configuration.

    .PARAMETER EndpointIP
        New public endpoint IP for peer configurations.

    .PARAMETER Description
        New description for the interface.

    .PARAMETER Enabled
        Enable or disable the interface.

    .PARAMETER PassThru
        Return the modified interface object.

    .PARAMETER Server
        The VergeOS connection to use.

    .EXAMPLE
        Get-VergeWireGuard -Network "Internal" -Name "wg0" | Set-VergeWireGuard -Enabled $false

        Disables the wg0 WireGuard interface.

    .EXAMPLE
        Set-VergeWireGuard -Key 123 -ListenPort 51821 -PassThru

        Changes the listen port for interface with key 123.

    .OUTPUTS
        None by default. Verge.WireGuard when -PassThru is specified.

    .NOTES
        Changes may require network apply to take effect.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByWireGuard')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByWireGuard')]
        [PSTypeName('Verge.WireGuard')]
        [PSCustomObject]$WireGuard,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [ValidateLength(1, 128)]
        [string]$Name,

        [Parameter()]
        [ValidatePattern('^(\d{1,3}\.){3}\d{1,3}/\d{1,2}$')]
        [string]$IPAddress,

        [Parameter()]
        [ValidateRange(1, 65535)]
        [int]$ListenPort,

        [Parameter()]
        [ValidateRange(0, 65535)]
        [int]$MTU,

        [Parameter()]
        [string]$EndpointIP,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [bool]$Enabled,

        [Parameter()]
        [switch]$PassThru,

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
        # Get target
        $targetKey = if ($PSCmdlet.ParameterSetName -eq 'ByWireGuard') {
            $WireGuard.Key
        }
        else {
            $Key
        }

        $displayName = if ($PSCmdlet.ParameterSetName -eq 'ByWireGuard') {
            $WireGuard.Name
        }
        else {
            "Key $Key"
        }

        # Build update body
        $body = @{}

        if ($PSBoundParameters.ContainsKey('Name')) {
            $body['name'] = $Name
        }

        if ($PSBoundParameters.ContainsKey('IPAddress')) {
            $body['ip'] = $IPAddress
        }

        if ($PSBoundParameters.ContainsKey('ListenPort')) {
            $body['listenport'] = $ListenPort
        }

        if ($PSBoundParameters.ContainsKey('MTU')) {
            $body['mtu'] = $MTU
        }

        if ($PSBoundParameters.ContainsKey('EndpointIP')) {
            $body['endpoint_ip'] = $EndpointIP
        }

        if ($PSBoundParameters.ContainsKey('Description')) {
            $body['description'] = $Description
        }

        if ($PSBoundParameters.ContainsKey('Enabled')) {
            $body['enabled'] = $Enabled
        }

        if ($body.Count -eq 0) {
            Write-Warning "No parameters specified to update"
            return
        }

        if ($PSCmdlet.ShouldProcess($displayName, "Update WireGuard Interface")) {
            try {
                Write-Verbose "Updating WireGuard interface '$displayName' (Key: $targetKey)"
                $response = Invoke-VergeAPI -Method PUT -Endpoint "vnet_wireguards/$targetKey" -Body $body -Connection $Server

                Write-Verbose "WireGuard interface '$displayName' updated successfully"

                if ($PassThru) {
                    $networkKey = if ($PSCmdlet.ParameterSetName -eq 'ByWireGuard') {
                        $WireGuard.NetworkKey
                    }
                    else {
                        $wg = Invoke-VergeAPI -Method GET -Endpoint "vnet_wireguards/$targetKey" -Connection $Server
                        $wg.vnet
                    }

                    Start-Sleep -Milliseconds 500
                    Get-VergeWireGuard -Network $networkKey -Key $targetKey -Server $Server
                }
            }
            catch {
                Write-Error -Message "Failed to update WireGuard interface '$displayName': $($_.Exception.Message)" -ErrorId 'WireGuardUpdateFailed'
            }
        }
    }
}
