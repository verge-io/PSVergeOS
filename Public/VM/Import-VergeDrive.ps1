function Import-VergeDrive {
    <#
    .SYNOPSIS
        Imports a disk image file as a new drive on a VergeOS virtual machine.

    .DESCRIPTION
        Import-VergeDrive creates a new drive on a VM by importing from a disk image
        file (VMDK, QCOW2, VHD, VHDX, OVA, OVF, etc.). The file must already be
        uploaded to the VergeOS media catalog.

        This is the recommended way to import VMs from OVA/OVF/VMDK files:
        1. Create a new VM with New-VergeVM
        2. Import the disk(s) with Import-VergeDrive

    .PARAMETER VM
        A VM object from Get-VergeVM. Accepts pipeline input.

    .PARAMETER VMName
        The name of the VM to add the imported drive to.

    .PARAMETER VMKey
        The key (ID) of the VM to add the imported drive to.

    .PARAMETER FileKey
        The key (ID) of the disk image file to import.

    .PARAMETER FileName
        The name of the disk image file to import.

    .PARAMETER File
        A file object from Get-VergeFile.

    .PARAMETER Name
        The name for the new drive. If not specified, uses auto-generated name.

    .PARAMETER Interface
        The drive interface type. Default is 'virtio-scsi'.
        Valid values: virtio, ide, ahci, nvme, virtio-scsi, virtio-scsi-dedicated

    .PARAMETER Tier
        The preferred storage tier (1-5).

    .PARAMETER PreserveDriveFormat
        Keep the original drive format instead of converting to raw. Default is false.

    .PARAMETER PassThru
        Return the created drive object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Import-VergeDrive -VMName "NewServer" -FileName "debian-12-generic-amd64.qcow2"

        Imports a QCOW2 disk image to the VM.

    .EXAMPLE
        $vm = New-VergeVM -Name "ImportedVM" -CPUCores 2 -RAM 4096 -OSFamily Linux -PassThru
        Import-VergeDrive -VM $vm -FileName "server-disk.vmdk" -Interface virtio-scsi

        Creates a VM and imports a VMDK disk.

    .EXAMPLE
        Get-VergeFile -Type qcow2 -Name "*debian*" | Import-VergeDrive -VMName "DebianServer"

        Imports all matching QCOW2 files as drives.

    .OUTPUTS
        None by default. Verge.Drive when -PassThru is specified.

    .NOTES
        Supported import formats: VMDK, QCOW2, VHD, VHDX, VDI, RAW, OVA, OVF
        The import process converts the disk to VergeOS format unless
        -PreserveDriveFormat is specified.
        Use Get-VergeFile -Type vmdk,qcow2,vhd,vhdx,ova,ovf to see importable files.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByVMNameFileName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByVMFileName')]
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByVMFileKey')]
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByVMFile')]
        [PSTypeName('Verge.VM')]
        [PSCustomObject]$VM,

        [Parameter(Mandatory, ParameterSetName = 'ByVMNameFileName')]
        [Parameter(Mandatory, ParameterSetName = 'ByVMNameFileKey')]
        [Parameter(Mandatory, ParameterSetName = 'ByVMNameFile')]
        [string]$VMName,

        [Parameter(Mandatory, ParameterSetName = 'ByVMKeyFileName')]
        [Parameter(Mandatory, ParameterSetName = 'ByVMKeyFileKey')]
        [Parameter(Mandatory, ParameterSetName = 'ByVMKeyFile')]
        [int]$VMKey,

        [Parameter(Mandatory, ParameterSetName = 'ByVMNameFileKey')]
        [Parameter(Mandatory, ParameterSetName = 'ByVMKeyFileKey')]
        [Parameter(Mandatory, ParameterSetName = 'ByVMFileKey')]
        [int]$FileKey,

        [Parameter(Mandatory, Position = 1, ParameterSetName = 'ByVMNameFileName')]
        [Parameter(Mandatory, Position = 1, ParameterSetName = 'ByVMKeyFileName')]
        [Parameter(Mandatory, Position = 1, ParameterSetName = 'ByVMFileName')]
        [string]$FileName,

        [Parameter(Mandatory, ParameterSetName = 'ByVMNameFile')]
        [Parameter(Mandatory, ParameterSetName = 'ByVMKeyFile')]
        [Parameter(Mandatory, ParameterSetName = 'ByVMFile')]
        [PSTypeName('Verge.File')]
        [PSCustomObject]$File,

        [Parameter()]
        [ValidateLength(1, 128)]
        [string]$Name,

        [Parameter()]
        [ValidateSet('virtio', 'ide', 'ahci', 'nvme', 'virtio-scsi', 'virtio-scsi-dedicated')]
        [string]$Interface = 'virtio-scsi',

        [Parameter()]
        [ValidateRange(1, 5)]
        [int]$Tier,

        [Parameter()]
        [switch]$PreserveDriveFormat,

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
        # Resolve VM
        $targetVM = switch -Wildcard ($PSCmdlet.ParameterSetName) {
            'ByVMName*' {
                Get-VergeVM -Name $VMName -Server $Server | Select-Object -First 1
            }
            'ByVMKey*' {
                Get-VergeVM -Key $VMKey -Server $Server
            }
            'ByVM*' {
                $VM
            }
        }

        if (-not $targetVM) {
            Write-Error -Message "VM not found" -ErrorId 'VMNotFound'
            return
        }

        if ($targetVM.IsSnapshot) {
            Write-Error -Message "Cannot import drive to '$($targetVM.Name)': VM is a snapshot" -ErrorId 'CannotModifySnapshot'
            return
        }

        # Resolve file
        $targetFileKey = $null
        $targetFileName = $null

        switch -Wildcard ($PSCmdlet.ParameterSetName) {
            '*FileKey' {
                $targetFileKey = $FileKey
                try {
                    $fileInfo = Get-VergeFile -Key $FileKey -Server $Server
                    $targetFileName = $fileInfo.Name
                }
                catch {
                    $targetFileName = "File $FileKey"
                }
            }
            '*FileName' {
                $fileInfo = Get-VergeFile -Name $FileName -Server $Server | Select-Object -First 1
                if (-not $fileInfo) {
                    Write-Error -Message "File '$FileName' not found in media catalog" -ErrorId 'FileNotFound'
                    return
                }
                $targetFileKey = $fileInfo.Key
                $targetFileName = $fileInfo.Name
            }
            '*File' {
                $targetFileKey = $File.Key
                $targetFileName = $File.Name
            }
        }

        if (-not $targetFileKey) {
            Write-Error -Message "Could not resolve file for import" -ErrorId 'FileNotResolved'
            return
        }

        # Build request body for import drive
        $body = @{
            machine              = $targetVM.MachineKey
            interface            = $Interface
            media                = 'import'
            media_source         = $targetFileKey
            enabled              = $true
            preserve_drive_format = $PreserveDriveFormat.IsPresent
        }

        if ($Name) {
            $body['name'] = $Name
        }

        if ($Tier) {
            $body['preferred_tier'] = $Tier.ToString()
        }

        $driveName = if ($Name) { $Name } else { $targetFileName }

        if ($PSCmdlet.ShouldProcess($targetVM.Name, "Import drive from '$targetFileName'")) {
            try {
                Write-Verbose "Importing '$targetFileName' as drive to VM '$($targetVM.Name)'"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'machine_drives' -Body $body -Connection $Server

                if ($response) {
                    $driveKey = $response.'$key' ?? $response.key
                    Write-Verbose "Drive import initiated with key: $driveKey"

                    if ($PassThru -and $driveKey) {
                        # Wait briefly for drive to be created
                        Start-Sleep -Seconds 2
                        Get-VergeDrive -VM $targetVM -Server $Server | Where-Object { $_.Key -eq $driveKey }
                    }
                }
            }
            catch {
                Write-Error -Message "Failed to import drive to VM '$($targetVM.Name)': $($_.Exception.Message)" -ErrorId 'DriveImportFailed'
            }
        }
    }
}
