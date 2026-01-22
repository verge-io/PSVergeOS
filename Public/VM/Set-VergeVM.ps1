function Set-VergeVM {
    <#
    .SYNOPSIS
        Modifies the configuration of a VergeOS virtual machine.

    .DESCRIPTION
        Set-VergeVM modifies VM settings such as CPU cores, RAM, description,
        and other configuration options. Some changes may require a VM restart
        to take effect.

    .PARAMETER VM
        A VM object from Get-VergeVM. Accepts pipeline input.

    .PARAMETER Name
        The name of the VM to modify.

    .PARAMETER Key
        The key (ID) of the VM to modify.

    .PARAMETER NewName
        Rename the VM to this new name.

    .PARAMETER Description
        Set the VM description.

    .PARAMETER CPUCores
        Set the number of CPU cores (1-1024).

    .PARAMETER RAM
        Set the amount of RAM in MB (256-1048576).

    .PARAMETER OSFamily
        Set the operating system family: Linux, Windows, FreeBSD, Other.

    .PARAMETER GuestAgent
        Enable or disable QEMU Guest Agent support.

    .PARAMETER UEFI
        Enable or disable UEFI boot.

    .PARAMETER SecureBoot
        Enable or disable Secure Boot (requires UEFI).

    .PARAMETER Enabled
        Enable or disable the VM.

    .PARAMETER Console
        Set the console type: VNC, Spice, Serial, None.

    .PARAMETER Video
        Set the video card type: Standard, Cirrus, VMware, QXL, Virtio, None.

    .PARAMETER BootOrder
        Set the boot device order.

    .PARAMETER BootDelay
        Set the boot delay in seconds (0-60).

    .PARAMETER PassThru
        Return the modified VM object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Set-VergeVM -Name "WebServer01" -CPUCores 8 -RAM 16384

        Increases CPU to 8 cores and RAM to 16GB.

    .EXAMPLE
        Get-VergeVM -Name "WebServer01" | Set-VergeVM -Description "Production web server"

        Sets the VM description using pipeline input.

    .EXAMPLE
        Set-VergeVM -Name "OldName" -NewName "NewName" -PassThru

        Renames a VM and returns the updated object.

    .EXAMPLE
        Get-VergeVM -Name "Dev-*" | Set-VergeVM -GuestAgent $true

        Enables guest agent on all development VMs.

    .EXAMPLE
        Set-VergeVM -Name "WebServer01" -UEFI $true -SecureBoot $true

        Enables UEFI and Secure Boot (requires VM restart).

    .OUTPUTS
        None by default. Verge.VM when -PassThru is specified.

    .NOTES
        Some changes (CPU, RAM, UEFI) may require the VM to be powered off
        or restarted to take effect. The VM will show 'Restart Needed' status.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByVM')]
        [PSTypeName('Verge.VM')]
        [PSCustomObject]$VM,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter()]
        [ValidateLength(1, 128)]
        [string]$NewName,

        [Parameter()]
        [ValidateLength(0, 2048)]
        [string]$Description,

        [Parameter()]
        [ValidateRange(1, 1024)]
        [int]$CPUCores,

        [Parameter()]
        [ValidateRange(256, 1048576)]
        [int]$RAM,

        [Parameter()]
        [ValidateSet('Linux', 'Windows', 'FreeBSD', 'Other')]
        [string]$OSFamily,

        [Parameter()]
        [bool]$GuestAgent,

        [Parameter()]
        [bool]$UEFI,

        [Parameter()]
        [bool]$SecureBoot,

        [Parameter()]
        [bool]$Enabled,

        [Parameter()]
        [ValidateSet('VNC', 'Spice', 'Serial', 'None')]
        [string]$Console,

        [Parameter()]
        [ValidateSet('Standard', 'Cirrus', 'VMware', 'QXL', 'Virtio', 'None')]
        [string]$Video,

        [Parameter()]
        [ValidateSet('DiskCD', 'DiskCDNetwork', 'CDDisk', 'NetworkDisk', 'Network', 'Disk', 'CD')]
        [string]$BootOrder,

        [Parameter()]
        [ValidateRange(0, 60)]
        [int]$BootDelay,

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

        # Map friendly names to API values
        $osFamilyMap = @{
            'Linux'   = 'linux'
            'Windows' = 'windows'
            'FreeBSD' = 'freebsd'
            'Other'   = 'other'
        }

        $consoleMap = @{
            'VNC'    = 'vnc'
            'Spice'  = 'spice'
            'Serial' = 'serial'
            'None'   = 'none'
        }

        $videoMap = @{
            'Standard' = 'std'
            'Cirrus'   = 'cirrus'
            'VMware'   = 'vmware'
            'QXL'      = 'qxl'
            'Virtio'   = 'virtio'
            'None'     = 'none'
        }

        $bootOrderMap = @{
            'DiskCD'        = 'cd'
            'DiskCDNetwork' = 'cdn'
            'CDDisk'        = 'dc'
            'NetworkDisk'   = 'nc'
            'Network'       = 'n'
            'Disk'          = 'c'
            'CD'            = 'd'
        }
    }

    process {
        # Resolve VM based on parameter set
        $targetVM = switch ($PSCmdlet.ParameterSetName) {
            'ByName' {
                Get-VergeVM -Name $Name -Server $Server | Select-Object -First 1
            }
            'ByKey' {
                Get-VergeVM -Key $Key -Server $Server
            }
            'ByVM' {
                $VM
            }
        }

        if (-not $targetVM) {
            Write-Error -Message "VM not found" -ErrorId 'VMNotFound'
            return
        }

        # Check if VM is a snapshot
        if ($targetVM.IsSnapshot) {
            Write-Error -Message "Cannot modify '$($targetVM.Name)': VM is a snapshot" -ErrorId 'CannotModifySnapshot'
            return
        }

        # Build the update body with only specified parameters
        $body = @{}
        $changes = [System.Collections.Generic.List[string]]::new()

        if ($PSBoundParameters.ContainsKey('NewName')) {
            $body['name'] = $NewName
            $changes.Add("Name: $($targetVM.Name) -> $NewName")
        }

        if ($PSBoundParameters.ContainsKey('Description')) {
            $body['description'] = $Description
            $changes.Add("Description updated")
        }

        if ($PSBoundParameters.ContainsKey('CPUCores')) {
            $body['cpu_cores'] = $CPUCores
            $changes.Add("CPU: $($targetVM.CPUCores) -> $CPUCores")
        }

        if ($PSBoundParameters.ContainsKey('RAM')) {
            # Normalize RAM to 256 MB increments
            $normalizedRAM = [Math]::Ceiling($RAM / 256) * 256
            $body['ram'] = $normalizedRAM
            $changes.Add("RAM: $($targetVM.RAM)MB -> ${normalizedRAM}MB")
        }

        if ($PSBoundParameters.ContainsKey('OSFamily')) {
            $body['os_family'] = $osFamilyMap[$OSFamily]
            $changes.Add("OS Family: $OSFamily")
        }

        if ($PSBoundParameters.ContainsKey('GuestAgent')) {
            $body['guest_agent'] = $GuestAgent
            $changes.Add("Guest Agent: $GuestAgent")
        }

        if ($PSBoundParameters.ContainsKey('UEFI')) {
            $body['uefi'] = $UEFI
            $changes.Add("UEFI: $UEFI")
        }

        if ($PSBoundParameters.ContainsKey('SecureBoot')) {
            $body['secure_boot'] = $SecureBoot
            $changes.Add("Secure Boot: $SecureBoot")
            if ($SecureBoot -and -not $UEFI -and -not $targetVM.UEFI) {
                Write-Warning "Secure Boot requires UEFI. Consider enabling UEFI as well."
            }
        }

        if ($PSBoundParameters.ContainsKey('Enabled')) {
            $body['enabled'] = $Enabled
            $changes.Add("Enabled: $Enabled")
        }

        if ($PSBoundParameters.ContainsKey('Console')) {
            $body['console'] = $consoleMap[$Console]
            $changes.Add("Console: $Console")
        }

        if ($PSBoundParameters.ContainsKey('Video')) {
            $body['video'] = $videoMap[$Video]
            $changes.Add("Video: $Video")
        }

        if ($PSBoundParameters.ContainsKey('BootOrder')) {
            $body['boot_order'] = $bootOrderMap[$BootOrder]
            $changes.Add("Boot Order: $BootOrder")
        }

        if ($PSBoundParameters.ContainsKey('BootDelay')) {
            $body['boot_delay'] = $BootDelay
            $changes.Add("Boot Delay: ${BootDelay}s")
        }

        # Check if there are any changes to make
        if ($body.Count -eq 0) {
            Write-Warning "No changes specified for VM '$($targetVM.Name)'"
            if ($PassThru) {
                Write-Output $targetVM
            }
            return
        }

        # Build change summary for confirmation
        $changeSummary = $changes -join ', '

        if ($PSCmdlet.ShouldProcess($targetVM.Name, "Modify VM ($changeSummary)")) {
            try {
                Write-Verbose "Modifying VM '$($targetVM.Name)' (Key: $($targetVM.Key))"
                Write-Verbose "Changes: $changeSummary"

                $response = Invoke-VergeAPI -Method PUT -Endpoint "vms/$($targetVM.Key)" -Body $body -Connection $Server

                Write-Verbose "VM '$($targetVM.Name)' modified successfully"

                if ($PassThru) {
                    # Return the updated VM
                    Start-Sleep -Milliseconds 500
                    $vmKey = if ($PSBoundParameters.ContainsKey('NewName')) {
                        # If renamed, we need to fetch by the new name or original key
                        $targetVM.Key
                    } else {
                        $targetVM.Key
                    }
                    Get-VergeVM -Key $vmKey -Server $Server
                }
            }
            catch {
                Write-Error -Message "Failed to modify VM '$($targetVM.Name)': $($_.Exception.Message)" -ErrorId 'VMModifyFailed'
            }
        }
    }
}
