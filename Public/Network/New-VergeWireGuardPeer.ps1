function New-VergeWireGuardPeer {
    <#
    .SYNOPSIS
        Creates a new WireGuard VPN peer on a VergeOS WireGuard interface.

    .DESCRIPTION
        New-VergeWireGuardPeer creates a peer configuration for a WireGuard
        interface. This defines a remote endpoint that can connect to the tunnel.

    .PARAMETER WireGuard
        A WireGuard interface object from Get-VergeWireGuard. Accepts pipeline input.

    .PARAMETER WireGuardKey
        The key of the WireGuard interface.

    .PARAMETER Name
        A unique name for the peer.

    .PARAMETER PeerIP
        The tunnel IP address for routing between endpoints.

    .PARAMETER PublicKey
        The public key of the remote peer (base64 encoded).

    .PARAMETER AllowedIPs
        Comma-separated list of allowed IP ranges (e.g., "10.0.0.0/24,192.168.1.0/24").

    .PARAMETER Endpoint
        IP address or hostname of the remote peer. Leave empty for roaming clients.

    .PARAMETER Port
        Remote peer port. Default: 51820.

    .PARAMETER PresharedKey
        Optional preshared key for additional security (post-quantum resistance).

    .PARAMETER Keepalive
        Keepalive interval in seconds. 0 to disable (default).

    .PARAMETER ConfigureFirewall
        Firewall rule configuration: SiteToSite, RemoteUser, or None (default: SiteToSite).

    .PARAMETER Description
        Optional description for the peer.

    .PARAMETER Enabled
        Whether the peer is enabled. Default: true.

    .PARAMETER PassThru
        Return the created peer object.

    .PARAMETER Server
        The VergeOS connection to use.

    .EXAMPLE
        Get-VergeWireGuard -Network "Internal" -Name "wg0" | New-VergeWireGuardPeer -Name "remote-office" -PeerIP "10.100.0.2" -PublicKey "abc123..." -AllowedIPs "192.168.1.0/24"

        Creates a site-to-site peer.

    .EXAMPLE
        New-VergeWireGuardPeer -WireGuardKey 123 -Name "laptop" -PeerIP "10.100.0.10" -PublicKey "xyz789..." -AllowedIPs "10.100.0.10/32" -ConfigureFirewall RemoteUser -Keepalive 25

        Creates a remote user peer with keepalive.

    .OUTPUTS
        None by default. Verge.WireGuardPeer when -PassThru is specified.

    .NOTES
        The peer's public key is required and must be obtained from the remote device.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByWireGuard')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByWireGuard')]
        [PSTypeName('Verge.WireGuard')]
        [PSCustomObject]$WireGuard,

        [Parameter(Mandatory, ParameterSetName = 'ByWireGuardKey')]
        [int]$WireGuardKey,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidateLength(1, 128)]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^(\d{1,3}\.){3}\d{1,3}$')]
        [string]$PeerIP,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PublicKey,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$AllowedIPs,

        [Parameter()]
        [string]$Endpoint,

        [Parameter()]
        [ValidateRange(1, 65535)]
        [int]$Port = 51820,

        [Parameter()]
        [string]$PresharedKey,

        [Parameter()]
        [ValidateRange(0, 65535)]
        [int]$Keepalive = 0,

        [Parameter()]
        [ValidateSet('SiteToSite', 'RemoteUser', 'None')]
        [string]$ConfigureFirewall = 'SiteToSite',

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

        # Map friendly names to API values
        $firewallMap = @{
            'SiteToSite' = 'site-to-site'
            'RemoteUser' = 'remote-user'
            'None'       = 'none'
        }
    }

    process {
        # Get WireGuard key
        $wgKey = if ($PSCmdlet.ParameterSetName -eq 'ByWireGuard') {
            $WireGuard.Key
        }
        else {
            $WireGuardKey
        }

        $wgName = if ($PSCmdlet.ParameterSetName -eq 'ByWireGuard') {
            $WireGuard.Name
        }
        else {
            "WireGuard $WireGuardKey"
        }

        # Build body
        $body = @{
            wireguard          = $wgKey
            name               = $Name
            enabled            = $Enabled
            peer_ip            = $PeerIP
            public_key         = $PublicKey
            allowed_ips        = $AllowedIPs
            port               = $Port
            keepalive          = $Keepalive
            configure_firewall = $firewallMap[$ConfigureFirewall]
        }

        if ($Endpoint) {
            $body['endpoint'] = $Endpoint
        }

        if ($PresharedKey) {
            $body['preshared_key'] = $PresharedKey
        }

        if ($Description) {
            $body['description'] = $Description
        }

        if ($PSCmdlet.ShouldProcess("$Name ($PeerIP) on $wgName", "Create WireGuard Peer")) {
            try {
                Write-Verbose "Creating WireGuard peer '$Name' on '$wgName'"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'vnet_wireguard_peers' -Body $body -Connection $Server

                $peerKey = $response.'$key'
                if (-not $peerKey -and $response.key) {
                    $peerKey = $response.key
                }

                Write-Verbose "WireGuard peer created with Key: $peerKey"

                if ($PassThru -and $peerKey) {
                    Start-Sleep -Milliseconds 500
                    Get-VergeWireGuardPeer -WireGuardKey $wgKey -Key $peerKey -Server $Server
                }
            }
            catch {
                throw "Failed to create WireGuard peer: $($_.Exception.Message)"
            }
        }
    }
}
