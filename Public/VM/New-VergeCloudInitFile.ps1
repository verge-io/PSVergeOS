function New-VergeCloudInitFile {
    <#
    .SYNOPSIS
        Creates a new cloud-init file in VergeOS.

    .DESCRIPTION
        New-VergeCloudInitFile creates a new cloud-init file in VergeOS for VM provisioning.
        Cloud-init files are used to provide user-data, meta-data, network-config, and
        other configuration to VMs during boot.

    .PARAMETER VMId
        The ID (key) of the VM that this cloud-init file belongs to.
        Cloud-init files are associated with specific VMs for provisioning.

    .PARAMETER VM
        A VM object from Get-VergeVM. Can be used instead of VMId.

    .PARAMETER Name
        The name of the cloud-init file. This should typically start with a forward slash
        (e.g., /user-data, /meta-data, /network-config).

    .PARAMETER Contents
        The contents of the cloud-init file. Maximum size is 65536 bytes (64KB).
        Can be provided as a string or read from a file using Get-Content -Raw.

    .PARAMETER Render
        Specifies how the file should be rendered during VM provisioning:
        - No: File is used as-is without any processing (default)
        - Variables: File supports VergeOS variable substitution
        - Jinja2: File is processed as a Jinja2 template

    .PARAMETER PassThru
        Return the created cloud-init file object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeCloudInitFile -VMId 123 -Name "/user-data" -Contents $userData

        Creates a simple user-data file for VM 123 without variable processing.

    .EXAMPLE
        $vm = Get-VergeVM -Name "myvm"
        $userData = Get-Content ./user-data.yaml -Raw
        New-VergeCloudInitFile -VM $vm -Name "/user-data" -Contents $userData -Render Jinja2 -PassThru

        Creates a user-data file with Jinja2 template rendering for a VM and returns the created object.

    .EXAMPLE
        Get-VergeVM -Name "myvm" | New-VergeCloudInitFile -Name "/meta-data" -Contents "instance-id: {{vm_name}}" -Render Variables

        Creates a meta-data file with VergeOS variable substitution using pipeline input.

    .OUTPUTS
        None by default. Verge.CloudInitFile when -PassThru is specified.

    .NOTES
        Cloud-init files have a maximum size of 65536 bytes (64KB).

        Common cloud-init file names:
        - /user-data: User configuration (packages, users, scripts)
        - /meta-data: Instance metadata (instance-id, hostname)
        - /network-config: Network configuration
        - /vendor-data: Vendor-specific configuration
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByVMId')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByVMId')]
        [int]$VMId,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByVM')]
        [PSTypeName('Verge.VM')]
        [PSCustomObject]$VM,

        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [ValidateLength(1, 256)]
        [string]$Name,

        [Parameter(Position = 1)]
        [ValidateScript({
            if ($_.Length -gt 65536) {
                throw "Contents exceed maximum size of 65536 bytes (64KB). Current size: $($_.Length) bytes."
            }
            $true
        })]
        [string]$Contents,

        [Parameter()]
        [ValidateSet('No', 'Variables', 'Jinja2')]
        [string]$Render = 'No',

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
        # Resolve VM ID
        $targetVMId = switch ($PSCmdlet.ParameterSetName) {
            'ByVMId' { $VMId }
            'ByVM' { $VM.Key }
        }

        if (-not $targetVMId) {
            throw "Unable to determine VM ID. Provide either -VMId or -VM parameter."
        }

        # Build request body
        $body = @{
            name   = $Name
            render = $renderMapping[$Render]
            owner  = "vms/$targetVMId"
        }

        # Add contents if provided
        if ($Contents) {
            $body['contents'] = $Contents
        }

        # Determine display info for confirmation
        $renderDisplay = $Render
        $sizeInfo = if ($Contents) { "$($Contents.Length) bytes" } else { "empty" }

        if ($PSCmdlet.ShouldProcess("$Name for VM $targetVMId ($sizeInfo, Render: $renderDisplay)", 'Create CloudInit File')) {
            try {
                Write-Verbose "Creating cloud-init file '$Name' for VM $targetVMId with render type '$renderDisplay'"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'cloudinit_files' -Body $body -Connection $Server

                # Get the created file key
                $fileKey = $response.'$key'
                if (-not $fileKey -and $response.key) {
                    $fileKey = $response.key
                }

                Write-Verbose "Cloud-init file created with Key: $fileKey"

                if ($PassThru -and $fileKey) {
                    # Return the created file
                    Start-Sleep -Milliseconds 500
                    Get-VergeCloudInitFile -Key $fileKey -Server $Server
                }
            }
            catch {
                $errorMessage = $_.Exception.Message
                if ($errorMessage -match 'already exists' -or $errorMessage -match 'duplicate') {
                    throw "A cloud-init file named '$Name' already exists."
                }
                throw "Failed to create cloud-init file '$Name': $errorMessage"
            }
        }
    }
}
