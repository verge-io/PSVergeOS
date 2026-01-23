function New-VergeNetworkHost {
    <#
    .SYNOPSIS
        Creates a new DNS/DHCP host override on a VergeOS virtual network.

    .DESCRIPTION
        New-VergeNetworkHost creates a host override that maps a hostname to an IP address.
        This provides static DNS entries and DHCP hostname assignment.

    .PARAMETER Network
        The name or key of the network to create the host override on.

    .PARAMETER NetworkObject
        A network object from Get-VergeNetwork. Accepts pipeline input.

    .PARAMETER Hostname
        The hostname or domain name for the override.

    .PARAMETER IP
        The IP address to map to the hostname.

    .PARAMETER Type
        The type of override: Host (default) or Domain.

    .PARAMETER PassThru
        Return the created host override object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeNetworkHost -Network "Internal" -Hostname "server01" -IP "10.0.0.50"

        Creates a host override mapping server01 to 10.0.0.50.

    .EXAMPLE
        New-VergeNetworkHost -Network "Internal" -Hostname "mail.example.com" -IP "10.0.0.25" -Type Domain

        Creates a domain override for mail.example.com.

    .OUTPUTS
        None by default. Verge.NetworkHost when -PassThru is specified.

    .NOTES
        Host overrides require DNS apply to take effect.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByNetworkName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByNetworkName')]
        [string]$Network,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByNetworkObject')]
        [PSTypeName('Verge.Network')]
        [PSCustomObject]$NetworkObject,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$Hostname,

        [Parameter(Mandatory, Position = 2)]
        [ValidatePattern('^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$')]
        [string]$IP,

        [Parameter()]
        [ValidateSet('Host', 'Domain')]
        [string]$Type = 'Host',

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

        # Map friendly type names to API values
        $typeMap = @{
            'Host'   = 'host'
            'Domain' = 'domain'
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
            throw "Network '$Network' not found"
        }

        # Build request body
        $body = @{
            vnet = $targetNetwork.Key
            host = $Hostname
            ip   = $IP
            type = $typeMap[$Type]
        }

        if ($PSCmdlet.ShouldProcess("$Hostname -> $IP", "Create Host Override on $($targetNetwork.Name)")) {
            try {
                Write-Verbose "Creating host override '$Hostname' -> '$IP' on network '$($targetNetwork.Name)'"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'vnet_hosts' -Body $body -Connection $Server

                # Get the created host key
                $hostKey = $response.'$key'
                if (-not $hostKey -and $response.key) {
                    $hostKey = $response.key
                }

                Write-Verbose "Host override created with Key: $hostKey"

                if ($PassThru -and $hostKey) {
                    # Return the created host
                    Start-Sleep -Milliseconds 500
                    Get-VergeNetworkHost -Network $targetNetwork.Key -Key $hostKey -Server $Server
                }
            }
            catch {
                $errorMessage = $_.Exception.Message
                if ($errorMessage -match 'already exists') {
                    throw "A host override for '$Hostname' already exists on network '$($targetNetwork.Name)'."
                }
                throw "Failed to create host override: $errorMessage"
            }
        }
    }
}
