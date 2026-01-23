function Connect-VergeTenantContext {
    <#
    .SYNOPSIS
        Connects to a VergeOS tenant context for executing commands as the tenant.

    .DESCRIPTION
        Connect-VergeTenantContext establishes a connection to a tenant's VergeOS
        environment. This allows you to run commands within the tenant's context,
        similar to logging into the tenant's UI directly. The tenant must be running.

    .PARAMETER Tenant
        A tenant object from Get-VergeTenant. Accepts pipeline input.

    .PARAMETER TenantName
        The name of the tenant to connect to.

    .PARAMETER TenantKey
        The unique key (ID) of the tenant to connect to.

    .PARAMETER Credential
        The credentials to use for authenticating to the tenant.
        If not specified, you will be prompted for credentials.

    .PARAMETER SkipCertificateCheck
        Skip SSL certificate validation. Useful for self-signed certificates.

    .PARAMETER PassThru
        Return the tenant connection object.

    .PARAMETER Server
        The VergeOS connection to use for resolving the tenant. Defaults to the current default connection.

    .EXAMPLE
        Connect-VergeTenantContext -TenantName "Customer01" -Credential $cred

        Connects to the tenant using the specified credentials.

    .EXAMPLE
        Get-VergeTenant -Name "Customer01" | Connect-VergeTenantContext -Credential $cred -PassThru

        Connects to the tenant and returns the connection object.

    .EXAMPLE
        $tenantConn = Connect-VergeTenantContext -TenantName "Customer01" -Credential $cred -PassThru
        Get-VergeVM -Server $tenantConn

        Connects to tenant and uses the connection to list VMs in the tenant.

    .OUTPUTS
        None by default. VergeConnection when -PassThru is specified.

    .NOTES
        The tenant must be running to connect. The credentials must be valid for
        the tenant's VergeOS environment. Use Disconnect-VergeOS to disconnect
        from the tenant context when finished.
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
        [PSCredential]$Credential,

        [Parameter()]
        [switch]$SkipCertificateCheck,

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

            # Check if tenant is a snapshot
            if ($t.IsSnapshot) {
                Write-Error -Message "Cannot connect to tenant '$($t.Name)': Tenant is a snapshot." -ErrorId 'CannotConnectToSnapshot'
                continue
            }

            # Check if tenant is running
            if (-not $t.IsRunning -and $t.Status -ne 'Online') {
                Write-Error -Message "Cannot connect to tenant '$($t.Name)': Tenant is not running. Start the tenant first." -ErrorId 'TenantNotRunning'
                continue
            }

            # Get the tenant's UI address
            $tenantAddress = $t.UIAddressIP
            if (-not $tenantAddress) {
                # Try to get it from the tenant details
                $queryParams = @{
                    filter = "`$key eq $($t.Key)"
                    fields = 'ui_address,ui_address#ip as ui_address_ip'
                }
                $tenantDetails = Invoke-VergeAPI -Method GET -Endpoint 'tenants' -Query $queryParams -Connection $Server
                $tenantAddress = $tenantDetails.ui_address_ip
            }

            if (-not $tenantAddress) {
                Write-Error -Message "Cannot connect to tenant '$($t.Name)': No UI address configured." -ErrorId 'NoUIAddress'
                continue
            }

            # Prompt for credentials if not provided
            if (-not $Credential) {
                $Credential = Get-Credential -Message "Enter credentials for tenant '$($t.Name)' at $tenantAddress"
                if (-not $Credential) {
                    Write-Error -Message "Credentials required to connect to tenant." -ErrorId 'CredentialsRequired'
                    continue
                }
            }

            try {
                Write-Verbose "Connecting to tenant '$($t.Name)' at $tenantAddress"

                # Build connection parameters
                $connectParams = @{
                    Server     = $tenantAddress
                    Credential = $Credential
                }

                if ($SkipCertificateCheck -or $Server.SkipCertificateCheck) {
                    $connectParams['SkipCertificateCheck'] = $true
                }

                # Connect to the tenant
                $tenantConnection = Connect-VergeOS @connectParams

                if ($tenantConnection) {
                    Write-Verbose "Successfully connected to tenant '$($t.Name)'"

                    # Add tenant context information
                    $tenantConnection | Add-Member -MemberType NoteProperty -Name 'IsTenantContext' -Value $true -Force
                    $tenantConnection | Add-Member -MemberType NoteProperty -Name 'ParentTenantName' -Value $t.Name -Force
                    $tenantConnection | Add-Member -MemberType NoteProperty -Name 'ParentTenantKey' -Value $t.Key -Force

                    if ($PassThru) {
                        Write-Output $tenantConnection
                    }
                }
            }
            catch {
                Write-Error -Message "Failed to connect to tenant '$($t.Name)': $($_.Exception.Message)" -ErrorId 'TenantConnectFailed'
            }
        }
    }
}
