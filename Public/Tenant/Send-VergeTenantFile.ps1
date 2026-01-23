function Send-VergeTenantFile {
    <#
    .SYNOPSIS
        Shares a file with a VergeOS tenant.

    .DESCRIPTION
        Send-VergeTenantFile shares a file from the parent vSAN with a tenant.
        This allows tenants to access specific files (ISOs, disk images, etc.)
        within their own Files section. The process is near-instant as it uses
        a branch command rather than copying the file.

    .PARAMETER Tenant
        A tenant object from Get-VergeTenant. Accepts pipeline input.

    .PARAMETER TenantName
        The name of the tenant to share the file with.

    .PARAMETER TenantKey
        The unique key (ID) of the tenant to share the file with.

    .PARAMETER File
        A file object from Get-VergeFile. Accepts pipeline input.

    .PARAMETER FileName
        The name of the file to share.

    .PARAMETER FileKey
        The unique key (ID) of the file to share.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Send-VergeTenantFile -TenantName "Customer01" -FileName "ubuntu-22.04.iso"

        Shares the specified ISO file with the tenant.

    .EXAMPLE
        Get-VergeFile -Name "*.iso" | Send-VergeTenantFile -TenantName "Customer01"

        Shares all ISO files with the tenant.

    .EXAMPLE
        Get-VergeTenant -Name "Customer*" | Send-VergeTenantFile -FileName "windows.iso"

        Shares the Windows ISO with all tenants starting with "Customer".

    .OUTPUTS
        None.

    .NOTES
        Files must already exist on the vSAN. The process uses a branch command
        so it is nearly instantaneous and does not duplicate storage usage.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByTenantNameAndFileName')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByTenantAndFileName')]
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByTenantAndFileKey')]
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByTenantAndFile')]
        [PSTypeName('Verge.Tenant')]
        [PSCustomObject]$Tenant,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByTenantNameAndFileName')]
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByTenantNameAndFileKey')]
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByTenantNameAndFile')]
        [string]$TenantName,

        [Parameter(Mandatory, ParameterSetName = 'ByTenantKeyAndFileName')]
        [Parameter(Mandatory, ParameterSetName = 'ByTenantKeyAndFileKey')]
        [Parameter(Mandatory, ParameterSetName = 'ByTenantKeyAndFile')]
        [int]$TenantKey,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByTenantNameAndFile')]
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByTenantKeyAndFile')]
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByTenantAndFile')]
        [PSTypeName('Verge.File')]
        [PSCustomObject]$File,

        [Parameter(Mandatory, Position = 1, ParameterSetName = 'ByTenantNameAndFileName')]
        [Parameter(Mandatory, Position = 1, ParameterSetName = 'ByTenantKeyAndFileName')]
        [Parameter(Mandatory, Position = 1, ParameterSetName = 'ByTenantAndFileName')]
        [string]$FileName,

        [Parameter(Mandatory, ParameterSetName = 'ByTenantNameAndFileKey')]
        [Parameter(Mandatory, ParameterSetName = 'ByTenantKeyAndFileKey')]
        [Parameter(Mandatory, ParameterSetName = 'ByTenantAndFileKey')]
        [int]$FileKey,

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
        $targetTenant = switch -Wildcard ($PSCmdlet.ParameterSetName) {
            'ByTenantName*' {
                Get-VergeTenant -Name $TenantName -Server $Server
            }
            'ByTenantKey*' {
                Get-VergeTenant -Key $TenantKey -Server $Server
            }
            'ByTenant*' {
                $Tenant
            }
        }

        # Resolve file based on parameter set
        $targetFile = switch -Wildcard ($PSCmdlet.ParameterSetName) {
            '*FileName' {
                Get-VergeFile -Name $FileName -Server $Server
            }
            '*FileKey' {
                Get-VergeFile -Key $FileKey -Server $Server
            }
            '*File' {
                $File
            }
        }

        foreach ($t in $targetTenant) {
            if (-not $t) {
                continue
            }

            # Check if tenant is a snapshot
            if ($t.IsSnapshot) {
                Write-Error -Message "Cannot share file with tenant '$($t.Name)': Tenant is a snapshot." -ErrorId 'CannotModifySnapshot'
                continue
            }

            foreach ($f in $targetFile) {
                if (-not $f) {
                    if ($PSCmdlet.ParameterSetName -like '*FileName') {
                        Write-Error -Message "File '$FileName' not found." -ErrorId 'FileNotFound'
                    }
                    continue
                }

                # Confirm action
                if ($PSCmdlet.ShouldProcess("$($t.Name)", "Share file '$($f.Name)'")) {
                    try {
                        Write-Verbose "Sharing file '$($f.Name)' with tenant '$($t.Name)'"

                        $body = @{
                            tenant = $t.Key
                            action = 'give_file'
                            params = @{
                                file = $f.Key
                            }
                        }

                        $response = Invoke-VergeAPI -Method POST -Endpoint 'tenant_actions' -Body $body -Connection $Server

                        Write-Verbose "File '$($f.Name)' shared with tenant '$($t.Name)'"
                    }
                    catch {
                        Write-Error -Message "Failed to share file '$($f.Name)' with tenant '$($t.Name)': $($_.Exception.Message)" -ErrorId 'ShareFileFailed'
                    }
                }
            }
        }
    }
}
