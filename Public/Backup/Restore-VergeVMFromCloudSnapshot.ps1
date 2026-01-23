function Restore-VergeVMFromCloudSnapshot {
    <#
    .SYNOPSIS
        Restores a VM from a cloud (system) snapshot in VergeOS.

    .DESCRIPTION
        Restore-VergeVMFromCloudSnapshot recovers a VM from a cloud snapshot.
        This creates a new VM from the snapshot data, it does not overwrite
        any existing VM.

        Use Get-VergeCloudSnapshot -IncludeVMs to see available VMs in a snapshot.

    .PARAMETER CloudSnapshot
        A cloud snapshot object from Get-VergeCloudSnapshot. Accepts pipeline input.

    .PARAMETER CloudSnapshotKey
        The key (ID) of the cloud snapshot containing the VM.

    .PARAMETER CloudSnapshotName
        The name of the cloud snapshot containing the VM.

    .PARAMETER VMName
        The name of the VM within the cloud snapshot to restore.

    .PARAMETER VMKey
        The key of the VM within the cloud snapshot (from cloud_snapshot_vms).

    .PARAMETER NewName
        Optional new name for the restored VM. If not specified, the original name
        is used (which may conflict with an existing VM).

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Restore-VergeVMFromCloudSnapshot -CloudSnapshotName "Daily_20260123" -VMName "WebServer01"

        Restores the VM "WebServer01" from the specified cloud snapshot.

    .EXAMPLE
        Get-VergeCloudSnapshot -Name "Daily*" | Restore-VergeVMFromCloudSnapshot -VMName "DBServer" -NewName "DBServer-Restored"

        Restores the VM with a new name from the first matching cloud snapshot.

    .EXAMPLE
        $snap = Get-VergeCloudSnapshot -Key 5 -IncludeVMs
        $snap.VMs | ForEach-Object { Restore-VergeVMFromCloudSnapshot -CloudSnapshotKey 5 -VMKey $_.Key }

        Restores all VMs from a specific cloud snapshot.

    .OUTPUTS
        PSCustomObject with recovery status information.

    .NOTES
        The recovered VM will be created as a new VM. If a VM with the same name
        already exists, you should specify -NewName to avoid conflicts.

        This operation may take time depending on VM size.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'BySnapshotName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [PSTypeName('Verge.CloudSnapshot')]
        [PSCustomObject]$CloudSnapshot,

        [Parameter(Mandatory, ParameterSetName = 'BySnapshotKey')]
        [int]$CloudSnapshotKey,

        [Parameter(Mandatory, ParameterSetName = 'BySnapshotName')]
        [string]$CloudSnapshotName,

        [Parameter(ParameterSetName = 'ByObject')]
        [Parameter(ParameterSetName = 'BySnapshotKey')]
        [Parameter(ParameterSetName = 'BySnapshotName')]
        [string]$VMName,

        [Parameter()]
        [int]$VMKey,

        [Parameter()]
        [string]$NewName,

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
        # Resolve the cloud snapshot
        $targetSnapshot = switch ($PSCmdlet.ParameterSetName) {
            'ByObject' { $CloudSnapshot }
            'BySnapshotKey' { Get-VergeCloudSnapshot -Key $CloudSnapshotKey -IncludeExpired -Server $Server }
            'BySnapshotName' { Get-VergeCloudSnapshot -Name $CloudSnapshotName -IncludeExpired -Server $Server | Select-Object -First 1 }
        }

        if (-not $targetSnapshot) {
            $identifier = if ($CloudSnapshotKey) { "Key: $CloudSnapshotKey" } else { "Name: $CloudSnapshotName" }
            Write-Error -Message "Cloud snapshot not found ($identifier)" -ErrorId 'CloudSnapshotNotFound'
            return
        }

        $snapshotKey = $targetSnapshot.Key
        $snapshotName = $targetSnapshot.Name

        # Find the VM within the snapshot
        if (-not $VMKey -and -not $VMName) {
            Write-Error -Message "Either -VMName or -VMKey must be specified" -ErrorId 'VMNotSpecified'
            return
        }

        # Query cloud_snapshot_vms to find the VM
        $vmParams = @{
            'fields' = @(
                '$key'
                'name'
                'description'
                'original_key'
                'status'
            ) -join ','
            'filter' = "cloud_snapshot eq $snapshotKey"
        }

        if ($VMKey) {
            $vmParams['filter'] += " and `$key eq $VMKey"
        }
        elseif ($VMName) {
            $vmParams['filter'] += " and name eq '$VMName'"
        }

        try {
            $vmResponse = Invoke-VergeAPI -Method GET -Endpoint 'cloud_snapshot_vms' -Query $vmParams -Connection $Server
            $snapshotVMs = if ($vmResponse -is [array]) { $vmResponse } elseif ($vmResponse) { @($vmResponse) } else { @() }

            if ($snapshotVMs.Count -eq 0) {
                $vmIdentifier = if ($VMKey) { "Key: $VMKey" } else { "Name: $VMName" }
                Write-Error -Message "VM not found in cloud snapshot '$snapshotName' ($vmIdentifier)" -ErrorId 'VMNotFoundInSnapshot'
                return
            }

            foreach ($vm in $snapshotVMs) {
                $vmDisplayName = $vm.name
                $vmSnapshotKey = $vm.'$key'

                $restoreName = if ($NewName) { $NewName } else { $vmDisplayName }

                if ($PSCmdlet.ShouldProcess("VM '$vmDisplayName' from Cloud Snapshot '$snapshotName'", 'Restore')) {
                    Write-Verbose "Restoring VM '$vmDisplayName' from cloud snapshot '$snapshotName' (VM Snapshot Key: $vmSnapshotKey)"

                    # Build the recover action
                    $body = @{
                        action = 'recover'
                        params = @{
                            rows = @($vmSnapshotKey)
                        }
                    }

                    if ($NewName) {
                        $body['params']['name'] = $NewName
                    }

                    try {
                        $response = Invoke-VergeAPI -Method POST -Endpoint 'cloud_snapshot_vm_actions' -Body $body -Connection $Server

                        # Create output object
                        $output = [PSCustomObject]@{
                            PSTypeName          = 'Verge.CloudSnapshotVMRestore'
                            CloudSnapshotKey    = $snapshotKey
                            CloudSnapshotName   = $snapshotName
                            VMSnapshotKey       = $vmSnapshotKey
                            VMName              = $vmDisplayName
                            RestoredAs          = $restoreName
                            Status              = 'Initiated'
                            Response            = $response
                        }

                        if ($response -and $response.task) {
                            $output | Add-Member -MemberType NoteProperty -Name 'TaskKey' -Value $response.task -Force
                        }

                        Write-Output $output
                        Write-Verbose "VM restore initiated for '$vmDisplayName'"
                    }
                    catch {
                        Write-Error -Message "Failed to restore VM '$vmDisplayName' from cloud snapshot: $($_.Exception.Message)" -ErrorId 'RestoreVMFailed'
                    }
                }
            }
        }
        catch {
            Write-Error -Message "Failed to query VMs in cloud snapshot '$snapshotName': $($_.Exception.Message)" -ErrorId 'QuerySnapshotVMsFailed'
        }
    }
}
