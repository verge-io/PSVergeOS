function Set-VergeTenantLayer2Network {
    <#
    .SYNOPSIS
        Modifies a Layer 2 network assignment for a VergeOS tenant.

    .DESCRIPTION
        Set-VergeTenantLayer2Network modifies an existing Layer 2 network
        assignment, allowing you to enable or disable the network connection.

    .PARAMETER Layer2Network
        A Layer 2 network object from Get-VergeTenantLayer2Network. Accepts pipeline input.

    .PARAMETER Key
        The unique key (ID) of the Layer 2 network assignment to modify.

    .PARAMETER Enabled
        Enable or disable the Layer 2 network connection.

    .PARAMETER PassThru
        Return the modified Layer 2 network assignment object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Set-VergeTenantLayer2Network -Key 42 -Enabled $false

        Disables the Layer 2 network assignment.

    .EXAMPLE
        Get-VergeTenantLayer2Network -TenantName "Customer01" | Set-VergeTenantLayer2Network -Enabled $true

        Enables all Layer 2 networks for the tenant.

    .EXAMPLE
        Get-VergeTenantLayer2Network -Key 42 | Set-VergeTenantLayer2Network -Enabled $false -PassThru

        Disables the network and returns the updated object.

    .OUTPUTS
        None by default. Verge.TenantLayer2Network when -PassThru is specified.

    .NOTES
        Only the Enabled property can be modified. To change the network
        assignment, remove and recreate the Layer 2 network assignment.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByKey')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [PSTypeName('Verge.TenantLayer2Network')]
        [PSCustomObject]$Layer2Network,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(Mandatory)]
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
        # Resolve Layer 2 network based on parameter set
        $targetKey = switch ($PSCmdlet.ParameterSetName) {
            'ByKey' { $Key }
            'ByObject' { $Layer2Network.Key }
        }

        $targetDesc = if ($Layer2Network) {
            "$($Layer2Network.TenantName)/$($Layer2Network.NetworkName)"
        }
        else {
            "Key $targetKey"
        }

        # Confirm action
        $action = if ($Enabled) { "Enable" } else { "Disable" }
        if ($PSCmdlet.ShouldProcess($targetDesc, "$action Layer 2 network")) {
            try {
                Write-Verbose "$action Layer 2 network '$targetDesc'"

                $body = @{
                    enabled = $Enabled
                }

                $response = Invoke-VergeAPI -Method PUT -Endpoint "tenant_layer2_vnets/$targetKey" -Body $body -Connection $Server

                Write-Verbose "Layer 2 network '$targetDesc' updated"

                if ($PassThru) {
                    Get-VergeTenantLayer2Network -Key $targetKey -Server $Server
                }
            }
            catch {
                Write-Error -Message "Failed to modify Layer 2 network '$targetDesc': $($_.Exception.Message)" -ErrorId 'Layer2NetworkModifyFailed'
            }
        }
    }
}
