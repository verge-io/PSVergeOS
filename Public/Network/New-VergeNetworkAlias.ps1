function New-VergeNetworkAlias {
    <#
    .SYNOPSIS
        Creates a new IP alias on a VergeOS virtual network.

    .DESCRIPTION
        New-VergeNetworkAlias creates an IP alias that can be referenced in firewall rules.
        IP aliases allow grouping addresses for easier rule management.

    .PARAMETER Network
        The name or key of the network to create the alias on.

    .PARAMETER NetworkObject
        A network object from Get-VergeNetwork. Accepts pipeline input.

    .PARAMETER IP
        The IP address for the alias.

    .PARAMETER Name
        A name/hostname for the alias. Used to reference it in rules.

    .PARAMETER Description
        An optional description for the alias.

    .PARAMETER PassThru
        Return the created alias object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeNetworkAlias -Network "External" -IP "10.0.0.100" -Name "webserver"

        Creates an IP alias for 10.0.0.100 named "webserver".

    .EXAMPLE
        New-VergeNetworkAlias -Network "External" -IP "192.168.1.0/24" -Name "internal-net" -Description "Internal network range"

        Creates an alias for a subnet range.

    .OUTPUTS
        None by default. Verge.NetworkAlias when -PassThru is specified.

    .NOTES
        Reference aliases in firewall rules using alias:name syntax.
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
        [string]$IP,

        [Parameter(Mandatory, Position = 2)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [string]$Description,

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
            throw "Network '$Network' not found"
        }

        # Build request body
        $body = @{
            vnet     = $targetNetwork.Key
            ip       = $IP
            hostname = $Name
            type     = 'ipalias'
        }

        if ($Description) {
            $body['description'] = $Description
        }

        if ($PSCmdlet.ShouldProcess("$Name ($IP)", "Create IP Alias on $($targetNetwork.Name)")) {
            try {
                Write-Verbose "Creating IP alias '$Name' ($IP) on network '$($targetNetwork.Name)'"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'vnet_addresses' -Body $body -Connection $Server

                # Get the created alias key
                $aliasKey = $response.'$key'
                if (-not $aliasKey -and $response.key) {
                    $aliasKey = $response.key
                }

                Write-Verbose "IP alias created with Key: $aliasKey"

                if ($PassThru -and $aliasKey) {
                    # Return the created alias
                    Start-Sleep -Milliseconds 500
                    Get-VergeNetworkAlias -Network $targetNetwork.Key -Key $aliasKey -Server $Server
                }
            }
            catch {
                $errorMessage = $_.Exception.Message
                if ($errorMessage -match 'already exists') {
                    throw "An IP alias for '$IP' already exists on network '$($targetNetwork.Name)'."
                }
                throw "Failed to create IP alias: $errorMessage"
            }
        }
    }
}
