function New-VergeIPSecPolicy {
    <#
    .SYNOPSIS
        Creates a new IPSec Phase 2 policy (traffic selector) on a VergeOS network.

    .DESCRIPTION
        New-VergeIPSecPolicy creates an IPSec Phase 2 policy that defines which
        traffic should be encrypted through the tunnel. This specifies local
        and remote networks for the security association.

    .PARAMETER Connection
        An IPSec connection object from Get-VergeIPSecConnection. Accepts pipeline input.

    .PARAMETER ConnectionKey
        The key of the IPSec Phase 1 connection.

    .PARAMETER Name
        A unique name for the policy.

    .PARAMETER LocalNetwork
        The local network/subnet in CIDR notation (e.g., "10.0.0.0/24").

    .PARAMETER RemoteNetwork
        The remote network/subnet in CIDR notation (e.g., "192.168.1.0/24").

    .PARAMETER Mode
        The IPSec mode: Tunnel (default) or Transport.

    .PARAMETER Protocol
        The security protocol: ESP (encrypted, default) or AH (auth only).

    .PARAMETER Ciphers
        The Phase 2 cipher suites.
        Default: "aes128-sha256-modp2048,aes128gcm128-sha256-modp2048"

    .PARAMETER Lifetime
        Lifetime of the security association in seconds. Default: 3600 (1 hour).

    .PARAMETER Description
        Optional description for the policy.

    .PARAMETER Enabled
        Whether the policy is enabled. Default: true.

    .PARAMETER PassThru
        Return the created policy object.

    .PARAMETER Server
        The VergeOS connection to use.

    .EXAMPLE
        Get-VergeIPSecConnection -Network "External" -Name "Site-B" | New-VergeIPSecPolicy -Name "LAN-to-LAN" -LocalNetwork "10.0.0.0/24" -RemoteNetwork "192.168.1.0/24"

        Creates a policy to tunnel traffic between the two LANs.

    .EXAMPLE
        New-VergeIPSecPolicy -ConnectionKey 123 -Name "All-Traffic" -LocalNetwork "0.0.0.0/0" -RemoteNetwork "0.0.0.0/0" -PassThru

        Creates a policy for all traffic through the tunnel.

    .OUTPUTS
        None by default. Verge.IPSecPolicy when -PassThru is specified.

    .NOTES
        At least one Phase 2 policy is required for tunnel traffic.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByConnection')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByConnection')]
        [PSTypeName('Verge.IPSecConnection')]
        [PSCustomObject]$Connection,

        [Parameter(Mandatory, ParameterSetName = 'ByConnectionKey')]
        [int]$ConnectionKey,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidateLength(1, 128)]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LocalNetwork,

        [Parameter()]
        [string]$RemoteNetwork,

        [Parameter()]
        [ValidateSet('Tunnel', 'Transport')]
        [string]$Mode = 'Tunnel',

        [Parameter()]
        [ValidateSet('ESP', 'AH')]
        [string]$Protocol = 'ESP',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Ciphers = 'aes128-sha256-modp2048,aes128gcm128-sha256-modp2048',

        [Parameter()]
        [ValidateRange(60, 86400)]
        [int]$Lifetime = 3600,

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
        # Get Phase 1 key
        $phase1Key = if ($PSCmdlet.ParameterSetName -eq 'ByConnection') {
            $Connection.Key
        }
        else {
            $ConnectionKey
        }

        $connName = if ($PSCmdlet.ParameterSetName -eq 'ByConnection') {
            $Connection.Name
        }
        else {
            "Connection $ConnectionKey"
        }

        # Build body
        $body = @{
            phase1   = $phase1Key
            enabled  = $Enabled
            name     = $Name
            local    = $LocalNetwork
            mode     = $Mode.ToLower()
            protocol = $Protocol.ToLower()
            ciphers  = $Ciphers
            lifetime = $Lifetime
        }

        if ($RemoteNetwork) {
            $body['remote'] = $RemoteNetwork
        }

        if ($Description) {
            $body['description'] = $Description
        }

        $displayTraffic = "$LocalNetwork -> $RemoteNetwork"
        if (-not $RemoteNetwork) {
            $displayTraffic = "$LocalNetwork -> (any)"
        }

        if ($PSCmdlet.ShouldProcess("$Name ($displayTraffic) on $connName", "Create IPSec Policy")) {
            try {
                Write-Verbose "Creating IPSec policy '$Name' for '$connName'"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'vnet_ipsec_phase2s' -Body $body -Connection $Server

                $policyKey = $response.'$key'
                if (-not $policyKey -and $response.key) {
                    $policyKey = $response.key
                }

                Write-Verbose "IPSec policy created with Key: $policyKey"

                if ($PassThru -and $policyKey) {
                    Start-Sleep -Milliseconds 500
                    Get-VergeIPSecPolicy -ConnectionKey $phase1Key -Key $policyKey -Server $Server
                }
            }
            catch {
                throw "Failed to create IPSec policy: $($_.Exception.Message)"
            }
        }
    }
}
