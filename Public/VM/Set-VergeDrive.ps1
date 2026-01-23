function Set-VergeDrive {
    <#
    .SYNOPSIS
        Modifies a VergeOS virtual machine drive configuration.

    .DESCRIPTION
        Set-VergeDrive updates the configuration of an existing VM drive.
        Can change size (grow only), tier, interface, and other settings.

    .PARAMETER Drive
        A drive object from Get-VergeDrive. Accepts pipeline input.

    .PARAMETER Key
        The key (ID) of the drive to modify.

    .PARAMETER Name
        The new name for the drive.

    .PARAMETER SizeGB
        The new size in gigabytes. Can only grow, not shrink.

    .PARAMETER Interface
        The drive interface type.
        Valid values: virtio, ide, ahci, nvme, virtio-scsi, virtio-scsi-dedicated

    .PARAMETER Tier
        The preferred storage tier (1-5).

    .PARAMETER Description
        The description for the drive.

    .PARAMETER ReadOnly
        Set the drive to read-only or read-write.

    .PARAMETER Enabled
        Enable or disable the drive.

    .PARAMETER MediaSource
        The media source file key (for CD-ROM drives to mount ISO).

    .PARAMETER PassThru
        Return the modified drive object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeDrive -VMName "WebServer01" -Name "DataDisk" | Set-VergeDrive -SizeGB 200

        Grows the DataDisk to 200GB.

    .EXAMPLE
        Set-VergeDrive -Key 123 -Tier 1 -PassThru

        Moves the drive to tier 1 storage and returns the updated object.

    .EXAMPLE
        Get-VergeDrive -VMName "WebServer01" | Where-Object { $_.Media -eq 'cdrom' } | Set-VergeDrive -MediaSource 456

        Mounts an ISO file to the CD-ROM drive.

    .EXAMPLE
        Get-VergeDrive -VMName "WebServer01" -Name "OldDisk" | Set-VergeDrive -Enabled $false

        Disables the drive.

    .OUTPUTS
        None by default. Verge.Drive when -PassThru is specified.

    .NOTES
        Disk size can only be increased, not decreased.
        Some changes may require the VM to be powered off.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByDrive')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByDrive')]
        [PSTypeName('Verge.Drive')]
        [PSCustomObject]$Drive,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter()]
        [ValidateLength(1, 128)]
        [string]$Name,

        [Parameter()]
        [ValidateRange(1, 65536)]
        [int]$SizeGB,

        [Parameter()]
        [ValidateSet('virtio', 'ide', 'ahci', 'nvme', 'virtio-scsi', 'virtio-scsi-dedicated')]
        [string]$Interface,

        [Parameter()]
        [ValidateRange(1, 5)]
        [ValidateScript({
            if ($_ -eq 0) {
                throw "Tier 0 is reserved for system metadata and cannot be used for VM drives."
            }
            $true
        })]
        [int]$Tier,

        [Parameter()]
        [ValidateLength(0, 2048)]
        [string]$Description,

        [Parameter()]
        [Nullable[bool]]$ReadOnly,

        [Parameter()]
        [Nullable[bool]]$Enabled,

        [Parameter()]
        [int]$MediaSource,

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
        # Resolve drive key
        $driveKey = switch ($PSCmdlet.ParameterSetName) {
            'ByDrive' { $Drive.Key }
            'ByKey' { $Key }
        }

        $driveName = if ($Drive) { $Drive.Name } else { "Key $driveKey" }
        $vmName = if ($Drive -and $Drive.VMName) { $Drive.VMName } else { 'Unknown' }

        # Build update body with only changed properties
        $body = @{}

        if ($PSBoundParameters.ContainsKey('Name')) {
            $body['name'] = $Name
        }

        if ($PSBoundParameters.ContainsKey('SizeGB')) {
            $body['disksize'] = [int64]$SizeGB * 1073741824
        }

        if ($PSBoundParameters.ContainsKey('Interface')) {
            $body['interface'] = $Interface
        }

        if ($PSBoundParameters.ContainsKey('Tier')) {
            $body['preferred_tier'] = $Tier.ToString()
        }

        if ($PSBoundParameters.ContainsKey('Description')) {
            $body['description'] = $Description
        }

        if ($PSBoundParameters.ContainsKey('ReadOnly')) {
            $body['readonly'] = $ReadOnly
        }

        if ($PSBoundParameters.ContainsKey('Enabled')) {
            $body['enabled'] = $Enabled
        }

        if ($PSBoundParameters.ContainsKey('MediaSource')) {
            $body['media_source'] = $MediaSource
        }

        if ($body.Count -eq 0) {
            Write-Warning "No changes specified for drive '$driveName'"
            return
        }

        $changes = ($body.Keys | ForEach-Object { $_ }) -join ', '

        if ($PSCmdlet.ShouldProcess("$driveName (VM: $vmName)", "Modify drive ($changes)")) {
            try {
                Write-Verbose "Modifying drive '$driveName' (Key: $driveKey)"
                $response = Invoke-VergeAPI -Method PUT -Endpoint "machine_drives/$driveKey" -Body $body -Connection $Server

                Write-Verbose "Drive '$driveName' modified successfully"

                if ($PassThru) {
                    # Return updated drive
                    $driveResponse = Invoke-VergeAPI -Method GET -Endpoint "machine_drives/$driveKey" -Connection $Server
                    if ($driveResponse) {
                        # Handle null/zero sizes gracefully (CDROM drives have no disksize)
                        # Use unique variable names to avoid parameter validation conflicts
                        $outputSizeBytes = if ($null -ne $driveResponse.disksize) { [long]$driveResponse.disksize } else { [long]0 }
                        $outputSizeGigabytes = if ($outputSizeBytes -gt 0) { [math]::Round($outputSizeBytes / 1073741824, 2) } else { [double]0 }

                        # Build output object
                        $output = New-Object PSObject
                        $output.PSObject.TypeNames.Insert(0, 'Verge.Drive')
                        $output | Add-Member -NotePropertyName Key -NotePropertyValue ($driveResponse.'$key' ?? $driveKey)
                        $output | Add-Member -NotePropertyName Name -NotePropertyValue $driveResponse.name
                        $output | Add-Member -NotePropertyName Interface -NotePropertyValue $driveResponse.interface
                        $output | Add-Member -NotePropertyName Media -NotePropertyValue $driveResponse.media
                        $output | Add-Member -NotePropertyName SizeGB -NotePropertyValue $outputSizeGigabytes
                        $output | Add-Member -NotePropertyName SizeBytes -NotePropertyValue $outputSizeBytes
                        $output | Add-Member -NotePropertyName Tier -NotePropertyValue $driveResponse.preferred_tier
                        $output | Add-Member -NotePropertyName Enabled -NotePropertyValue $driveResponse.enabled
                        $output | Add-Member -NotePropertyName ReadOnly -NotePropertyValue $driveResponse.readonly
                        $output | Add-Member -NotePropertyName Description -NotePropertyValue $driveResponse.description
                        $output | Add-Member -NotePropertyName MachineKey -NotePropertyValue $driveResponse.machine
                        $output | Add-Member -NotePropertyName MediaSource -NotePropertyValue $driveResponse.media_source
                        $output | Add-Member -NotePropertyName OrderId -NotePropertyValue $driveResponse.orderid
                        Write-Output $output
                    }
                }
            }
            catch {
                Write-Error -Message "Failed to modify drive '$driveName': $($_.Exception.Message)" -ErrorId 'DriveModifyFailed'
            }
        }
    }
}
