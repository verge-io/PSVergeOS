function Set-VergeNetworkHost {
    <#
    .SYNOPSIS
        Modifies an existing DNS/DHCP host override on a VergeOS virtual network.

    .DESCRIPTION
        Set-VergeNetworkHost modifies properties of an existing host override.

    .PARAMETER Network
        The name or key of the network containing the host override.

    .PARAMETER Hostname
        The hostname of the override to modify.

    .PARAMETER Key
        The unique key (ID) of the host override to modify.

    .PARAMETER HostObject
        A host override object from Get-VergeNetworkHost. Accepts pipeline input.

    .PARAMETER NewHostname
        A new hostname for the override.

    .PARAMETER IP
        A new IP address for the override.

    .PARAMETER Type
        A new type: Host or Domain.

    .PARAMETER PassThru
        Return the modified host override object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Set-VergeNetworkHost -Network "Internal" -Hostname "server01" -IP "10.0.0.51"

        Changes the IP address for server01.

    .EXAMPLE
        Get-VergeNetworkHost -Network "Internal" -Hostname "old*" | Set-VergeNetworkHost -Type Domain

        Changes all hosts starting with "old" to domain type.

    .OUTPUTS
        None by default. Verge.NetworkHost when -PassThru is specified.

    .NOTES
        Host override changes require DNS apply to take effect.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByHostname')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByHostname')]
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByKey')]
        [string]$Network,

        [Parameter(Mandatory, Position = 1, ParameterSetName = 'ByHostname')]
        [string]$Hostname,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByHostObject')]
        [PSTypeName('Verge.NetworkHost')]
        [PSCustomObject]$HostObject,

        [Parameter()]
        [string]$NewHostname,

        [Parameter()]
        [ValidatePattern('^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$')]
        [string]$IP,

        [Parameter()]
        [ValidateSet('Host', 'Domain')]
        [string]$Type,

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
        # Get the host to modify
        $targetHost = switch ($PSCmdlet.ParameterSetName) {
            'ByHostname' {
                Get-VergeNetworkHost -Network $Network -Hostname $Hostname -Server $Server
            }
            'ByKey' {
                Get-VergeNetworkHost -Network $Network -Key $Key -Server $Server
            }
            'ByHostObject' {
                $HostObject
            }
        }

        if (-not $targetHost) {
            Write-Error -Message "Host override not found" -ErrorId 'HostNotFound'
            return
        }

        # Handle multiple matches
        if ($targetHost -is [array]) {
            Write-Error -Message "Multiple host overrides matched. Please specify a unique hostname or use -Key." -ErrorId 'MultipleHostsMatched'
            return
        }

        # Build the update body with only specified parameters
        $body = @{}

        if ($PSBoundParameters.ContainsKey('NewHostname')) {
            $body['host'] = $NewHostname
        }

        if ($PSBoundParameters.ContainsKey('IP')) {
            $body['ip'] = $IP
        }

        if ($PSBoundParameters.ContainsKey('Type')) {
            $body['type'] = $typeMap[$Type]
        }

        # Validate we have something to update
        if ($body.Count -eq 0) {
            Write-Warning "No properties specified to update for host override '$($targetHost.Hostname)'."
            return
        }

        # Build description of changes for WhatIf
        $changesDescription = ($body.Keys | ForEach-Object { "$_ = $($body[$_])" }) -join ', '

        if ($PSCmdlet.ShouldProcess($targetHost.Hostname, "Set Host Override ($changesDescription)")) {
            try {
                Write-Verbose "Updating host override '$($targetHost.Hostname)' (Key: $($targetHost.Key))"
                $response = Invoke-VergeAPI -Method PUT -Endpoint "vnet_hosts/$($targetHost.Key)" -Body $body -Connection $Server

                Write-Verbose "Host override '$($targetHost.Hostname)' updated successfully"

                if ($PassThru) {
                    # Return refreshed host object
                    Start-Sleep -Milliseconds 500
                    Get-VergeNetworkHost -Network $targetHost.NetworkKey -Key $targetHost.Key -Server $Server
                }
            }
            catch {
                Write-Error -Message "Failed to update host override '$($targetHost.Hostname)': $($_.Exception.Message)" -ErrorId 'HostUpdateFailed'
            }
        }
    }
}
