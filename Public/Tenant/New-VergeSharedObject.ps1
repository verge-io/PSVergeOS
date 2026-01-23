function New-VergeSharedObject {
    <#
    .SYNOPSIS
        Shares a VM with a VergeOS tenant.

    .DESCRIPTION
        New-VergeSharedObject shares a VM from the parent system with a tenant.
        The shared VM can then be imported by the tenant to create their own copy.
        This is useful for distributing templates or pre-configured VMs to tenants.

    .PARAMETER Tenant
        A tenant object from Get-VergeTenant. Accepts pipeline input.

    .PARAMETER TenantName
        The name of the tenant to share the VM with.

    .PARAMETER TenantKey
        The unique key (ID) of the tenant to share the VM with.

    .PARAMETER VM
        A VM object from Get-VergeVM to share.

    .PARAMETER VMName
        The name of the VM to share.

    .PARAMETER VMKey
        The unique key (ID) of the VM to share.

    .PARAMETER Name
        The name for the shared object (how it appears to the tenant).
        Defaults to the VM name if not specified.

    .PARAMETER Description
        Optional description for the shared object.

    .PARAMETER PassThru
        Return the created shared object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeSharedObject -TenantName "Customer01" -VMName "Ubuntu-Template"

        Shares the VM "Ubuntu-Template" with the tenant.

    .EXAMPLE
        Get-VergeVM -Name "Windows-Base" | New-VergeSharedObject -TenantName "Customer01" -Name "Windows Server Template"

        Shares a VM with a custom name for the tenant.

    .EXAMPLE
        New-VergeSharedObject -TenantName "Customer01" -VMName "AppServer" -Description "Pre-configured application server" -PassThru

        Shares a VM with description and returns the shared object.

    .OUTPUTS
        None by default. Verge.SharedObject when -PassThru is specified.

    .NOTES
        The VM must exist and be accessible. A snapshot of the VM will be created
        for sharing. The tenant can then import this shared object to create
        their own copy.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByNames')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByTenantVM')]
        [PSTypeName('Verge.Tenant')]
        [PSCustomObject]$Tenant,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByNames')]
        [Parameter(Mandatory, ParameterSetName = 'ByTenantNameVMKey')]
        [string]$TenantName,

        [Parameter(Mandatory, ParameterSetName = 'ByTenantKeyVMName')]
        [Parameter(Mandatory, ParameterSetName = 'ByTenantKeyVMKey')]
        [int]$TenantKey,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByTenantVM')]
        [PSTypeName('Verge.VM')]
        [PSCustomObject]$VM,

        [Parameter(Mandatory, Position = 1, ParameterSetName = 'ByNames')]
        [Parameter(Mandatory, ParameterSetName = 'ByTenantKeyVMName')]
        [string]$VMName,

        [Parameter(Mandatory, ParameterSetName = 'ByTenantNameVMKey')]
        [Parameter(Mandatory, ParameterSetName = 'ByTenantKeyVMKey')]
        [int]$VMKey,

        [Parameter()]
        [ValidateLength(1, 128)]
        [string]$Name,

        [Parameter()]
        [ValidateLength(0, 2048)]
        [string]$Description,

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
        # Resolve tenant
        $targetTenant = switch -Wildcard ($PSCmdlet.ParameterSetName) {
            '*TenantName*' {
                Get-VergeTenant -Name $TenantName -Server $Server
            }
            '*TenantKey*' {
                Get-VergeTenant -Key $TenantKey -Server $Server
            }
            'ByTenantVM' {
                $Tenant
            }
            'ByNames' {
                Get-VergeTenant -Name $TenantName -Server $Server
            }
        }

        if (-not $targetTenant) {
            Write-Error -Message "Tenant not found." -ErrorId 'TenantNotFound'
            return
        }

        # Resolve VM
        $targetVM = switch -Wildcard ($PSCmdlet.ParameterSetName) {
            '*VMName*' {
                Get-VergeVM -Name $VMName -Server $Server
            }
            '*VMKey*' {
                Get-VergeVM -Key $VMKey -Server $Server
            }
            'ByTenantVM' {
                $VM
            }
            'ByNames' {
                Get-VergeVM -Name $VMName -Server $Server
            }
        }

        if (-not $targetVM) {
            Write-Error -Message "VM not found." -ErrorId 'VMNotFound'
            return
        }

        foreach ($t in $targetTenant) {
            if (-not $t) {
                continue
            }

            # Check if tenant is a snapshot
            if ($t.IsSnapshot) {
                Write-Error -Message "Cannot share VM with tenant '$($t.Name)': Tenant is a snapshot." -ErrorId 'CannotModifySnapshot'
                continue
            }

            foreach ($v in $targetVM) {
                if (-not $v) {
                    continue
                }

                # Determine the shared object name
                $sharedName = if ($Name) { $Name } else { $v.Name }

                # Build request body
                $body = @{
                    recipient = $t.Key
                    type      = 'vm'
                    name      = $sharedName
                    id        = "vms/$($v.Key)"
                }

                # Add optional description
                if ($Description) {
                    $body['description'] = $Description
                }

                # Confirm action
                if ($PSCmdlet.ShouldProcess("$($t.Name)", "Share VM '$($v.Name)' as '$sharedName'")) {
                    try {
                        Write-Verbose "Sharing VM '$($v.Name)' with tenant '$($t.Name)' as '$sharedName'"
                        $response = Invoke-VergeAPI -Method POST -Endpoint 'shared_objects' -Body $body -Connection $Server

                        Write-Verbose "VM '$($v.Name)' shared with tenant '$($t.Name)'"

                        if ($PassThru) {
                            # Wait briefly then return the new shared object
                            Start-Sleep -Milliseconds 500
                            Get-VergeSharedObject -TenantKey $t.Key -Name $sharedName -Server $Server
                        }
                    }
                    catch {
                        $errorMessage = $_.Exception.Message
                        if ($errorMessage -match 'already exists') {
                            Write-Error -Message "A shared object named '$sharedName' already exists for tenant '$($t.Name)'." -ErrorId 'SharedObjectExists'
                        }
                        else {
                            Write-Error -Message "Failed to share VM with tenant '$($t.Name)': $errorMessage" -ErrorId 'ShareVMFailed'
                        }
                    }
                }
            }
        }
    }
}
