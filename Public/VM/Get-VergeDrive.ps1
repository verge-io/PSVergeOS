function Get-VergeDrive {
    <#
    .SYNOPSIS
        Retrieves drives attached to a VergeOS virtual machine.

    .DESCRIPTION
        Get-VergeDrive retrieves drive information for one or more VMs, including
        disk size, interface type, media type, and storage tier details.

    .PARAMETER VM
        A VM object from Get-VergeVM. Accepts pipeline input.

    .PARAMETER VMName
        The name of the VM to get drives for.

    .PARAMETER VMKey
        The key (ID) of the VM to get drives for.

    .PARAMETER Name
        Filter drives by name. Supports wildcards (* and ?).

    .PARAMETER Media
        Filter drives by media type: Disk, CDROM, EFIDisk.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeDrive -VMName "WebServer01"

        Gets all drives attached to the VM named "WebServer01".

    .EXAMPLE
        Get-VergeVM -Name "WebServer01" | Get-VergeDrive

        Gets drives for the VM using pipeline input.

    .EXAMPLE
        Get-VergeVM -Name "Prod-*" | Get-VergeDrive | Where-Object { $_.UsedGB -gt 100 }

        Gets drives larger than 100GB for all production VMs.

    .EXAMPLE
        Get-VergeDrive -VMName "WebServer01" -Media CDROM

        Gets only CD-ROM drives for the specified VM.

    .EXAMPLE
        Get-VergeVM | Get-VergeDrive | Format-Table VMName, Name, Interface, SizeGB, UsedGB, Tier

        Lists all drives across all VMs in a table format.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.Drive'

    .NOTES
        Use New-VergeDrive and Remove-VergeDrive to manage VM drives.
        Use Set-VergeDrive to modify drive settings or change CD/ISO media.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByVMObject')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByVMObject')]
        [PSTypeName('Verge.VM')]
        [PSCustomObject]$VM,

        [Parameter(Mandatory, ParameterSetName = 'ByVMName')]
        [string]$VMName,

        [Parameter(Mandatory, ParameterSetName = 'ByVMKey')]
        [int]$VMKey,

        [Parameter()]
        [SupportsWildcards()]
        [string]$Name,

        [Parameter()]
        [ValidateSet('Disk', 'CDROM', 'EFIDisk')]
        [string]$Media,

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

        # Map friendly media names to API values
        $mediaMap = @{
            'Disk'    = 'disk'
            'CDROM'   = 'cdrom'
            'EFIDisk' = 'efidisk'
        }

        # Map API interface values to friendly names
        $interfaceDisplayMap = @{
            'virtio'               = 'Virtio (Legacy)'
            'ide'                  = 'IDE'
            'ahci'                 = 'SATA (AHCI)'
            'nvme'                 = 'NVMe'
            'virtio-scsi'          = 'Virtio-SCSI'
            'virtio-scsi-dedicated' = 'Virtio-SCSI (Dedicated)'
            'lsi53c895a'           = 'LSI SCSI'
            'megasas'              = 'LSI MegaRAID SAS'
            'megasas-gen2'         = 'LSI MegaRAID SAS 2'
            'usb'                  = 'USB'
        }
    }

    process {
        # Resolve VM based on parameter set
        $targetVMs = switch ($PSCmdlet.ParameterSetName) {
            'ByVMName' {
                Get-VergeVM -Name $VMName -Server $Server
            }
            'ByVMKey' {
                Get-VergeVM -Key $VMKey -Server $Server
            }
            'ByVMObject' {
                $VM
            }
        }

        foreach ($targetVM in $targetVMs) {
            if (-not $targetVM -or -not $targetVM.MachineKey) {
                continue
            }

            # Build query for drives
            $queryParams = @{}

            # Filter by machine (VM's internal machine key)
            $filters = [System.Collections.Generic.List[string]]::new()
            $filters.Add("machine eq $($targetVM.MachineKey)")

            # Filter by media type if specified
            if ($Media) {
                $filters.Add("media eq '$($mediaMap[$Media])'")
            }

            $queryParams['filter'] = $filters -join ' and '

            # Request drive fields including related data
            $queryParams['fields'] = @(
                '$key'
                'name'
                'orderid'
                'interface'
                'media'
                'description'
                'enabled'
                'serial'
                'preferred_tier'
                'readonly'
                'disksize'
                'used_bytes'
                'media_source'
                'machine'
                'status#status as status'
                'status#display(status) as status_display'
                'media_source#name as media_file'
                'media_source#allocated_bytes as allocated_bytes'
                'media_source#used_bytes as file_used_bytes'
                'media_source#filesize as filesize'
            ) -join ','

            $queryParams['sort'] = '+orderid'

            try {
                Write-Verbose "Querying drives for VM '$($targetVM.Name)' (Machine: $($targetVM.MachineKey))"
                $response = Invoke-VergeAPI -Method GET -Endpoint 'machine_drives' -Query $queryParams -Connection $Server

                # Handle both single object and array responses
                $drives = if ($response -is [array]) { $response } elseif ($response) { @($response) } else { @() }

                foreach ($drive in $drives) {
                    if (-not $drive -or -not $drive.name) {
                        continue
                    }

                    # Apply name filter if specified (with wildcard support)
                    if ($Name) {
                        if ($Name -match '[\*\?]') {
                            if ($drive.name -notlike $Name) {
                                continue
                            }
                        }
                        elseif ($drive.name -ne $Name) {
                            continue
                        }
                    }

                    # Calculate sizes in GB
                    $sizeBytes = if ($drive.disksize) { $drive.disksize } elseif ($drive.allocated_bytes) { $drive.allocated_bytes } else { 0 }
                    $usedBytes = if ($drive.used_bytes) { $drive.used_bytes } elseif ($drive.file_used_bytes) { $drive.file_used_bytes } else { 0 }

                    # Map media type to friendly name
                    $mediaDisplay = switch ($drive.media) {
                        'cdrom'    { 'CD-ROM' }
                        'disk'     { 'Disk' }
                        'efidisk'  { 'EFI Disk' }
                        'import'   { 'Import Disk' }
                        '9p'       { 'Pass-Through (9P)' }
                        'dir'      { 'Pass-Through (Directory)' }
                        'clone'    { 'Clone Disk' }
                        'nonpersistent' { 'Non-Persistent' }
                        default    { $drive.media }
                    }

                    # Get interface display name
                    $interfaceDisplay = if ($interfaceDisplayMap.ContainsKey($drive.interface)) {
                        $interfaceDisplayMap[$drive.interface]
                    } else {
                        $drive.interface
                    }

                    # Create output object
                    $output = [PSCustomObject]@{
                        PSTypeName       = 'Verge.Drive'
                        Key              = [int]$drive.'$key'
                        Name             = $drive.name
                        OrderId          = [int]$drive.orderid
                        Interface        = $drive.interface
                        InterfaceDisplay = $interfaceDisplay
                        Media            = $drive.media
                        MediaDisplay     = $mediaDisplay
                        Description      = $drive.description
                        Enabled          = [bool]$drive.enabled
                        ReadOnly         = [bool]$drive.readonly
                        Serial           = $drive.serial
                        Tier             = $drive.preferred_tier
                        SizeBytes        = [long]$sizeBytes
                        SizeGB           = [math]::Round($sizeBytes / 1GB, 2)
                        UsedBytes        = [long]$usedBytes
                        UsedGB           = [math]::Round($usedBytes / 1GB, 2)
                        MediaSource      = $drive.media_source
                        MediaFile        = $drive.media_file
                        Status           = $drive.status
                        StatusDisplay    = $drive.status_display
                        VMKey            = $targetVM.Key
                        VMName           = $targetVM.Name
                        MachineKey       = $targetVM.MachineKey
                    }

                    # Add hidden property for pipeline support
                    $output | Add-Member -MemberType NoteProperty -Name '_Connection' -Value $Server -Force
                    $output | Add-Member -MemberType NoteProperty -Name '_VM' -Value $targetVM -Force

                    Write-Output $output
                }
            }
            catch {
                Write-Error -Message "Failed to get drives for VM '$($targetVM.Name)': $($_.Exception.Message)" -ErrorId 'GetDrivesFailed'
            }
        }
    }
}
