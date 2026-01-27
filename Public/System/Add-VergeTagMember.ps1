function Add-VergeTagMember {
    <#
    .SYNOPSIS
        Assigns a tag to a resource in VergeOS.

    .DESCRIPTION
        Add-VergeTagMember assigns a tag to a resource such as a VM, network, tenant,
        or other taggable object. The tag must already exist and the resource type
        must be enabled for tagging in the tag's category.

    .PARAMETER Tag
        The tag to assign. Accepts a tag name, key, or Verge.Tag object.

    .PARAMETER VM
        A VM to tag. Accepts a VM name, key, or Verge.VM object.

    .PARAMETER Network
        A network to tag. Accepts a network name, key, or Verge.Network object.

    .PARAMETER Tenant
        A tenant to tag. Accepts a tenant name, key, or Verge.Tenant object.

    .PARAMETER ResourceType
        The type of resource when using ResourceKey parameter.
        Valid values: vms, vnets, volumes, tenants, users, groups, nodes, clusters, sites, vnet_rules

    .PARAMETER ResourceKey
        The key (ID) of the resource to tag. Must be used with ResourceType.

    .PARAMETER PassThru
        Return the created tag member object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Add-VergeTagMember -Tag "Production" -VM "WebServer01"

        Assigns the "Production" tag to the VM named "WebServer01".

    .EXAMPLE
        Get-VergeVM -Name "Web*" | Add-VergeTagMember -Tag "Production"

        Tags all VMs starting with "Web" with the "Production" tag.

    .EXAMPLE
        Add-VergeTagMember -Tag "Production" -Network "DMZ"

        Assigns the "Production" tag to the "DMZ" network.

    .EXAMPLE
        Get-VergeTag -Name "Production" | Add-VergeTagMember -VM "WebServer01"

        Assigns a tag to a VM using pipeline input for the tag.

    .EXAMPLE
        Add-VergeTagMember -Tag "Critical" -ResourceType vms -ResourceKey 42

        Assigns a tag using the generic resource type and key parameters.

    .OUTPUTS
        None by default. Verge.TagMember when -PassThru is specified.

    .NOTES
        Use Get-VergeTagMember to list existing tag assignments.
        Use Remove-VergeTagMember to remove tag assignments.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'VM')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [object]$Tag,

        [Parameter(Mandatory, ParameterSetName = 'VM', ValueFromPipeline)]
        [object]$VM,

        [Parameter(Mandatory, ParameterSetName = 'Network')]
        [Alias('VNet')]
        [object]$Network,

        [Parameter(Mandatory, ParameterSetName = 'Tenant')]
        [object]$Tenant,

        [Parameter(Mandatory, ParameterSetName = 'Generic')]
        [ValidateSet('vms', 'vnets', 'volumes', 'tenants', 'users', 'groups', 'nodes', 'clusters', 'sites', 'vnet_rules', 'vmware_containers', 'tenant_nodes')]
        [string]$ResourceType,

        [Parameter(Mandatory, ParameterSetName = 'Generic')]
        [int]$ResourceKey,

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

        # Resolve tag once in begin block
        $resolvedTagKey = $null
        $resolvedTagName = $null

        # Handle Verge.Tag object
        if ($Tag.PSObject.TypeNames -contains 'Verge.Tag') {
            $resolvedTagKey = $Tag.Key
            $resolvedTagName = $Tag.Name
        }
        # Handle integer key
        elseif ($Tag -is [int]) {
            $resolvedTagKey = $Tag
            $foundTag = Get-VergeTag -Key $resolvedTagKey -Server $Server
            if ($foundTag) {
                $resolvedTagName = $foundTag.Name
            }
        }
        # Handle string (name or key)
        elseif ($Tag -is [string]) {
            if ($Tag -match '^\d+$') {
                $resolvedTagKey = [int]$Tag
                $foundTag = Get-VergeTag -Key $resolvedTagKey -Server $Server
                if ($foundTag) {
                    $resolvedTagName = $foundTag.Name
                }
            }
            else {
                # Look up tag by name
                $foundTag = Get-VergeTag -Name $Tag -Server $Server | Select-Object -First 1
                if ($foundTag) {
                    $resolvedTagKey = $foundTag.Key
                    $resolvedTagName = $foundTag.Name
                }
            }
        }

        if (-not $resolvedTagKey) {
            throw "Tag '$Tag' not found. Use Get-VergeTag to list available tags."
        }
    }

    process {
        # Resolve the resource reference based on parameter set
        $memberRef = $null
        $memberName = $null
        $memberType = $null

        switch ($PSCmdlet.ParameterSetName) {
            'VM' {
                $memberType = 'vms'
                if ($VM.PSObject.TypeNames -contains 'Verge.VM') {
                    $memberRef = "vms/$($VM.Key)"
                    $memberName = $VM.Name
                }
                elseif ($VM -is [int]) {
                    $memberRef = "vms/$VM"
                    $existingVM = Get-VergeVM -Key $VM -Server $Server -ErrorAction SilentlyContinue
                    $memberName = if ($existingVM) { $existingVM.Name } else { "VM $VM" }
                }
                elseif ($VM -is [string]) {
                    $existingVM = Get-VergeVM -Name $VM -Server $Server -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($existingVM) {
                        $memberRef = "vms/$($existingVM.Key)"
                        $memberName = $existingVM.Name
                    }
                    else {
                        Write-Error -Message "VM not found: $VM" -ErrorId 'VMNotFound' -Category ObjectNotFound
                        return
                    }
                }
            }
            'Network' {
                $memberType = 'vnets'
                if ($Network.PSObject.TypeNames -contains 'Verge.Network') {
                    $memberRef = "vnets/$($Network.Key)"
                    $memberName = $Network.Name
                }
                elseif ($Network -is [int]) {
                    $memberRef = "vnets/$Network"
                    $existingNetwork = Get-VergeNetwork -Key $Network -Server $Server -ErrorAction SilentlyContinue
                    $memberName = if ($existingNetwork) { $existingNetwork.Name } else { "Network $Network" }
                }
                elseif ($Network -is [string]) {
                    $existingNetwork = Get-VergeNetwork -Name $Network -Server $Server -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($existingNetwork) {
                        $memberRef = "vnets/$($existingNetwork.Key)"
                        $memberName = $existingNetwork.Name
                    }
                    else {
                        Write-Error -Message "Network not found: $Network" -ErrorId 'NetworkNotFound' -Category ObjectNotFound
                        return
                    }
                }
            }
            'Tenant' {
                $memberType = 'tenants'
                if ($Tenant.PSObject.TypeNames -contains 'Verge.Tenant') {
                    $memberRef = "tenants/$($Tenant.Key)"
                    $memberName = $Tenant.Name
                }
                elseif ($Tenant -is [int]) {
                    $memberRef = "tenants/$Tenant"
                    $existingTenant = Get-VergeTenant -Key $Tenant -Server $Server -ErrorAction SilentlyContinue
                    $memberName = if ($existingTenant) { $existingTenant.Name } else { "Tenant $Tenant" }
                }
                elseif ($Tenant -is [string]) {
                    $existingTenant = Get-VergeTenant -Name $Tenant -Server $Server -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($existingTenant) {
                        $memberRef = "tenants/$($existingTenant.Key)"
                        $memberName = $existingTenant.Name
                    }
                    else {
                        Write-Error -Message "Tenant not found: $Tenant" -ErrorId 'TenantNotFound' -Category ObjectNotFound
                        return
                    }
                }
            }
            'Generic' {
                $memberType = $ResourceType
                $memberRef = "$ResourceType/$ResourceKey"
                $memberName = "$ResourceType/$ResourceKey"
            }
        }

        if (-not $memberRef) {
            Write-Error -Message "Could not resolve resource reference" -ErrorId 'ResourceNotResolved' -Category InvalidArgument
            return
        }

        # Build request body
        $body = @{
            tag    = $resolvedTagKey
            member = $memberRef
        }

        if ($PSCmdlet.ShouldProcess("$memberName", "Add Tag '$resolvedTagName'")) {
            try {
                Write-Verbose "Adding tag '$resolvedTagName' to $memberType '$memberName'"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'tag_members' -Body $body -Connection $Server

                $membershipKey = $response.'$key'
                Write-Verbose "Tag '$resolvedTagName' assigned to '$memberName' (Membership Key: $membershipKey)"

                if ($PassThru -and $membershipKey) {
                    # Return the tag member record
                    [PSCustomObject]@{
                        PSTypeName   = 'Verge.TagMember'
                        Key          = [int]$membershipKey
                        TagKey       = $resolvedTagKey
                        TagName      = $resolvedTagName
                        ResourceType = $memberType
                        ResourceKey  = if ($ResourceKey) { $ResourceKey } else { [int]($memberRef -split '/')[-1] }
                        ResourceRef  = $memberRef
                    }
                }
            }
            catch {
                $errorMessage = $_.Exception.Message
                if ($errorMessage -match 'already' -or $errorMessage -match 'unique') {
                    Write-Warning "Tag '$resolvedTagName' is already assigned to '$memberName'"
                }
                else {
                    throw "Failed to add tag to resource: $errorMessage"
                }
            }
        }
    }
}
