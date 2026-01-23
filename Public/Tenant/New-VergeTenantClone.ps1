function New-VergeTenantClone {
    <#
    .SYNOPSIS
        Creates a clone of an existing VergeOS tenant.

    .DESCRIPTION
        New-VergeTenantClone creates a new tenant that is a copy of an existing tenant.
        The clone includes all configuration, VMs, networks, and storage by default.
        You can optionally exclude certain components from the clone.

    .PARAMETER SourceTenant
        A tenant object from Get-VergeTenant to clone. Accepts pipeline input.

    .PARAMETER SourceName
        The name of the tenant to clone.

    .PARAMETER SourceKey
        The unique key (ID) of the tenant to clone.

    .PARAMETER Name
        The name for the new cloned tenant. If not specified, a default name
        like "Clone of SourceName XXXXX" will be generated.

    .PARAMETER NoNetwork
        Do not clone the network configuration.

    .PARAMETER NoStorage
        Do not clone the storage configuration.

    .PARAMETER NoNodes
        Do not clone the nodes (VMs).

    .PARAMETER PassThru
        Return the cloned tenant object after creation.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeTenantClone -SourceName "Customer01" -Name "Customer01-Test"

        Creates a clone of "Customer01" named "Customer01-Test".

    .EXAMPLE
        Get-VergeTenant -Name "Template" | New-VergeTenantClone -Name "NewCustomer"

        Clones the "Template" tenant to create "NewCustomer".

    .EXAMPLE
        New-VergeTenantClone -SourceName "Customer01" -Name "NetworkTest" -NoStorage -NoNodes

        Creates a clone with only the network configuration (no storage or VMs).

    .EXAMPLE
        New-VergeTenantClone -SourceName "Customer01" -PassThru

        Creates a clone with default naming and returns the tenant object.

    .OUTPUTS
        None by default. Verge.Tenant when -PassThru is specified.

    .NOTES
        Cloning can take time depending on the size of the tenant.
        The source tenant does not need to be powered off for cloning.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'BySourceName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'BySourceTenant')]
        [PSTypeName('Verge.Tenant')]
        [PSCustomObject]$SourceTenant,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'BySourceName')]
        [string]$SourceName,

        [Parameter(Mandatory, ParameterSetName = 'BySourceKey')]
        [int]$SourceKey,

        [Parameter(Position = 1)]
        [ValidateLength(1, 120)]
        [string]$Name,

        [Parameter()]
        [switch]$NoNetwork,

        [Parameter()]
        [switch]$NoStorage,

        [Parameter()]
        [switch]$NoNodes,

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
        # Resolve source tenant based on parameter set
        $sourceTarget = switch ($PSCmdlet.ParameterSetName) {
            'BySourceName' {
                Get-VergeTenant -Name $SourceName -Server $Server
            }
            'BySourceKey' {
                Get-VergeTenant -Key $SourceKey -Server $Server
            }
            'BySourceTenant' {
                $SourceTenant
            }
        }

        foreach ($source in $sourceTarget) {
            if (-not $source) {
                continue
            }

            # Check if source tenant is a snapshot
            if ($source.IsSnapshot) {
                Write-Error -Message "Cannot clone tenant '$($source.Name)': Source is a snapshot. Use tenant restore instead." -ErrorId 'CannotCloneSnapshot'
                continue
            }

            # Determine clone name
            $cloneName = if ($Name) { $Name } else { "Clone of $($source.Name) $(Get-Random -Maximum 99999)" }

            # Build action body
            $body = @{
                tenant = $source.Key
                action = 'clone'
                params = @{
                    name = $cloneName
                }
            }

            # Add exclusion options
            if ($NoNetwork) {
                $body['params']['no_vnet'] = $true
            }

            if ($NoStorage) {
                $body['params']['no_storage'] = $true
            }

            if ($NoNodes) {
                $body['params']['no_nodes'] = $true
            }

            # Build description of what's being cloned
            $excludeList = @()
            if ($NoNetwork) { $excludeList += "network" }
            if ($NoStorage) { $excludeList += "storage" }
            if ($NoNodes) { $excludeList += "nodes" }
            $excludeDesc = if ($excludeList.Count -gt 0) { " (excluding: $($excludeList -join ', '))" } else { "" }

            # Confirm action
            if ($PSCmdlet.ShouldProcess("$($source.Name) -> $cloneName", "Clone Tenant$excludeDesc")) {
                try {
                    Write-Verbose "Cloning tenant '$($source.Name)' to '$cloneName'"
                    $response = Invoke-VergeAPI -Method POST -Endpoint 'tenant_actions' -Body $body -Connection $Server

                    Write-Verbose "Clone operation initiated for tenant '$($source.Name)'"

                    # Try to get the task to find the new tenant key
                    $taskKey = $response.'$key'
                    if ($taskKey) {
                        Write-Verbose "Clone task started with key: $taskKey"
                    }

                    if ($PassThru) {
                        # Wait a moment for the clone to be created, then find it
                        Start-Sleep -Seconds 2

                        # Find the new tenant by name
                        $newTenant = Get-VergeTenant -Name $cloneName -Server $Server
                        if ($newTenant) {
                            Write-Output $newTenant
                        }
                        else {
                            Write-Warning "Clone operation initiated but tenant '$cloneName' not yet found. It may still be creating."
                        }
                    }
                }
                catch {
                    $errorMessage = $_.Exception.Message
                    if ($errorMessage -match 'already in use') {
                        throw "A tenant with the name '$cloneName' already exists."
                    }
                    Write-Error -Message "Failed to clone tenant '$($source.Name)': $errorMessage" -ErrorId 'TenantCloneFailed'
                }
            }
        }
    }
}
