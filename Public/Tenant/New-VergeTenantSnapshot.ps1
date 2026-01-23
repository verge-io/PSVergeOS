function New-VergeTenantSnapshot {
    <#
    .SYNOPSIS
        Creates a snapshot of a VergeOS tenant.

    .DESCRIPTION
        New-VergeTenantSnapshot creates a point-in-time snapshot of a tenant.
        Snapshots can be used for backup/recovery or to create tenant clones.
        The tenant does not need to be powered off to create a snapshot.

    .PARAMETER Tenant
        A tenant object from Get-VergeTenant. Accepts pipeline input.

    .PARAMETER TenantName
        The name of the tenant to snapshot.

    .PARAMETER TenantKey
        The unique key (ID) of the tenant to snapshot.

    .PARAMETER Name
        The name for the snapshot. Must be unique within the tenant.

    .PARAMETER Description
        An optional description for the snapshot.

    .PARAMETER ExpiresIn
        The number of days until the snapshot expires. Use 0 for no expiration.
        Default is 0 (no expiration).

    .PARAMETER ExpiresAt
        A specific date/time when the snapshot should expire.

    .PARAMETER PassThru
        Return the created snapshot object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeTenantSnapshot -TenantName "Customer01" -Name "Pre-Upgrade"

        Creates a snapshot named "Pre-Upgrade" for the tenant.

    .EXAMPLE
        Get-VergeTenant -Name "Customer01" | New-VergeTenantSnapshot -Name "Daily-Backup" -ExpiresIn 7

        Creates a snapshot that expires in 7 days using pipeline input.

    .EXAMPLE
        New-VergeTenantSnapshot -TenantName "Customer01" -Name "Quarterly" -Description "Q1 2026 backup" -PassThru

        Creates a snapshot with a description and returns the snapshot object.

    .OUTPUTS
        None by default. Verge.TenantSnapshot when -PassThru is specified.

    .NOTES
        Snapshots are created instantly using copy-on-write technology.
        The tenant continues running normally during snapshot creation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByTenantName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByTenant')]
        [PSTypeName('Verge.Tenant')]
        [PSCustomObject]$Tenant,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByTenantName')]
        [string]$TenantName,

        [Parameter(Mandatory, ParameterSetName = 'ByTenantKey')]
        [int]$TenantKey,

        [Parameter(Mandatory, Position = 1)]
        [ValidateLength(1, 128)]
        [string]$Name,

        [Parameter()]
        [ValidateLength(0, 2048)]
        [string]$Description,

        [Parameter()]
        [ValidateRange(0, 3650)]
        [int]$ExpiresIn = 0,

        [Parameter()]
        [datetime]$ExpiresAt,

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
        # Resolve tenant based on parameter set
        $targetTenant = switch ($PSCmdlet.ParameterSetName) {
            'ByTenantName' {
                Get-VergeTenant -Name $TenantName -Server $Server
            }
            'ByTenantKey' {
                Get-VergeTenant -Key $TenantKey -Server $Server
            }
            'ByTenant' {
                $Tenant
            }
        }

        foreach ($t in $targetTenant) {
            if (-not $t) {
                continue
            }

            # Check if tenant is a snapshot (cannot snapshot a snapshot)
            if ($t.IsSnapshot) {
                Write-Error -Message "Cannot create snapshot of tenant '$($t.Name)': Source is already a snapshot." -ErrorId 'CannotSnapshotSnapshot'
                continue
            }

            # Build request body
            $body = @{
                tenant = $t.Key
                name   = $Name
            }

            # Add optional description
            if ($Description) {
                $body['description'] = $Description
            }

            # Calculate expiration timestamp
            if ($PSBoundParameters.ContainsKey('ExpiresAt')) {
                $body['expires'] = [int][DateTimeOffset]::new($ExpiresAt).ToUnixTimeSeconds()
            }
            elseif ($ExpiresIn -gt 0) {
                $expiresDate = (Get-Date).AddDays($ExpiresIn)
                $body['expires'] = [int][DateTimeOffset]::new($expiresDate).ToUnixTimeSeconds()
            }

            # Confirm action
            if ($PSCmdlet.ShouldProcess("$($t.Name)", "Create Tenant Snapshot '$Name'")) {
                try {
                    Write-Verbose "Creating snapshot '$Name' for tenant '$($t.Name)'"
                    $response = Invoke-VergeAPI -Method POST -Endpoint 'tenant_snapshots' -Body $body -Connection $Server

                    Write-Verbose "Snapshot '$Name' created for tenant '$($t.Name)'"

                    if ($PassThru) {
                        # Wait briefly for the snapshot to be available
                        Start-Sleep -Milliseconds 500

                        # Find the new snapshot by name
                        Get-VergeTenantSnapshot -TenantKey $t.Key -Name $Name -Server $Server
                    }
                }
                catch {
                    $errorMessage = $_.Exception.Message
                    if ($errorMessage -match 'already exists') {
                        throw "A snapshot named '$Name' already exists for tenant '$($t.Name)'."
                    }
                    Write-Error -Message "Failed to create snapshot for tenant '$($t.Name)': $errorMessage" -ErrorId 'TenantSnapshotCreateFailed'
                }
            }
        }
    }
}
