function New-VergeSnapshotProfile {
    <#
    .SYNOPSIS
        Creates a new snapshot profile in VergeOS.

    .DESCRIPTION
        New-VergeSnapshotProfile creates a new snapshot profile that defines automated
        snapshot schedules for VMs, volumes, and cloud snapshots.

        After creating the profile, use New-VergeSnapshotProfilePeriod to add schedule
        periods to the profile.

    .PARAMETER Name
        The name of the snapshot profile. Must be unique.

    .PARAMETER Description
        Optional description of the snapshot profile.

    .PARAMETER IgnoreWarnings
        If specified, ignores warnings about snapshot count estimates.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeSnapshotProfile -Name "Daily Backups"

        Creates a new snapshot profile named "Daily Backups".

    .EXAMPLE
        New-VergeSnapshotProfile -Name "Production VMs" -Description "Snapshot profile for production workloads"

        Creates a new snapshot profile with a description.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.SnapshotProfile'

    .NOTES
        After creating a profile, add schedule periods using New-VergeSnapshotProfilePeriod.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [ValidateLength(1, 128)]
        [string]$Name,

        [Parameter()]
        [ValidateLength(0, 2048)]
        [string]$Description,

        [Parameter()]
        [switch]$IgnoreWarnings,

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
        if ($PSCmdlet.ShouldProcess("Snapshot Profile '$Name'", 'Create')) {
            # Build request body
            $body = @{
                name = $Name
            }

            if ($PSBoundParameters.ContainsKey('Description')) {
                $body['description'] = $Description
            }

            if ($IgnoreWarnings) {
                $body['ignore_warnings'] = $true
            }

            try {
                Write-Verbose "Creating snapshot profile '$Name'"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'snapshot_profiles' -Body $body -Connection $Server

                # Get the created profile
                if ($response -and $response.'$key') {
                    $newKey = $response.'$key'
                    Write-Verbose "Snapshot profile created with key: $newKey"

                    # Retrieve and return the full profile
                    Get-VergeSnapshotProfile -Key $newKey -Server $Server
                }
                else {
                    Write-Error -Message "Failed to create snapshot profile: No key returned" -ErrorId 'CreateSnapshotProfileFailed'
                }
            }
            catch {
                Write-Error -Message "Failed to create snapshot profile '$Name': $($_.Exception.Message)" -ErrorId 'CreateSnapshotProfileFailed'
            }
        }
    }
}
