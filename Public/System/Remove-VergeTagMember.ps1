function Remove-VergeTagMember {
    <#
    .SYNOPSIS
        Removes a tag assignment from a resource in VergeOS.

    .DESCRIPTION
        Remove-VergeTagMember removes a tag from a resource such as a VM, network,
        or tenant. This cmdlet supports multiple ways to identify the tag assignment
        to remove: by key, by tag member object, or by specifying the tag and resource.

    .PARAMETER Key
        The unique key (ID) of the tag member assignment to remove.

    .PARAMETER TagMember
        A tag member object from Get-VergeTagMember. Accepts pipeline input.

    .PARAMETER Tag
        The tag to remove. Used with VM, Network, Tenant, or ResourceType parameters.

    .PARAMETER VM
        The VM to remove the tag from. Accepts a VM name, key, or Verge.VM object.

    .PARAMETER Network
        The network to remove the tag from. Accepts a network name, key, or Verge.Network object.

    .PARAMETER Tenant
        The tenant to remove the tag from. Accepts a tenant name, key, or Verge.Tenant object.

    .PARAMETER ResourceType
        The type of resource when using ResourceKey parameter.

    .PARAMETER ResourceKey
        The key (ID) of the resource. Must be used with ResourceType.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeTagMember -Key 1

        Removes the tag member assignment with key 1.

    .EXAMPLE
        Get-VergeTagMember -Tag "Production" | Remove-VergeTagMember

        Removes all tag assignments for the "Production" tag.

    .EXAMPLE
        Remove-VergeTagMember -Tag "Production" -VM "WebServer01"

        Removes the "Production" tag from the specified VM.

    .EXAMPLE
        Get-VergeVM -Name "Dev-*" | ForEach-Object {
            Remove-VergeTagMember -Tag "Production" -VM $_
        }

        Removes the "Production" tag from all VMs matching "Dev-*".

    .OUTPUTS
        None

    .NOTES
        Use Get-VergeTagMember to list existing tag assignments.
        Use Add-VergeTagMember to assign tags to resources.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByKey')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByTagMember')]
        [PSTypeName('Verge.TagMember')]
        [PSCustomObject]$TagMember,

        [Parameter(Mandatory, ParameterSetName = 'ByTagAndVM')]
        [Parameter(Mandatory, ParameterSetName = 'ByTagAndNetwork')]
        [Parameter(Mandatory, ParameterSetName = 'ByTagAndTenant')]
        [Parameter(Mandatory, ParameterSetName = 'ByTagAndGeneric')]
        [object]$Tag,

        [Parameter(Mandatory, ParameterSetName = 'ByTagAndVM')]
        [object]$VM,

        [Parameter(Mandatory, ParameterSetName = 'ByTagAndNetwork')]
        [Alias('VNet')]
        [object]$Network,

        [Parameter(Mandatory, ParameterSetName = 'ByTagAndTenant')]
        [object]$Tenant,

        [Parameter(Mandatory, ParameterSetName = 'ByTagAndGeneric')]
        [ValidateSet('vms', 'vnets', 'volumes', 'tenants', 'users', 'groups', 'nodes', 'clusters', 'sites', 'vnet_rules', 'vmware_containers', 'tenant_nodes')]
        [string]$ResourceType,

        [Parameter(Mandatory, ParameterSetName = 'ByTagAndGeneric')]
        [int]$ResourceKey,

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
        $memberKey = $null
        $displayName = $null

        switch -Wildcard ($PSCmdlet.ParameterSetName) {
            'ByKey' {
                $memberKey = $Key
                $displayName = "Tag member $Key"
            }
            'ByTagMember' {
                $memberKey = $TagMember.Key
                $displayName = "Tag '$($TagMember.TagName)' from $($TagMember.ResourceRef)"
            }
            'ByTagAnd*' {
                # Resolve tag
                $tagKey = $null
                $tagName = $null

                if ($Tag.PSObject.TypeNames -contains 'Verge.Tag') {
                    $tagKey = $Tag.Key
                    $tagName = $Tag.Name
                }
                elseif ($Tag -is [int]) {
                    $tagKey = $Tag
                    $foundTag = Get-VergeTag -Key $tagKey -Server $Server
                    $tagName = if ($foundTag) { $foundTag.Name } else { "Tag $tagKey" }
                }
                elseif ($Tag -is [string]) {
                    if ($Tag -match '^\d+$') {
                        $tagKey = [int]$Tag
                        $foundTag = Get-VergeTag -Key $tagKey -Server $Server
                        $tagName = if ($foundTag) { $foundTag.Name } else { "Tag $tagKey" }
                    }
                    else {
                        $foundTag = Get-VergeTag -Name $Tag -Server $Server | Select-Object -First 1
                        if ($foundTag) {
                            $tagKey = $foundTag.Key
                            $tagName = $foundTag.Name
                        }
                    }
                }

                if (-not $tagKey) {
                    Write-Error -Message "Tag '$Tag' not found" -ErrorId 'TagNotFound' -Category ObjectNotFound
                    return
                }

                # Resolve member reference
                $memberRef = $null
                $resourceName = $null

                switch ($PSCmdlet.ParameterSetName) {
                    'ByTagAndVM' {
                        if ($VM.PSObject.TypeNames -contains 'Verge.VM') {
                            $memberRef = "vms/$($VM.Key)"
                            $resourceName = $VM.Name
                        }
                        elseif ($VM -is [int]) {
                            $memberRef = "vms/$VM"
                            $existingVM = Get-VergeVM -Key $VM -Server $Server -ErrorAction SilentlyContinue
                            $resourceName = if ($existingVM) { $existingVM.Name } else { "VM $VM" }
                        }
                        elseif ($VM -is [string]) {
                            $existingVM = Get-VergeVM -Name $VM -Server $Server -ErrorAction SilentlyContinue | Select-Object -First 1
                            if ($existingVM) {
                                $memberRef = "vms/$($existingVM.Key)"
                                $resourceName = $existingVM.Name
                            }
                            else {
                                Write-Error -Message "VM not found: $VM" -ErrorId 'VMNotFound' -Category ObjectNotFound
                                return
                            }
                        }
                    }
                    'ByTagAndNetwork' {
                        if ($Network.PSObject.TypeNames -contains 'Verge.Network') {
                            $memberRef = "vnets/$($Network.Key)"
                            $resourceName = $Network.Name
                        }
                        elseif ($Network -is [int]) {
                            $memberRef = "vnets/$Network"
                            $existingNetwork = Get-VergeNetwork -Key $Network -Server $Server -ErrorAction SilentlyContinue
                            $resourceName = if ($existingNetwork) { $existingNetwork.Name } else { "Network $Network" }
                        }
                        elseif ($Network -is [string]) {
                            $existingNetwork = Get-VergeNetwork -Name $Network -Server $Server -ErrorAction SilentlyContinue | Select-Object -First 1
                            if ($existingNetwork) {
                                $memberRef = "vnets/$($existingNetwork.Key)"
                                $resourceName = $existingNetwork.Name
                            }
                            else {
                                Write-Error -Message "Network not found: $Network" -ErrorId 'NetworkNotFound' -Category ObjectNotFound
                                return
                            }
                        }
                    }
                    'ByTagAndTenant' {
                        if ($Tenant.PSObject.TypeNames -contains 'Verge.Tenant') {
                            $memberRef = "tenants/$($Tenant.Key)"
                            $resourceName = $Tenant.Name
                        }
                        elseif ($Tenant -is [int]) {
                            $memberRef = "tenants/$Tenant"
                            $existingTenant = Get-VergeTenant -Key $Tenant -Server $Server -ErrorAction SilentlyContinue
                            $resourceName = if ($existingTenant) { $existingTenant.Name } else { "Tenant $Tenant" }
                        }
                        elseif ($Tenant -is [string]) {
                            $existingTenant = Get-VergeTenant -Name $Tenant -Server $Server -ErrorAction SilentlyContinue | Select-Object -First 1
                            if ($existingTenant) {
                                $memberRef = "tenants/$($existingTenant.Key)"
                                $resourceName = $existingTenant.Name
                            }
                            else {
                                Write-Error -Message "Tenant not found: $Tenant" -ErrorId 'TenantNotFound' -Category ObjectNotFound
                                return
                            }
                        }
                    }
                    'ByTagAndGeneric' {
                        $memberRef = "$ResourceType/$ResourceKey"
                        $resourceName = "$ResourceType/$ResourceKey"
                    }
                }

                if (-not $memberRef) {
                    Write-Error -Message "Could not resolve resource reference" -ErrorId 'ResourceNotResolved' -Category InvalidArgument
                    return
                }

                # Find the tag member by tag and member reference
                $existingMembers = Get-VergeTagMember -Tag $tagKey -Server $Server |
                    Where-Object { $_.ResourceRef -eq $memberRef }

                if (-not $existingMembers -or $existingMembers.Count -eq 0) {
                    Write-Warning "Tag '$tagName' is not assigned to '$resourceName'"
                    return
                }

                $memberKey = $existingMembers[0].Key
                $displayName = "Tag '$tagName' from '$resourceName'"
            }
        }

        if (-not $memberKey) {
            Write-Error -Message "Could not determine tag member to remove" -ErrorId 'TagMemberNotFound' -Category ObjectNotFound
            return
        }

        if ($PSCmdlet.ShouldProcess($displayName, 'Remove Tag Assignment')) {
            try {
                Write-Verbose "Removing tag assignment (Key: $memberKey)"
                Invoke-VergeAPI -Method DELETE -Endpoint "tag_members/$memberKey" -Connection $Server | Out-Null
                Write-Verbose "Tag assignment removed successfully"
            }
            catch {
                $errorMessage = $_.Exception.Message
                if ($errorMessage -match 'not found') {
                    Write-Warning "Tag assignment not found (may have already been removed)"
                }
                else {
                    Write-Error -Message "Failed to remove tag assignment: $errorMessage" -ErrorId 'TagMemberDeleteFailed'
                }
            }
        }
    }
}
