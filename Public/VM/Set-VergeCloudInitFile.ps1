function Set-VergeCloudInitFile {
    <#
    .SYNOPSIS
        Modifies an existing cloud-init file in VergeOS.

    .DESCRIPTION
        Set-VergeCloudInitFile modifies the properties of an existing cloud-init file,
        including its name, contents, and render type.

    .PARAMETER CloudInitFile
        A cloud-init file object from Get-VergeCloudInitFile. Accepts pipeline input.

    .PARAMETER Key
        The key (ID) of the cloud-init file to modify.

    .PARAMETER Name
        Set a new name for the cloud-init file.

    .PARAMETER Contents
        Set new contents for the cloud-init file. Maximum size is 65536 bytes (64KB).

    .PARAMETER Render
        Set how the file should be rendered during VM provisioning:
        - No: File is used as-is without any processing
        - Variables: File supports VergeOS variable substitution
        - Jinja2: File is processed as a Jinja2 template

    .PARAMETER PassThru
        Return the modified cloud-init file object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Set-VergeCloudInitFile -Key 27 -Contents $newContents

        Updates the contents of cloud-init file 27.

    .EXAMPLE
        Get-VergeCloudInitFile -Key 27 | Set-VergeCloudInitFile -Render Variables -PassThru

        Changes a file's render type to Variables using pipeline input and returns the result.

    .EXAMPLE
        Set-VergeCloudInitFile -Key 27 -Name "/new-user-data" -Render Jinja2

        Renames a cloud-init file and changes its render type.

    .OUTPUTS
        None by default. Verge.CloudInitFile when -PassThru is specified.

    .NOTES
        Cloud-init files have a maximum size of 65536 bytes (64KB).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByKey')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByCloudInitFile')]
        [PSTypeName('Verge.CloudInitFile')]
        [PSCustomObject]$CloudInitFile,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter()]
        [ValidateLength(1, 256)]
        [string]$Name,

        [Parameter()]
        [ValidateScript({
            if ($_.Length -gt 65536) {
                throw "Contents exceed maximum size of 65536 bytes (64KB). Current size: $($_.Length) bytes."
            }
            $true
        })]
        [string]$Contents,

        [Parameter()]
        [ValidateSet('No', 'Variables', 'Jinja2')]
        [string]$Render,

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

        # Map friendly render names to API values
        $renderMapping = @{
            'No'        = 'no'
            'Variables' = 'variables'
            'Jinja2'    = 'jinja2'
        }
    }

    process {
        # Resolve cloud-init file based on parameter set
        $targetFile = switch ($PSCmdlet.ParameterSetName) {
            'ByKey' {
                Get-VergeCloudInitFile -Key $Key -Server $Server
            }
            'ByCloudInitFile' {
                $CloudInitFile
            }
        }

        if (-not $targetFile) {
            Write-Error -Message "Cloud-init file not found" -ErrorId 'CloudInitFileNotFound'
            return
        }

        # Build the update body with only specified parameters
        $body = @{}
        $changes = [System.Collections.Generic.List[string]]::new()

        if ($PSBoundParameters.ContainsKey('Name')) {
            $body['name'] = $Name
            $changes.Add("Name: $Name")
        }

        if ($PSBoundParameters.ContainsKey('Contents')) {
            $body['contents'] = $Contents
            $changes.Add("Contents updated ($($Contents.Length) bytes)")
        }

        if ($PSBoundParameters.ContainsKey('Render')) {
            $body['render'] = $renderMapping[$Render]
            $changes.Add("Render: $Render")
        }

        # Check if there are any changes to make
        if ($body.Count -eq 0) {
            Write-Warning "No changes specified for cloud-init file '$($targetFile.Name)'"
            if ($PassThru) {
                Write-Output $targetFile
            }
            return
        }

        # Build change summary for confirmation
        $changeSummary = $changes -join ', '
        $fileDisplay = "$($targetFile.Name) (Key: $($targetFile.Key))"

        if ($PSCmdlet.ShouldProcess($fileDisplay, "Modify CloudInit File ($changeSummary)")) {
            try {
                Write-Verbose "Modifying cloud-init file '$($targetFile.Name)' (Key: $($targetFile.Key))"
                Write-Verbose "Changes: $changeSummary"

                $null = Invoke-VergeAPI -Method PUT -Endpoint "cloudinit_files/$($targetFile.Key)" -Body $body -Connection $Server

                Write-Verbose "Cloud-init file '$($targetFile.Name)' modified successfully"

                if ($PassThru) {
                    # Return the updated file
                    Start-Sleep -Milliseconds 500
                    Get-VergeCloudInitFile -Key $targetFile.Key -Server $Server
                }
            }
            catch {
                $errorMessage = $_.Exception.Message
                Write-Error -Message "Failed to modify cloud-init file '$($targetFile.Name)': $errorMessage" -ErrorId 'CloudInitFileModifyFailed'
            }
        }
    }
}
