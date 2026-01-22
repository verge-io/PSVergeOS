function Remove-VergeDrive {
    <#
    .SYNOPSIS
        Removes a drive from a VergeOS virtual machine.

    .DESCRIPTION
        Remove-VergeDrive permanently removes a virtual drive from a VM.
        This operation cannot be undone and all data on the drive will be lost.

    .PARAMETER Drive
        A drive object from Get-VergeDrive. Accepts pipeline input.

    .PARAMETER Key
        The key (ID) of the drive to remove.

    .PARAMETER VMName
        The name of the VM that owns the drive. Use with -Name.

    .PARAMETER VMKey
        The key (ID) of the VM that owns the drive. Use with -Name.

    .PARAMETER Name
        The name of the drive to remove. Use with -VMName or -VMKey.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeDrive -VMName "WebServer01" -Name "DataDisk"

        Removes the drive named "DataDisk" from the specified VM.

    .EXAMPLE
        Get-VergeDrive -VMName "WebServer01" | Where-Object { $_.SizeGB -lt 10 } | Remove-VergeDrive

        Removes all drives smaller than 10GB from the VM.

    .EXAMPLE
        Remove-VergeDrive -Key 123 -Confirm:$false

        Removes a drive by its key without confirmation.

    .OUTPUTS
        None.

    .NOTES
        WARNING: This is a destructive operation that cannot be undone.
        All data on the drive will be permanently lost.
        The VM should typically be powered off before removing drives.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByDrive')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByDrive')]
        [PSTypeName('Verge.Drive')]
        [PSCustomObject]$Drive,

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
        # Resolve drive based on parameter set
        $drivesToRemove = switch ($PSCmdlet.ParameterSetName) {
            'ByDrive' {
                $Drive
            }
            'ByKey' {
                # Create minimal drive object
                try {
                    $response = Invoke-VergeAPI -Method GET -Endpoint "machine_drives/$Key" -Connection $Server
                    if ($response) {
                        [PSCustomObject]@{
                            Key     = $Key
                            Name    = $response.name
                            VMName  = 'Unknown'
                        }
                    }
                }
                catch {
                    Write-Error -Message "Drive with key $Key not found" -ErrorId 'DriveNotFound'
                    return
                }
            }
            'ByVMAndName' {
                Get-VergeDrive -VMName $VMName -Name $Name -Server $Server
            }
            'ByVMKeyAndName' {
                Get-VergeDrive -VMKey $VMKey -Name $Name -Server $Server
            }
        }

        foreach ($targetDrive in $drivesToRemove) {
            if (-not $targetDrive) {
                continue
            }

            $driveKey = $targetDrive.Key
            $driveName = $targetDrive.Name
            $vmName = if ($targetDrive.VMName) { $targetDrive.VMName } else { 'Unknown' }
            $sizeInfo = if ($targetDrive.SizeGB) { " (${($targetDrive.SizeGB)}GB)" } else { '' }

            if ($PSCmdlet.ShouldProcess("$driveName$sizeInfo (VM: $vmName)", 'Remove drive')) {
                try {
                    Write-Verbose "Removing drive '$driveName' (Key: $driveKey) from VM '$vmName'"
                    Invoke-VergeAPI -Method DELETE -Endpoint "machine_drives/$driveKey" -Connection $Server | Out-Null
                    Write-Verbose "Drive '$driveName' removed successfully"
                }
                catch {
                    Write-Error -Message "Failed to remove drive '$driveName': $($_.Exception.Message)" -ErrorId 'DriveRemoveFailed'
                }
            }
        }
    }
}
