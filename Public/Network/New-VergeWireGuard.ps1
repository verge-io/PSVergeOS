function New-VergeWireGuard {
    <#
    .SYNOPSIS
        Creates a new WireGuard VPN interface on a VergeOS network.

    .DESCRIPTION
        New-VergeWireGuard creates a WireGuard VPN interface. This defines
        the local tunnel endpoint with an IP address and listen port.

    .PARAMETER Network
        The name or key of the network to create the interface on.

    .PARAMETER NetworkObject
        A network object from Get-VergeNetwork. Accepts pipeline input.

    .PARAMETER Name
        A unique name for the WireGuard interface.

    .PARAMETER IPAddress
        The tunnel IP address in CIDR notation (e.g., "10.100.0.1/24").

    .PARAMETER ListenPort
        The UDP port to listen on. Default: 51820.

    .PARAMETER MTU
        The MTU for the interface. 0 for auto-configuration (default).

    .PARAMETER EndpointIP
        The public IP address for peer configurations. Auto-detected if not specified.

    .PARAMETER Description
        Optional description for the interface.

    .PARAMETER Enabled
        Whether the interface is enabled. Default: true.

    .PARAMETER PassThru
        Return the created interface object.

    .PARAMETER Server
        The VergeOS connection to use.

    .EXAMPLE
        New-VergeWireGuard -Network "Internal" -Name "wg0" -IPAddress "10.100.0.1/24"

        Creates a WireGuard interface with default settings.

    .EXAMPLE
        New-VergeWireGuard -Network "Internal" -Name "wg-remote" -IPAddress "10.100.0.1/24" -ListenPort 51821 -EndpointIP "203.0.113.50" -PassThru

        Creates an interface with custom port and endpoint.

    .OUTPUTS
        None by default. Verge.WireGuard when -PassThru is specified.

    .NOTES
        A key pair is automatically generated for the interface.
        Add peers with New-VergeWireGuardPeer.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByNetworkName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByNetworkName')]
        [string]$Network,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByNetworkObject')]
        [PSTypeName('Verge.Network')]
        [PSCustomObject]$NetworkObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidateLength(1, 128)]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^(\d{1,3}\.){3}\d{1,3}/\d{1,2}$')]
        [string]$IPAddress,

        [Parameter()]
        [ValidateRange(1, 65535)]
        [int]$ListenPort = 51820,

        [Parameter()]
        [ValidateRange(0, 65535)]
        [int]$MTU = 0,

        [Parameter()]
        [string]$EndpointIP,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [bool]$Enabled = $true,

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
        # Resolve network
        $targetNetwork = $null
        if ($PSCmdlet.ParameterSetName -eq 'ByNetworkObject') {
            $targetNetwork = $NetworkObject
        }
        else {
            if ($Network -match '^\d+$') {
                $targetNetwork = Get-VergeNetwork -Key ([int]$Network) -Server $Server
            }
            else {
                $targetNetwork = Get-VergeNetwork -Name $Network -Server $Server
            }
        }

        if (-not $targetNetwork) {
            Write-Error -Message "Network '$Network' not found" -ErrorId 'NetworkNotFound'
            return
        }

        # Build body
        $body = @{
            vnet       = $targetNetwork.Key
            name       = $Name
            enabled    = $Enabled
            ip         = $IPAddress
            listenport = $ListenPort
            mtu        = $MTU
        }

        if ($EndpointIP) {
            $body['endpoint_ip'] = $EndpointIP
        }

        if ($Description) {
            $body['description'] = $Description
        }

        if ($PSCmdlet.ShouldProcess("$Name ($IPAddress) on $($targetNetwork.Name)", "Create WireGuard Interface")) {
            try {
                Write-Verbose "Creating WireGuard interface '$Name' on network '$($targetNetwork.Name)'"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'vnet_wireguards' -Body $body -Connection $Server

                $ifaceKey = $response.'$key'
                if (-not $ifaceKey -and $response.key) {
                    $ifaceKey = $response.key
                }

                Write-Verbose "WireGuard interface created with Key: $ifaceKey"

                if ($PassThru -and $ifaceKey) {
                    Start-Sleep -Milliseconds 500
                    Get-VergeWireGuard -Network $targetNetwork.Key -Key $ifaceKey -Server $Server
                }
            }
            catch {
                throw "Failed to create WireGuard interface: $($_.Exception.Message)"
            }
        }
    }
}
