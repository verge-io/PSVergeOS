function Import-VergeVM {
    <#
    .SYNOPSIS
        Imports a virtual machine from a VergeOS YBVM file.

    .DESCRIPTION
        Import-VergeVM creates a new VM by importing from a YBVM (VergeOS native VM)
        file. The file must already be uploaded to the VergeOS media catalog.

        For OVA/OVF/VMDK files, use New-VergeVM to create a VM, then use
        Import-VergeDrive to import the disk image as a drive.

    .PARAMETER FileKey
        The key (ID) of the YBVM file to import. Use Get-VergeFile -Type ybvm.

    .PARAMETER FileName
        The name of the YBVM file to import.

    .PARAMETER File
        A file object from Get-VergeFile. Accepts pipeline input.

    .PARAMETER Name
        The name for the new VM. If not specified, the name from the file is used.

    .PARAMETER PreserveMACAddresses
        Preserve the MAC addresses from the import file. Default is true.

    .PARAMETER PreserveDriveFormat
        Keep the original drive format instead of converting to raw. Default is false.

    .PARAMETER Tier
        The preferred storage tier (1-5) for the imported VM's drives.

    .PARAMETER Wait
        Wait for the import to complete before returning.

    .PARAMETER Timeout
        Maximum time in seconds to wait for import completion. Default is 600 (10 minutes).

    .PARAMETER PassThru
        Return the import job object (or VM object if -Wait is specified).

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Import-VergeVM -FileName "backup-webserver.ybvm" -Name "WebServer-Restored"

        Imports a YBVM file as a new VM.

    .EXAMPLE
        Get-VergeFile -Type ybvm | Import-VergeVM -Wait -PassThru

        Imports all YBVM files and waits for completion.

    .EXAMPLE
        Import-VergeVM -FileKey 123 -Tier 1 -Wait

        Imports a YBVM file to Tier 1 storage and waits for completion.

    .OUTPUTS
        Verge.VMImport object by default. Verge.VM when -Wait and -PassThru are specified.

    .NOTES
        This cmdlet imports YBVM (VergeOS native) files only.
        For OVA/OVF/VMDK imports, create a VM first with New-VergeVM, then use
        Import-VergeDrive to add the disk image.
        Use Get-VergeFile -Type ybvm to see importable VM files.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByFileName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByFileKey')]
        [int]$FileKey,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByFileName')]
        [string]$FileName,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByFile')]
        [PSTypeName('Verge.File')]
        [PSCustomObject]$File,

        [Parameter()]
        [ValidateLength(1, 128)]
        [string]$Name,

        [Parameter()]
        [bool]$PreserveMACAddresses = $true,

        [Parameter()]
        [switch]$PreserveDriveFormat,

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
        [switch]$Wait,

        [Parameter()]
        [ValidateRange(30, 3600)]
        [int]$Timeout = 600,

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
        # Resolve file key
        $targetFileKey = $null
        $targetFileName = $null
        $targetFileType = $null

        switch ($PSCmdlet.ParameterSetName) {
            'ByFileKey' {
                $targetFileKey = $FileKey
                try {
                    $fileInfo = Get-VergeFile -Key $FileKey -Server $Server
                    $targetFileName = $fileInfo.Name
                    $targetFileType = $fileInfo.Type
                }
                catch {
                    $targetFileName = "File $FileKey"
                }
            }
            'ByFileName' {
                $fileInfo = Get-VergeFile -Name $FileName -Server $Server | Select-Object -First 1
                if (-not $fileInfo) {
                    Write-Error -Message "File '$FileName' not found in media catalog" -ErrorId 'FileNotFound'
                    return
                }
                $targetFileKey = $fileInfo.Key
                $targetFileName = $fileInfo.Name
                $targetFileType = $fileInfo.Type
            }
            'ByFile' {
                $targetFileKey = $File.Key
                $targetFileName = $File.Name
                $targetFileType = $File.Type
            }
        }

        if (-not $targetFileKey) {
            Write-Error -Message "Could not resolve file for import" -ErrorId 'FileNotResolved'
            return
        }

        # Validate file type
        if ($targetFileType -and $targetFileType -ne 'ybvm') {
            Write-Error -Message "Import-VergeVM only supports YBVM files. File '$targetFileName' is type '$targetFileType'. For OVA/OVF/VMDK files, create a VM with New-VergeVM and use Import-VergeDrive to add the disk." -ErrorId 'InvalidFileType'
            return
        }

        # Build import request body
        $body = @{
            file                  = $targetFileKey
            preserve_macs         = $PreserveMACAddresses
            preserve_drive_format = $PreserveDriveFormat.IsPresent
        }

        if ($Name) {
            $body['name'] = $Name
        }

        if ($Tier) {
            $body['preferred_tier'] = $Tier.ToString()
        }

        $vmName = if ($Name) { $Name } else { $targetFileName }

        if ($PSCmdlet.ShouldProcess($targetFileName, "Import VM as '$vmName'")) {
            try {
                Write-Verbose "Starting import from '$targetFileName' (Key: $targetFileKey)"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'vm_imports' -Body $body -Connection $Server

                if (-not $response) {
                    Write-Error -Message "Failed to start import - no response from API" -ErrorId 'ImportStartFailed'
                    return
                }

                $importId = $response.id ?? $response.'$key'
                Write-Verbose "Import job created with ID: $importId"

                if ($Wait) {
                    Write-Verbose "Waiting for import to complete (timeout: ${Timeout}s)..."
                    $startTime = Get-Date
                    $lastStatus = ''

                    while ($true) {
                        Start-Sleep -Seconds 3

                        $importStatus = Invoke-VergeAPI -Method GET -Endpoint "vm_imports/$importId" -Connection $Server

                        if ($importStatus.status -ne $lastStatus) {
                            $lastStatus = $importStatus.status
                            Write-Verbose "Import status: $lastStatus - $($importStatus.status_info)"
                        }

                        if ($importStatus.status -eq 'complete') {
                            Write-Verbose "Import completed successfully"

                            if ($PassThru -and $importStatus.vm) {
                                Get-VergeVM -Key $importStatus.vm -Server $Server
                            }
                            elseif ($PassThru) {
                                [PSCustomObject]@{
                                    PSTypeName  = 'Verge.VMImport'
                                    Id          = $importId
                                    Name        = $importStatus.name
                                    Status      = $importStatus.status
                                    StatusInfo  = $importStatus.status_info
                                    VMKey       = $importStatus.vm
                                    FileKey     = $targetFileKey
                                    FileName    = $targetFileName
                                }
                            }
                            return
                        }

                        if ($importStatus.status -in @('error', 'aborted')) {
                            Write-Error -Message "Import failed: $($importStatus.status_info)" -ErrorId 'ImportFailed'
                            return
                        }

                        $elapsed = (Get-Date) - $startTime
                        if ($elapsed.TotalSeconds -ge $Timeout) {
                            Write-Warning "Import timed out after ${Timeout}s. Import may still be running."

                            if ($PassThru) {
                                [PSCustomObject]@{
                                    PSTypeName  = 'Verge.VMImport'
                                    Id          = $importId
                                    Name        = $importStatus.name
                                    Status      = $importStatus.status
                                    StatusInfo  = $importStatus.status_info
                                    VMKey       = $importStatus.vm
                                    FileKey     = $targetFileKey
                                    FileName    = $targetFileName
                                }
                            }
                            return
                        }
                    }
                }
                else {
                    if ($PassThru) {
                        [PSCustomObject]@{
                            PSTypeName  = 'Verge.VMImport'
                            Id          = $importId
                            Name        = $response.name ?? $vmName
                            Status      = $response.status ?? 'initializing'
                            StatusInfo  = $response.status_info
                            VMKey       = $response.vm
                            FileKey     = $targetFileKey
                            FileName    = $targetFileName
                        }
                    }
                    else {
                        Write-Verbose "Import started. Use -Wait to monitor progress."
                    }
                }
            }
            catch {
                Write-Error -Message "Failed to import VM from '$targetFileName': $($_.Exception.Message)" -ErrorId 'ImportFailed'
            }
        }
    }
}
