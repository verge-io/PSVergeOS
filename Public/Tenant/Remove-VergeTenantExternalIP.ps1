function Remove-VergeTenantExternalIP {
    <#
    .SYNOPSIS
        Removes an external IP address assignment from a VergeOS tenant.

    .DESCRIPTION
        Remove-VergeTenantExternalIP removes a Virtual IP address assignment from a tenant.
        The IP address will be released back to the network pool.

    .PARAMETER ExternalIP
        An external IP object from Get-VergeTenantExternalIP. Accepts pipeline input.

    .PARAMETER TenantName
        The name of the tenant. Used with -IPAddress.

    .PARAMETER IPAddress
        The IP address to remove. Requires -TenantName.

    .PARAMETER Key
        The unique key (ID) of the external IP assignment to remove.

    .PARAMETER Force
        Skip confirmation prompts and remove without confirmation.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeTenantExternalIP -TenantName "Customer01" -IPAddress "10.0.0.100"

        Removes the external IP assignment after confirmation.

    .EXAMPLE
        Get-VergeTenantExternalIP -TenantName "Customer01" | Remove-VergeTenantExternalIP -Force

        Removes all external IPs from the tenant without confirmation.

    .EXAMPLE
        Remove-VergeTenantExternalIP -Key 42 -Force

        Removes the external IP assignment by key without confirmation.

    .OUTPUTS
        None.

    .NOTES
        Removing an external IP may disrupt connectivity for services using that IP.
        Firewall rules referencing the IP must be removed first.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByExternalIP')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByExternalIP')]
        [PSTypeName('Verge.TenantExternalIP')]
        [PSCustomObject]$ExternalIP,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByTenantIP')]
        [string]$TenantName,

        [Parameter(Mandatory, Position = 1, ParameterSetName = 'ByTenantIP')]
        [string]$IPAddress,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter()]
        [switch]$Force,

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
        # Resolve external IP based on parameter set
        $targetIPs = switch ($PSCmdlet.ParameterSetName) {
            'ByExternalIP' {
                $ExternalIP
            }
            'ByTenantIP' {
                Get-VergeTenantExternalIP -TenantName $TenantName -IPAddress $IPAddress -Server $Server
            }
            'ByKey' {
                # Query directly by key
                $queryParams = @{
                    filter = "`$key eq $Key"
                    fields = '$key,ip,vnet#name as network_name,owner'
                }
                $response = Invoke-VergeAPI -Method GET -Endpoint 'vnet_addresses' -Query $queryParams -Connection $Server
                if ($response) {
                    [PSCustomObject]@{
                        PSTypeName  = 'Verge.TenantExternalIP'
                        Key         = [int]$response.'$key'
                        IPAddress   = $response.ip
                        NetworkName = $response.network_name
                        _Connection = $Server
                    }
                }
                else {
                    Write-Error -Message "External IP with key $Key not found." -ErrorId 'ExternalIPNotFound'
                    return
                }
            }
        }

        foreach ($ip in $targetIPs) {
            if (-not $ip) {
                if ($PSCmdlet.ParameterSetName -eq 'ByTenantIP') {
                    Write-Error -Message "External IP '$IPAddress' not found for tenant '$TenantName'." -ErrorId 'ExternalIPNotFound'
                }
                continue
            }

            # Build description for confirmation
            $ipDesc = if ($ip.TenantName) {
                "$($ip.TenantName)/$($ip.IPAddress)"
            }
            else {
                $ip.IPAddress
            }

            # Confirm action
            if ($Force) {
                $shouldContinue = $true
            }
            else {
                $shouldContinue = $PSCmdlet.ShouldProcess($ipDesc, "Remove External IP Assignment")
            }

            if ($shouldContinue) {
                try {
                    Write-Verbose "Removing external IP '$($ip.IPAddress)'"
                    $response = Invoke-VergeAPI -Method DELETE -Endpoint "vnet_addresses/$($ip.Key)" -Connection $Server

                    Write-Verbose "External IP '$($ip.IPAddress)' removed"
                }
                catch {
                    $errorMessage = $_.Exception.Message
                    if ($errorMessage -match 'referencing') {
                        Write-Error -Message "Cannot remove external IP '$($ip.IPAddress)': Firewall rules are referencing this IP. Remove the rules first." -ErrorId 'IPHasReferences'
                    }
                    else {
                        Write-Error -Message "Failed to remove external IP '$($ip.IPAddress)': $errorMessage" -ErrorId 'ExternalIPRemoveFailed'
                    }
                }
            }
        }
    }
}
