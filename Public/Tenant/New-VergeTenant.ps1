function New-VergeTenant {
    <#
    .SYNOPSIS
        Creates a new tenant in VergeOS.

    .DESCRIPTION
        New-VergeTenant creates a new tenant with the specified configuration.
        The tenant is created in a stopped state by default. Use -PowerOn to start
        the tenant immediately after creation.

    .PARAMETER Name
        The name of the new tenant. Must be unique and 1-120 characters.

    .PARAMETER Password
        The password for the auto-created admin user. If not specified, a random
        password will be generated (check the tenant after creation).

    .PARAMETER Description
        An optional description for the tenant.

    .PARAMETER URL
        An optional URL associated with the tenant.

    .PARAMETER Note
        An optional note for the tenant.

    .PARAMETER ExposeCloudSnapshots
        If set, the tenant will be able to request a snapshot of their system from
        your system snapshots. Default is $true.

    .PARAMETER AllowBranding
        If set, the tenant will be able to customize colors and their logo.
        Default is $false.

    .PARAMETER RequirePasswordChange
        If set, the admin user will be required to change their password on first login.
        Default is $false.

    .PARAMETER PowerOn
        Start the tenant immediately after creation.

    .PARAMETER PassThru
        Return the created tenant object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeTenant -Name "Customer01"

        Creates a tenant with default settings.

    .EXAMPLE
        New-VergeTenant -Name "Customer01" -Password "SecurePass123!" -Description "Customer tenant"

        Creates a tenant with a specific admin password and description.

    .EXAMPLE
        New-VergeTenant -Name "Customer01" -AllowBranding -PowerOn -PassThru

        Creates a tenant with branding enabled, starts it, and returns the tenant object.

    .OUTPUTS
        None by default. Verge.Tenant when -PassThru is specified.

    .NOTES
        After creating a tenant, use Set-VergeTenantStorage to allocate storage tiers.
        The tenant needs at least one storage tier allocation before VMs can be created.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [ValidateLength(1, 120)]
        [string]$Name,

        [Parameter()]
        [ValidateLength(0, 256)]
        [string]$Password,

        [Parameter()]
        [ValidateLength(0, 2048)]
        [string]$Description,

        [Parameter()]
        [string]$URL,

        [Parameter()]
        [ValidateLength(0, 1024)]
        [string]$Note,

        [Parameter()]
        [bool]$ExposeCloudSnapshots = $true,

        [Parameter()]
        [switch]$AllowBranding,

        [Parameter()]
        [switch]$RequirePasswordChange,

        [Parameter()]
        [switch]$PowerOn,

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
        # Build request body with required and specified fields
        $body = @{
            name                   = $Name
            expose_cloud_snapshots = $ExposeCloudSnapshots
        }

        # Add optional parameters
        if ($Password) {
            $body['password'] = $Password
        }

        if ($Description) {
            $body['description'] = $Description
        }

        if ($URL) {
            $body['url'] = $URL
        }

        if ($Note) {
            $body['note'] = $Note
        }

        if ($AllowBranding) {
            $body['allow_branding'] = $true
        }

        if ($RequirePasswordChange) {
            $body['change_password'] = $true
        }

        # Confirm action
        if ($PSCmdlet.ShouldProcess($Name, 'Create Tenant')) {
            try {
                Write-Verbose "Creating tenant '$Name'"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'tenants' -Body $body -Connection $Server

                # Get the created tenant key
                $tenantKey = $response.'$key'
                if (-not $tenantKey -and $response.key) {
                    $tenantKey = $response.key
                }

                Write-Verbose "Tenant '$Name' created with Key: $tenantKey"

                # Power on if requested
                if ($PowerOn -and $tenantKey) {
                    Write-Verbose "Powering on tenant '$Name'"
                    $powerBody = @{
                        tenant = $tenantKey
                        action = 'poweron'
                    }
                    Invoke-VergeAPI -Method POST -Endpoint 'tenant_actions' -Body $powerBody -Connection $Server | Out-Null
                }

                if ($PassThru -and $tenantKey) {
                    # Return the created tenant
                    Start-Sleep -Milliseconds 500
                    Get-VergeTenant -Key $tenantKey -Server $Server
                }
            }
            catch {
                $errorMessage = $_.Exception.Message
                if ($errorMessage -match 'already in use') {
                    throw "A tenant with the name '$Name' already exists."
                }
                throw "Failed to create tenant '$Name': $errorMessage"
            }
        }
    }
}
