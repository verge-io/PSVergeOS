function Remove-VergeNIC {
    <#
    .SYNOPSIS
        Removes a network interface from a VergeOS virtual machine.

    .DESCRIPTION
        Remove-VergeNIC permanently removes a virtual NIC from a VM.
        This will disconnect the VM from the associated network.

    .PARAMETER NIC
        A NIC object from Get-VergeNIC. Accepts pipeline input.

    .PARAMETER Key
        The key (ID) of the NIC to remove.

    .PARAMETER VMName
        The name of the VM that owns the NIC. Use with -Name.

    .PARAMETER VMKey
        The key (ID) of the VM that owns the NIC. Use with -Name.

    .PARAMETER Name
        The name of the NIC to remove. Use with -VMName or -VMKey.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeNIC -VMName "WebServer01" -Name "nic_1"

        Removes the NIC named "nic_1" from the specified VM.

    .EXAMPLE
        Get-VergeNIC -VMName "WebServer01" | Where-Object { -not $_.Enabled } | Remove-VergeNIC

        Removes all disabled NICs from the VM.

    .EXAMPLE
        Remove-VergeNIC -Key 123 -Confirm:$false

        Removes a NIC by its key without confirmation.

    .OUTPUTS
        None.

    .NOTES
        Removing a NIC will disconnect the VM from the associated network.
        The VM should typically be powered off before removing NICs.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByNIC')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByNIC')]
        [PSTypeName('Verge.NIC')]
        [PSCustomObject]$NIC,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(Mandatory, ParameterSetName = 'ByVMAndName')]
        [string]$VMName,

        [Parameter(Mandatory, ParameterSetName = 'ByVMKeyAndName')]
        [int]$VMKey,

        [Parameter(Mandatory, ParameterSetName = 'ByVMAndName')]
        [Parameter(Mandatory, ParameterSetName = 'ByVMKeyAndName')]
        [string]$Name,

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
        # Resolve NIC based on parameter set
        $nicsToRemove = switch ($PSCmdlet.ParameterSetName) {
            'ByNIC' {
                $NIC
            }
            'ByKey' {
                # Create minimal NIC object
                try {
                    $response = Invoke-VergeAPI -Method GET -Endpoint "machine_nics/$Key" -Connection $Server
                    if ($response) {
                        [PSCustomObject]@{
                            Key     = $Key
                            Name    = $response.name
                            VMName  = 'Unknown'
                        }
                    }
                }
                catch {
                    Write-Error -Message "NIC with key $Key not found" -ErrorId 'NICNotFound'
                    return
                }
            }
            'ByVMAndName' {
                Get-VergeNIC -VMName $VMName -Name $Name -Server $Server
            }
            'ByVMKeyAndName' {
                Get-VergeNIC -VMKey $VMKey -Name $Name -Server $Server
            }
        }

        foreach ($targetNIC in $nicsToRemove) {
            if (-not $targetNIC) {
                continue
            }

            $nicKey = $targetNIC.Key
            $nicName = $targetNIC.Name
            $vmName = if ($targetNIC.VMName) { $targetNIC.VMName } else { 'Unknown' }
            $macInfo = if ($targetNIC.MACAddress) { " ($($targetNIC.MACAddress))" } else { '' }

            if ($PSCmdlet.ShouldProcess("$nicName$macInfo (VM: $vmName)", 'Remove NIC')) {
                try {
                    Write-Verbose "Removing NIC '$nicName' (Key: $nicKey) from VM '$vmName'"
                    Invoke-VergeAPI -Method DELETE -Endpoint "machine_nics/$nicKey" -Connection $Server | Out-Null
                    Write-Verbose "NIC '$nicName' removed successfully"
                }
                catch {
                    Write-Error -Message "Failed to remove NIC '$nicName': $($_.Exception.Message)" -ErrorId 'NICRemoveFailed'
                }
            }
        }
    }
}
