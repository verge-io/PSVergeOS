function New-VergeVMSnapshot {
    <#
    .SYNOPSIS
        Creates a snapshot of a VergeOS virtual machine.

    .DESCRIPTION
        New-VergeVMSnapshot creates a point-in-time snapshot of a VM that can be
        used to restore the VM to its current state. Snapshots can be quiesced
        (requires guest agent) for application-consistent backups.

    .PARAMETER VM
        A VM object from Get-VergeVM. Accepts pipeline input.

    .PARAMETER VMName
        The name of the VM to snapshot.

    .PARAMETER VMKey
        The key (ID) of the VM to snapshot.

    .PARAMETER Name
        The name for the snapshot. If not specified, a timestamp-based name is used.

    .PARAMETER Description
        An optional description for the snapshot.

    .PARAMETER Retention
        How long to keep the snapshot. Accepts timespan strings like '24h', '7d', '1w'.
        Default is 24 hours (86400 seconds). Use 'Never' for no expiration.

    .PARAMETER Quiesce
        Quiesce the VM's disks before taking the snapshot. This temporarily freezes
        disk activity for a consistent snapshot. Requires the QEMU Guest Agent.

    .PARAMETER PassThru
        Return the created snapshot object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeVMSnapshot -VMName "WebServer01"

        Creates a snapshot with default 24-hour retention.

    .EXAMPLE
        New-VergeVMSnapshot -VMName "WebServer01" -Name "Pre-Update" -Retention "7d"

        Creates a named snapshot that expires in 7 days.

    .EXAMPLE
        New-VergeVMSnapshot -VMName "Database01" -Quiesce -Retention "Never"

        Creates a quiesced snapshot that never expires.

    .EXAMPLE
        Get-VergeVM -Name "Prod-*" | New-VergeVMSnapshot -Name "Maintenance-$(Get-Date -Format 'yyyyMMdd')"

        Creates snapshots for all production VMs with a dated name.

    .OUTPUTS
        None by default. Verge.VMSnapshot when -PassThru is specified.

    .NOTES
        Quiesced snapshots require the QEMU Guest Agent to be installed and running.
        The VM must not be a snapshot itself.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByVMName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByVMObject')]
        [PSTypeName('Verge.VM')]
        [PSCustomObject]$VM,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByVMName')]
        [string]$VMName,

        [Parameter(Mandatory, ParameterSetName = 'ByVMKey')]
        [int]$VMKey,

        [Parameter()]
        [ValidateLength(1, 128)]
        [string]$Name,

        [Parameter()]
        [ValidateLength(0, 2048)]
        [string]$Description,

        [Parameter()]
        [string]$Retention = '24h',

        [Parameter()]
        [switch]$Quiesce,

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
        # Resolve VM based on parameter set
        $targetVMs = switch ($PSCmdlet.ParameterSetName) {
            'ByVMName' {
                Get-VergeVM -Name $VMName -Server $Server
            }
            'ByVMKey' {
                Get-VergeVM -Key $VMKey -Server $Server
            }
            'ByVMObject' {
                $VM
            }
        }

        foreach ($targetVM in $targetVMs) {
            if (-not $targetVM) {
                continue
            }

            # Check if VM is a snapshot
            if ($targetVM.IsSnapshot) {
                Write-Error -Message "Cannot snapshot '$($targetVM.Name)': VM is already a snapshot" -ErrorId 'CannotSnapshotSnapshot'
                continue
            }

            # Parse retention to seconds
            $retentionSeconds = 86400  # Default 24 hours
            if ($Retention -eq 'Never' -or $Retention -eq '0') {
                $retentionSeconds = 0
            }
            elseif ($Retention -match '^(\d+)([smhdw])$') {
                $value = [int]$Matches[1]
                $unit = $Matches[2]
                $retentionSeconds = switch ($unit) {
                    's' { $value }
                    'm' { $value * 60 }
                    'h' { $value * 3600 }
                    'd' { $value * 86400 }
                    'w' { $value * 604800 }
                }
            }
            elseif ($Retention -match '^\d+$') {
                $retentionSeconds = [int]$Retention
            }
            else {
                Write-Error -Message "Invalid retention format '$Retention'. Use format like '24h', '7d', '1w', or 'Never'." -ErrorId 'InvalidRetention'
                continue
            }

            # Generate snapshot name if not provided
            $snapshotName = if ($Name) {
                $Name
            } else {
                "Snapshot-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            }

            # Calculate expiration timestamp (Unix epoch)
            # If retention is 0 (Never), set expires to 0 (no expiration)
            $expiresTimestamp = if ($retentionSeconds -eq 0) {
                0
            } else {
                [int][DateTimeOffset]::UtcNow.AddSeconds($retentionSeconds).ToUnixTimeSeconds()
            }

            # Build request body for machine_snapshots endpoint
            $body = @{
                machine          = $targetVM.MachineKey
                name             = $snapshotName
                created_manually = $true
                quiesce          = $Quiesce.IsPresent
            }

            # Only include expires if there's a retention period
            if ($expiresTimestamp -gt 0) {
                $body['expires'] = $expiresTimestamp
            }

            # Format retention for display
            $retentionDisplay = if ($retentionSeconds -eq 0) {
                'Never'
            } elseif ($retentionSeconds -ge 86400) {
                "$([math]::Round($retentionSeconds / 86400, 1)) days"
            } elseif ($retentionSeconds -ge 3600) {
                "$([math]::Round($retentionSeconds / 3600, 1)) hours"
            } else {
                "$retentionSeconds seconds"
            }

            $quiesceText = if ($Quiesce) { ', quiesced' } else { '' }

            if ($PSCmdlet.ShouldProcess($targetVM.Name, "Create snapshot '$snapshotName' (retention: $retentionDisplay$quiesceText)")) {
                try {
                    Write-Verbose "Creating snapshot '$snapshotName' for VM '$($targetVM.Name)'"
                    $response = Invoke-VergeAPI -Method POST -Endpoint 'machine_snapshots' -Body $body -Connection $Server

                    Write-Verbose "Snapshot '$snapshotName' created for VM '$($targetVM.Name)'"

                    if ($PassThru) {
                        # Wait for snapshot to be created and return it
                        Start-Sleep -Seconds 2
                        Get-VergeVMSnapshot -VMKey $targetVM.Key -Server $Server |
                            Sort-Object Created -Descending |
                            Select-Object -First 1
                    }
                }
                catch {
                    Write-Error -Message "Failed to create snapshot for VM '$($targetVM.Name)': $($_.Exception.Message)" -ErrorId 'SnapshotFailed'
                }
            }
        }
    }
}
