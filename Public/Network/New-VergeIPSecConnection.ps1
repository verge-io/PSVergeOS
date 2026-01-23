function New-VergeIPSecConnection {
    <#
    .SYNOPSIS
        Creates a new IPSec VPN connection on a VergeOS network.

    .DESCRIPTION
        New-VergeIPSecConnection creates an IPSec Phase 1 (IKE) VPN connection.
        This establishes the IKE security association with a remote gateway.

    .PARAMETER Network
        The name or key of the network to create the connection on.

    .PARAMETER NetworkObject
        A network object from Get-VergeNetwork. Accepts pipeline input.

    .PARAMETER Name
        A unique name for the IPSec connection.

    .PARAMETER RemoteGateway
        The IP address or hostname of the remote VPN gateway.

    .PARAMETER PreSharedKey
        The pre-shared key for authentication. Required for PSK auth method.

    .PARAMETER KeyExchange
        The IKE version to use: IKEv1, IKEv2, or Auto (default).
        Auto uses IKEv2 when initiating and accepts either as responder.

    .PARAMETER Encryption
        The IKE encryption algorithms to use.
        Default: "aes256-sha256-modp2048"

    .PARAMETER IKELifetime
        Lifetime of the IKE SA in seconds. Default: 10800 (3 hours).

    .PARAMETER ConnectionMode
        How the connection should behave:
        - ResponderOnly: Load but don't initiate
        - OnDemand: Start when traffic is detected (default)
        - Start: Initiate immediately on startup

    .PARAMETER Identifier
        Local identifier for the connection. Defaults to local IP.

    .PARAMETER PeerIdentifier
        Remote peer identifier. Defaults to remote gateway.

    .PARAMETER Negotiation
        IKEv1 negotiation mode: Main (default) or Aggressive.

    .PARAMETER DPDAction
        Dead Peer Detection action: Disabled, Clear, Hold, or Restart (default).

    .PARAMETER DPDDelay
        Interval between DPD messages in seconds. Default: 30.

    .PARAMETER ForceUDPEncap
        Force UDP encapsulation even without NAT.

    .PARAMETER MOBIKE
        Enable IKEv2 MOBIKE protocol for mobility.

    .PARAMETER Description
        Optional description for the connection.

    .PARAMETER Enabled
        Whether the connection is enabled. Default: true.

    .PARAMETER PassThru
        Return the created connection object.

    .PARAMETER Server
        The VergeOS connection to use.

    .EXAMPLE
        New-VergeIPSecConnection -Network "External" -Name "Site-B" -RemoteGateway "203.0.113.1" -PreSharedKey "MySecretKey123"

        Creates a basic site-to-site VPN connection.

    .EXAMPLE
        $params = @{
            Network = "External"
            Name = "Azure-VPN"
            RemoteGateway = "azure-vpn.eastus.cloudapp.net"
            PreSharedKey = "ComplexKey!@#"
            KeyExchange = "IKEv2"
            Encryption = "aes256gcm16-sha384-modp2048"
            ConnectionMode = "Start"
        }
        New-VergeIPSecConnection @params -PassThru

        Creates an IKEv2 connection with custom encryption.

    .OUTPUTS
        None by default. Verge.IPSecConnection when -PassThru is specified.

    .NOTES
        After creating a connection, you need to add Phase 2 policies with
        New-VergeIPSecPolicy to define which traffic should traverse the tunnel.
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
        [string]$RemoteGateway,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PreSharedKey,

        [Parameter()]
        [ValidateSet('Auto', 'IKEv1', 'IKEv2')]
        [string]$KeyExchange = 'Auto',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Encryption = 'aes256-sha256-modp2048',

        [Parameter()]
        [ValidateRange(60, 86400)]
        [int]$IKELifetime = 10800,

        [Parameter()]
        [ValidateSet('ResponderOnly', 'OnDemand', 'Start')]
        [string]$ConnectionMode = 'OnDemand',

        [Parameter()]
        [string]$Identifier,

        [Parameter()]
        [string]$PeerIdentifier,

        [Parameter()]
        [ValidateSet('Main', 'Aggressive')]
        [string]$Negotiation = 'Main',

        [Parameter()]
        [ValidateSet('Disabled', 'Clear', 'Hold', 'Restart')]
        [string]$DPDAction = 'Restart',

        [Parameter()]
        [ValidateRange(0, 3600)]
        [int]$DPDDelay = 30,

        [Parameter()]
        [switch]$ForceUDPEncap,

        [Parameter()]
        [switch]$MOBIKE,

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
        $keyExchangeApiMap = @{
            'Auto'  = 'ike'
            'IKEv1' = 'ikev1'
            'IKEv2' = 'ikev2'
        }

        $connectionModeApiMap = @{
            'ResponderOnly' = 'add'
            'OnDemand'      = 'route'
            'Start'         = 'start'
        }

        $dpdActionApiMap = @{
            'Disabled' = 'none'
            'Clear'    = 'clear'
            'Hold'     = 'hold'
            'Restart'  = 'restart'
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

        # Get or create IPSec config for this network
        $ipsecQuery = @{
            filter = "vnet eq $($targetNetwork.Key)"
            fields = '$key'
        }

        $ipsecConfig = Invoke-VergeAPI -Method GET -Endpoint 'vnet_ipsecs' -Query $ipsecQuery -Connection $Server

        $ipsecKey = $null
        if ($ipsecConfig -and ($ipsecConfig.'$key' -or ($ipsecConfig -is [array] -and $ipsecConfig.Count -gt 0))) {
            $ipsecKey = if ($ipsecConfig -is [array]) { $ipsecConfig[0].'$key' } else { $ipsecConfig.'$key' }
        }

        if (-not $ipsecKey) {
            # Create IPSec config for this network
            Write-Verbose "Creating IPSec configuration for network '$($targetNetwork.Name)'"
            $ipsecBody = @{
                vnet    = $targetNetwork.Key
                enabled = $true
                mode    = 'normal'
            }

            $createResponse = Invoke-VergeAPI -Method POST -Endpoint 'vnet_ipsecs' -Body $ipsecBody -Connection $Server
            $ipsecKey = $createResponse.'$key'

            if (-not $ipsecKey) {
                Write-Error -Message "Failed to create IPSec configuration for network" -ErrorId 'IPSecConfigCreateFailed'
                return
            }
        }

        # Build Phase 1 body
        $body = @{
            ipsec          = $ipsecKey
            enabled        = $Enabled
            name           = $Name
            remote_gateway = $RemoteGateway
            auth           = 'psk'
            psk            = $PreSharedKey
            keyexchange    = $keyExchangeApiMap[$KeyExchange]
            ike            = $Encryption
            ikelifetime    = $IKELifetime
            auto           = $connectionModeApiMap[$ConnectionMode]
            negotiation    = $Negotiation.ToLower()
            dpdaction      = $dpdActionApiMap[$DPDAction]
            dpddelay       = $DPDDelay
            forceencaps    = $ForceUDPEncap.IsPresent
            mobike         = $MOBIKE.IsPresent
        }

        if ($Identifier) {
            $body['identifier'] = $Identifier
        }

        if ($PeerIdentifier) {
            $body['peer_identifier'] = $PeerIdentifier
        }

        if ($Description) {
            $body['description'] = $Description
        }

        if ($PSCmdlet.ShouldProcess("$Name to $RemoteGateway on $($targetNetwork.Name)", "Create IPSec Connection")) {
            try {
                Write-Verbose "Creating IPSec connection '$Name' to '$RemoteGateway'"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'vnet_ipsec_phase1s' -Body $body -Connection $Server

                $connKey = $response.'$key'
                if (-not $connKey -and $response.key) {
                    $connKey = $response.key
                }

                Write-Verbose "IPSec connection created with Key: $connKey"

                if ($PassThru -and $connKey) {
                    Start-Sleep -Milliseconds 500
                    Get-VergeIPSecConnection -Network $targetNetwork.Key -Key $connKey -Server $Server
                }
            }
            catch {
                throw "Failed to create IPSec connection: $($_.Exception.Message)"
            }
        }
    }
}
