function Remove-VergeNASVolume {
    <#
    .SYNOPSIS
        Removes a NAS volume from VergeOS.

    .DESCRIPTION
        Remove-VergeNASVolume deletes a NAS volume from the VergeOS system.
        This operation is destructive and cannot be undone. All data on
        the volume will be permanently deleted.

    .PARAMETER Name
        The name of the volume to remove.

    .PARAMETER Key
        The unique key (ID) of the volume to remove.

    .PARAMETER Volume
        A volume object from Get-VergeNASVolume.

    .PARAMETER Force
        Bypasses the confirmation prompt.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeNASVolume -Name "TempData"

        Removes the TempData volume after confirmation.

    .EXAMPLE
        Remove-VergeNASVolume -Name "TempData" -Force

        Removes the TempData volume without confirmation.

    .EXAMPLE
        Get-VergeNASVolume -Name "Test-*" | Remove-VergeNASVolume -Force

        Removes all volumes starting with "Test-" without confirmation.

    .NOTES
        The volume must not have any active shares or be mounted by any
        processes before it can be removed. Ensure all CIFS/NFS shares
        are removed first.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [string]$Key,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [PSTypeName('Verge.NASVolume')]
        [PSCustomObject]$Volume,

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
        try {
            # Resolve volume to key
            $volumeKey = $null
            $volumeName = $null

            switch ($PSCmdlet.ParameterSetName) {
                'ByKey' {
                    $volumeKey = $Key
                }
                'ByName' {
                    $volumeName = $Name
                    $existingVolume = Get-VergeNASVolume -Name $Name -Server $Server
                    if (-not $existingVolume) {
                        throw "Volume '$Name' not found"
                    }
                    $volumeKey = $existingVolume.Key
                    $volumeName = $existingVolume.Name
                }
                'ByObject' {
                    $volumeKey = $Volume.Key
                    $volumeName = $Volume.Name
                }
            }

            if (-not $volumeKey) {
                throw "Could not resolve volume key"
            }

            $displayName = $volumeName ?? $volumeKey
            $shouldProcess = $Force -or $PSCmdlet.ShouldProcess(
                "Volume '$displayName'",
                'Remove (this will permanently delete all data)'
            )

            if ($shouldProcess) {
                Write-Verbose "Removing volume '$displayName' (key: $volumeKey)"
                $null = Invoke-VergeAPI -Method DELETE -Endpoint "volumes/$volumeKey" -Connection $Server
                Write-Verbose "Volume '$displayName' removed successfully"
            }
        }
        catch {
            $displayName = $volumeName ?? $volumeKey ?? 'unknown'
            Write-Error -Message "Failed to remove volume '$displayName': $($_.Exception.Message)" -ErrorId 'RemoveVolumeFailed'
        }
    }
}
