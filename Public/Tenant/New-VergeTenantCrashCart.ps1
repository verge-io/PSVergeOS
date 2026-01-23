function New-VergeTenantCrashCart {
    <#
    .SYNOPSIS
        Deploys a Crash Cart VM for emergency access to a VergeOS tenant.

    .DESCRIPTION
        New-VergeTenantCrashCart deploys a Crash Cart VM that provides emergency
        UI access to a tenant. This is useful when normal tenant access is unavailable.
        The Crash Cart VM connects to the tenant's internal network and provides
        a web-based console for troubleshooting.

    .PARAMETER Tenant
        A tenant object from Get-VergeTenant. Accepts pipeline input.

    .PARAMETER TenantName
        The name of the tenant to deploy the Crash Cart for.

    .PARAMETER TenantKey
        The unique key (ID) of the tenant to deploy the Crash Cart for.

    .PARAMETER Name
        The name for the Crash Cart VM. Defaults to "Crash Cart - TenantName".

    .PARAMETER PassThru
        Return the created Crash Cart VM object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeTenantCrashCart -TenantName "Customer01"

        Deploys a Crash Cart VM for the tenant.

    .EXAMPLE
        Get-VergeTenant -Name "Customer01" | New-VergeTenantCrashCart -PassThru

        Deploys a Crash Cart and returns the VM object.

    .EXAMPLE
        New-VergeTenantCrashCart -TenantName "Customer01" -Name "Emergency Access VM"

        Deploys a Crash Cart with a custom name.

    .OUTPUTS
        None by default. Verge.VM when -PassThru is specified.

    .NOTES
        The Crash Cart VM requires the Crash Cart recipe to be available in the system.
        The VM provides emergency UI access and should be removed after troubleshooting.
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

        [Parameter()]
        [ValidateLength(1, 128)]
        [string]$Name,

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
                Write-Error -Message "Cannot deploy Crash Cart for tenant '$($t.Name)': Tenant is a snapshot." -ErrorId 'CannotModifySnapshot'
                continue
            }

            # Find the Crash Cart recipe
            $recipeQuery = @{
                filter = "name eq 'Crash Cart'"
                fields = 'id,name,description,version'
            }

            try {
                $recipe = Invoke-VergeAPI -Method GET -Endpoint 'vm_recipes' -Query $recipeQuery -Connection $Server
            }
            catch {
                Write-Error -Message "Failed to find Crash Cart recipe: $($_.Exception.Message)" -ErrorId 'RecipeNotFound'
                continue
            }

            if (-not $recipe) {
                Write-Error -Message "Crash Cart recipe not found. Ensure the Crash Cart recipe is available in the system." -ErrorId 'CrashCartRecipeNotFound'
                continue
            }

            # Determine the Crash Cart VM name
            $crashCartName = if ($Name) { $Name } else { "Crash Cart - $($t.Name)" }

            # Build request body for vm_recipe_instances
            $body = @{
                recipe  = $recipe.id
                name    = $crashCartName
                answers = @{
                    tenant = $t.Key
                }
            }

            # Confirm action
            if ($PSCmdlet.ShouldProcess("$($t.Name)", "Deploy Crash Cart VM '$crashCartName'")) {
                try {
                    Write-Verbose "Deploying Crash Cart VM '$crashCartName' for tenant '$($t.Name)'"
                    $response = Invoke-VergeAPI -Method POST -Endpoint 'vm_recipe_instances' -Body $body -Connection $Server

                    Write-Verbose "Crash Cart VM deployment initiated for tenant '$($t.Name)'"

                    if ($PassThru) {
                        # Wait for the VM to be created
                        Start-Sleep -Seconds 2

                        # Find the created VM
                        $vm = Get-VergeVM -Name $crashCartName -Server $Server
                        if ($vm) {
                            Write-Output $vm
                        }
                        else {
                            Write-Warning "Crash Cart deployment initiated but VM '$crashCartName' not yet found. It may still be creating."
                        }
                    }
                }
                catch {
                    Write-Error -Message "Failed to deploy Crash Cart for tenant '$($t.Name)': $($_.Exception.Message)" -ErrorId 'CrashCartDeployFailed'
                }
            }
        }
    }
}
