function New-VergeDrive {
    <#
    .SYNOPSIS
        Adds a new drive to a VergeOS virtual machine.

    .DESCRIPTION
        New-VergeDrive creates a new virtual drive and attaches it to a VM.
        Supports disk, CD-ROM, and EFI disk types with various interface options.

    .PARAMETER VM
        A VM object from Get-VergeVM. Accepts pipeline input.

    .PARAMETER VMName
        The name of the VM to add the drive to.

    .PARAMETER VMKey
        The key (ID) of the VM to add the drive to.

    .PARAMETER Name
        The name for the new drive. If not specified, uses auto-generated name.

    .PARAMETER SizeGB
        The size of the drive in gigabytes. Required for disk media type.

    .PARAMETER Interface
        The drive interface type. Default is 'virtio-scsi'.
        Valid values: virtio, ide, ahci, nvme, virtio-scsi, virtio-scsi-dedicated

    .PARAMETER Media
        The media type. Default is 'disk'.
        Valid values: disk, cdrom, efidisk

    .PARAMETER Tier
        The preferred storage tier (1-5). Default is determined by system.

    .PARAMETER Description
        An optional description for the drive.

    .PARAMETER ReadOnly
        Make the drive read-only.

    .PARAMETER Disabled
        Create the drive in disabled state.

    .PARAMETER PassThru
        Return the created drive object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeDrive -VMName "WebServer01" -SizeGB 100

        Adds a 100GB disk to the VM using default settings.

    .EXAMPLE
        New-VergeDrive -VMName "WebServer01" -Name "DataDisk" -SizeGB 500 -Tier 2

        Adds a 500GB disk on tier 2 storage with a custom name.

    .EXAMPLE
        Get-VergeVM -Name "Database*" | New-VergeDrive -SizeGB 200 -Interface nvme

        Adds a 200GB NVMe disk to all database VMs.

    .EXAMPLE
        New-VergeDrive -VMName "WebServer01" -Media cdrom -Name "ISO"

        Adds a CD-ROM drive to the VM.

    .OUTPUTS
        None by default. Verge.Drive when -PassThru is specified.

    .NOTES
        The VM should be powered off when adding drives for best results,
        though hot-add may be supported depending on configuration.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByVMName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByVMObject')]
        [PSTypeName('Verge.VM')]
        [PSCustomObject]$VM,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByVMName')]
        [string]$VMName,

        [Parameter(Mandatory, ParameterSetName = 'ByVMKey')]
        [int]$VMKey,

        [Parameter()]
        [ValidateLength(1, 128)]
        [string]$Name,

        [Parameter()]
        [ValidateRange(1, 65536)]
        [int]$SizeGB,

        [Parameter()]
        [ValidateSet('virtio', 'ide', 'ahci', 'nvme', 'virtio-scsi', 'virtio-scsi-dedicated')]
        [string]$Interface = 'virtio-scsi',

        [Parameter()]
        [ValidateSet('disk', 'cdrom', 'efidisk')]
        [string]$Media = 'disk',

        [Parameter()]
        [ValidateRange(1, 5)]
        [int]$Tier,

        [Parameter()]
        [ValidateLength(0, 2048)]
        [string]$Description,

        [Parameter()]
        [switch]$ReadOnly,

        [Parameter()]
        [switch]$Disabled,

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
            if (-not $targetVM) {
                continue
            }

            # Check if VM is a snapshot
            if ($targetVM.IsSnapshot) {
                Write-Error -Message "Cannot add drive to '$($targetVM.Name)': VM is a snapshot" -ErrorId 'CannotModifySnapshot'
                continue
            }

            # Validate SizeGB for disk media
            if ($Media -eq 'disk' -and -not $SizeGB) {
                Write-Error -Message "SizeGB is required when Media is 'disk'" -ErrorId 'SizeRequired'
                continue
            }

            # Auto-detect CDROM interface based on VM machine type if not explicitly specified
            $effectiveInterface = $Interface
            if ($Media -eq 'cdrom' -and -not $PSBoundParameters.ContainsKey('Interface')) {
                # Q35 chipset requires AHCI, i440FX requires IDE
                if ($targetVM.IsQ35) {
                    $effectiveInterface = 'ahci'
                    Write-Verbose "Auto-selected 'ahci' interface for CDROM (Q35 chipset)"
                }
                else {
                    $effectiveInterface = 'ide'
                    Write-Verbose "Auto-selected 'ide' interface for CDROM (i440FX chipset)"
                }
            }

            # Build request body
            $body = @{
                machine   = $targetVM.MachineKey
                interface = $effectiveInterface
                media     = $Media
                enabled   = -not $Disabled.IsPresent
            }

            if ($Name) {
                $body['name'] = $Name
            }

            if ($SizeGB -and $Media -eq 'disk') {
                # Convert GB to bytes
                $body['disksize'] = [int64]$SizeGB * 1073741824
            }

            if ($Tier) {
                $body['preferred_tier'] = $Tier.ToString()
            }

            if ($Description) {
                $body['description'] = $Description
            }

            if ($ReadOnly) {
                $body['readonly'] = $true
            }

            $driveDesc = if ($Name) { $Name } else { "$Media drive" }
            $sizeDesc = if ($SizeGB) { " (${SizeGB}GB)" } else { '' }

            if ($PSCmdlet.ShouldProcess($targetVM.Name, "Add $driveDesc$sizeDesc")) {
                try {
                    Write-Verbose "Adding $Media drive to VM '$($targetVM.Name)'"
                    $response = Invoke-VergeAPI -Method POST -Endpoint 'machine_drives' -Body $body -Connection $Server

                    if ($response) {
                        Write-Verbose "Drive added successfully with key: $($response.'$key' ?? $response.key ?? 'unknown')"

                        if ($PassThru) {
                            # Return the drive using Get-VergeDrive
                            $driveKey = $response.'$key' ?? $response.key
                            if ($driveKey) {
                                Get-VergeDrive -VM $targetVM -Server $Server | Where-Object { $_.Key -eq $driveKey }
                            }
                        }
                    }
                }
                catch {
                    Write-Error -Message "Failed to add drive to VM '$($targetVM.Name)': $($_.Exception.Message)" -ErrorId 'DriveAddFailed'
                }
            }
        }
    }
}
