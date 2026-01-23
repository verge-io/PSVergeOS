function Set-VergeIPSecConnection {
    <#
    .SYNOPSIS
        Modifies an existing IPSec VPN connection on a VergeOS network.

    .DESCRIPTION
        Set-VergeIPSecConnection updates the configuration of an existing
        IPSec Phase 1 (IKE) VPN connection.

    .PARAMETER Connection
        An IPSec connection object from Get-VergeIPSecConnection. Accepts pipeline input.

    .PARAMETER Key
        The unique key of the connection to modify.

    .PARAMETER Name
        New name for the connection.

    .PARAMETER RemoteGateway
        New remote gateway IP address or hostname.

    .PARAMETER PreSharedKey
        New pre-shared key for authentication.

    .PARAMETER KeyExchange
        New IKE version: IKEv1, IKEv2, or Auto.

    .PARAMETER Encryption
        New IKE encryption algorithms.

    .PARAMETER IKELifetime
        New IKE SA lifetime in seconds.

    .PARAMETER ConnectionMode
        New connection behavior: ResponderOnly, OnDemand, or Start.

    .PARAMETER Identifier
        New local identifier.

    .PARAMETER PeerIdentifier
        New remote peer identifier.

    .PARAMETER Negotiation
        New negotiation mode: Main or Aggressive.

    .PARAMETER DPDAction
        New Dead Peer Detection action: Disabled, Clear, Hold, or Restart.

    .PARAMETER DPDDelay
        New DPD delay in seconds.

    .PARAMETER ForceUDPEncap
        Enable or disable forced UDP encapsulation.

    .PARAMETER MOBIKE
        Enable or disable MOBIKE protocol.

    .PARAMETER Description
        New description for the connection.

    .PARAMETER Enabled
        Enable or disable the connection.

    .PARAMETER PassThru
        Return the modified connection object.

    .PARAMETER Server
        The VergeOS connection to use.

    .EXAMPLE
        Get-VergeIPSecConnection -Network "External" -Name "Site-B" | Set-VergeIPSecConnection -Enabled $false

        Disables the Site-B IPSec connection.

    .EXAMPLE
        Set-VergeIPSecConnection -Key 123 -RemoteGateway "198.51.100.1" -PreSharedKey "NewKey456"

        Updates the remote gateway and PSK for connection with key 123.

    .OUTPUTS
        None by default. Verge.IPSecConnection when -PassThru is specified.

    .NOTES
        Changes may require network apply to take effect.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByConnection')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByConnection')]
        [PSTypeName('Verge.IPSecConnection')]
        [PSCustomObject]$Connection,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [ValidateLength(1, 128)]
        [string]$Name,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$RemoteGateway,

        [Parameter()]
        [string]$PreSharedKey,

        [Parameter()]
        [ValidateSet('Auto', 'IKEv1', 'IKEv2')]
        [string]$KeyExchange,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Encryption,

        [Parameter()]
        [ValidateRange(60, 86400)]
        [int]$IKELifetime,

        [Parameter()]
        [ValidateSet('ResponderOnly', 'OnDemand', 'Start')]
        [string]$ConnectionMode,

        [Parameter()]
        [string]$Identifier,

        [Parameter()]
        [string]$PeerIdentifier,

        [Parameter()]
        [ValidateSet('Main', 'Aggressive')]
        [string]$Negotiation,

        [Parameter()]
        [ValidateSet('Disabled', 'Clear', 'Hold', 'Restart')]
        [string]$DPDAction,

        [Parameter()]
        [ValidateRange(0, 3600)]
        [int]$DPDDelay,

        [Parameter()]
        [bool]$ForceUDPEncap,

        [Parameter()]
        [bool]$MOBIKE,

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
        # Get target connection
        $targetKey = if ($PSCmdlet.ParameterSetName -eq 'ByConnection') {
            $Connection.Key
        }
        else {
            $Key
        }

        $displayName = if ($PSCmdlet.ParameterSetName -eq 'ByConnection') {
            $Connection.Name
        }
        else {
            "Key $Key"
        }

        # Build update body with only changed parameters
        $body = @{}

        if ($PSBoundParameters.ContainsKey('Name')) {
            $body['name'] = $Name
        }

        if ($PSBoundParameters.ContainsKey('RemoteGateway')) {
            $body['remote_gateway'] = $RemoteGateway
        }

        if ($PSBoundParameters.ContainsKey('PreSharedKey')) {
            $body['psk'] = $PreSharedKey
        }

        if ($PSBoundParameters.ContainsKey('KeyExchange')) {
            $body['keyexchange'] = $keyExchangeApiMap[$KeyExchange]
        }

        if ($PSBoundParameters.ContainsKey('Encryption')) {
            $body['ike'] = $Encryption
        }

        if ($PSBoundParameters.ContainsKey('IKELifetime')) {
            $body['ikelifetime'] = $IKELifetime
        }

        if ($PSBoundParameters.ContainsKey('ConnectionMode')) {
            $body['auto'] = $connectionModeApiMap[$ConnectionMode]
        }

        if ($PSBoundParameters.ContainsKey('Identifier')) {
            $body['identifier'] = $Identifier
        }

        if ($PSBoundParameters.ContainsKey('PeerIdentifier')) {
            $body['peer_identifier'] = $PeerIdentifier
        }

        if ($PSBoundParameters.ContainsKey('Negotiation')) {
            $body['negotiation'] = $Negotiation.ToLower()
        }

        if ($PSBoundParameters.ContainsKey('DPDAction')) {
            $body['dpdaction'] = $dpdActionApiMap[$DPDAction]
        }

        if ($PSBoundParameters.ContainsKey('DPDDelay')) {
            $body['dpddelay'] = $DPDDelay
        }

        if ($PSBoundParameters.ContainsKey('ForceUDPEncap')) {
            $body['forceencaps'] = $ForceUDPEncap
        }

        if ($PSBoundParameters.ContainsKey('MOBIKE')) {
            $body['mobike'] = $MOBIKE
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

        if ($PSCmdlet.ShouldProcess($displayName, "Update IPSec Connection")) {
            try {
                Write-Verbose "Updating IPSec connection '$displayName' (Key: $targetKey)"
                $response = Invoke-VergeAPI -Method PUT -Endpoint "vnet_ipsec_phase1s/$targetKey" -Body $body -Connection $Server

                Write-Verbose "IPSec connection '$displayName' updated successfully"

                if ($PassThru) {
                    # Need network key to retrieve the connection
                    $networkKey = if ($PSCmdlet.ParameterSetName -eq 'ByConnection') {
                        $Connection.NetworkKey
                    }
                    else {
                        # Query to find the network
                        $phase1 = Invoke-VergeAPI -Method GET -Endpoint "vnet_ipsec_phase1s/$targetKey" -Connection $Server
                        $ipsec = Invoke-VergeAPI -Method GET -Endpoint "vnet_ipsecs/$($phase1.ipsec)" -Connection $Server
                        $ipsec.vnet
                    }

                    Start-Sleep -Milliseconds 500
                    Get-VergeIPSecConnection -Network $networkKey -Key $targetKey -Server $Server
                }
            }
            catch {
                Write-Error -Message "Failed to update IPSec connection '$displayName': $($_.Exception.Message)" -ErrorId 'IPSecUpdateFailed'
            }
        }
    }
}
