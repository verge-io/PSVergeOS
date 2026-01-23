function Get-VergeSharedObject {
    <#
    .SYNOPSIS
        Retrieves shared objects (VMs shared with tenants) from VergeOS.

    .DESCRIPTION
        Get-VergeSharedObject retrieves VMs that have been shared with tenants.
        Shared objects allow parent systems to provide VMs to tenants that can
        be imported and used within the tenant environment.

    .PARAMETER Tenant
        A tenant object from Get-VergeTenant. Accepts pipeline input.

    .PARAMETER TenantName
        The name of the tenant to get shared objects for.

    .PARAMETER TenantKey
        The unique key (ID) of the tenant to get shared objects for.

    .PARAMETER Name
        Filter by shared object name. Supports wildcards (* and ?).

    .PARAMETER Inbox
        If specified, only return inbox items (shared objects waiting to be imported).

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeSharedObject -TenantName "Customer01"

        Gets all shared objects for the tenant.

    .EXAMPLE
        Get-VergeTenant -Name "Customer01" | Get-VergeSharedObject

        Gets shared objects using pipeline input.

    .EXAMPLE
        Get-VergeSharedObject -TenantName "Customer01" -Name "Template*"

        Gets shared objects with names starting with "Template".

    .EXAMPLE
        Get-VergeSharedObject -TenantName "Customer01" -Inbox

        Gets only inbox items (pending imports) for the tenant.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.SharedObject'

    .NOTES
        Shared objects are created by the parent system and can be imported
        by tenants to create their own copies of VMs.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByTenantName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByTenant')]
        [PSTypeName('Verge.Tenant')]
        [PSCustomObject]$Tenant,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByTenantName')]
        [string]$TenantName,

        [Parameter(Mandatory, ParameterSetName = 'ByTenantKey')]
        [int]$TenantKey,

        [Parameter()]
        [SupportsWildcards()]
        [string]$Name,

        [Parameter()]
        [switch]$Inbox,

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

            # Build query parameters
            $queryParams = @{}

            # Build filter
            $filters = [System.Collections.Generic.List[string]]::new()
            $filters.Add("recipient eq $($t.Key)")

            if ($Inbox) {
                $filters.Add("inbox eq true")
            }

            $queryParams['filter'] = $filters -join ' and '

            # Request fields
            $queryParams['fields'] = @(
                '$key'
                'recipient'
                'type'
                'name'
                'description'
                'created'
                'inbox'
                'snapshot'
                'id'
            ) -join ','

            try {
                Write-Verbose "Querying shared objects for tenant '$($t.Name)' from $($Server.Server)"
                $response = Invoke-VergeAPI -Method GET -Endpoint 'shared_objects' -Query $queryParams -Connection $Server

                # Handle both single object and array responses
                $objects = if ($response -is [array]) { $response } else { @($response) }

                # Filter by name if specified
                if ($Name) {
                    if ($Name -match '[\\*\\?]') {
                        $objects = $objects | Where-Object { $_.name -like $Name }
                    }
                    else {
                        $objects = $objects | Where-Object { $_.name -eq $Name }
                    }
                }

                foreach ($obj in $objects) {
                    # Skip null entries
                    if (-not $obj -or -not $obj.name) {
                        continue
                    }

                    # Parse snapshot path to extract key (format: "machine_snapshots/14")
                    $snapshotKey = $null
                    if ($obj.snapshot) {
                        if ($obj.snapshot -match '/(\d+)$') {
                            $snapshotKey = [int]$Matches[1]
                        }
                    }

                    # Create output object
                    $output = [PSCustomObject]@{
                        PSTypeName   = 'Verge.SharedObject'
                        Key          = [int]$obj.'$key'
                        TenantKey    = $t.Key
                        TenantName   = $t.Name
                        Name         = $obj.name
                        Type         = $obj.type
                        Description  = $obj.description
                        IsInbox      = [bool]$obj.inbox
                        Snapshot     = $obj.snapshot
                        SnapshotKey  = $snapshotKey
                        ObjectId     = $obj.id
                        Created      = if ($obj.created) { [DateTimeOffset]::FromUnixTimeSeconds($obj.created).LocalDateTime } else { $null }
                    }

                    # Add hidden properties for pipeline support
                    $output | Add-Member -MemberType NoteProperty -Name '_Connection' -Value $Server -Force

                    Write-Output $output
                }
            }
            catch {
                Write-Error -Message "Failed to get shared objects for tenant '$($t.Name)': $($_.Exception.Message)" -ErrorId 'SharedObjectQueryFailed'
            }
        }
    }
}
