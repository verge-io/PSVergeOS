function New-VergeVMClone {
    <#
    .SYNOPSIS
        Creates a clone of a VergeOS virtual machine.

    .DESCRIPTION
        New-VergeVMClone creates an independent copy of an existing VM. The clone
        includes all drives and configuration. By default, new MAC addresses are
        assigned to network interfaces.

    .PARAMETER VM
        A VM object from Get-VergeVM. Accepts pipeline input.

    .PARAMETER VMName
        The name of the VM to clone.

    .PARAMETER VMKey
        The key (ID) of the VM to clone.

    .PARAMETER Name
        The name for the new cloned VM. If not specified, uses the format
        "{OriginalName}_{Timestamp}".

    .PARAMETER PreserveMACAddresses
        Keep the same MAC addresses as the source VM. Use with caution as
        this can cause network conflicts if both VMs are on the same network.

    .PARAMETER PowerOn
        Start the cloned VM immediately after creation.

    .PARAMETER PassThru
        Return the cloned VM object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeVMClone -VMName "Template-Ubuntu22" -Name "NewWebServer"

        Clones the template VM to create a new server.

    .EXAMPLE
        Get-VergeVM -Name "Template-*" | New-VergeVMClone

        Clones all template VMs using pipeline input.

    .EXAMPLE
        New-VergeVMClone -VMName "WebServer01" -Name "WebServer01-Test" -PowerOn -PassThru

        Clones a VM, starts it, and returns the new VM object.

    .EXAMPLE
        New-VergeVMClone -VMName "AppServer" -PreserveMACAddresses

        Clones with MAC addresses preserved (for offline testing).

    .OUTPUTS
        None by default. Verge.VM when -PassThru is specified.

    .NOTES
        Cloning creates a complete copy of all VM drives, which may take time
        for large VMs. The source VM can remain running during cloning.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByVMName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByVM')]
        [Alias('SourceVM')]
        [PSTypeName('Verge.VM')]
        [PSCustomObject]$VM,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByVMName')]
        [Alias('SourceVMName')]
        [string]$VMName,

        [Parameter(Mandatory, ParameterSetName = 'ByVMKey')]
        [Alias('SourceVMKey')]
        [int]$VMKey,

        [Parameter(Position = 1)]
        [ValidateLength(1, 128)]
        [string]$Name,

        [Parameter()]
        [switch]$PreserveMACAddresses,

        [Parameter()]
        [switch]$PowerOn,

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
        # Resolve source VM based on parameter set
        $targetVM = switch ($PSCmdlet.ParameterSetName) {
            'ByVMName' {
                Get-VergeVM -Name $VMName -Server $Server | Select-Object -First 1
            }
            'ByVMKey' {
                Get-VergeVM -Key $VMKey -Server $Server
            }
            'ByVM' {
                $VM
            }
        }

        if (-not $targetVM) {
            Write-Error -Message "Source VM not found" -ErrorId 'VMNotFound'
            return
        }

        # Check if VM is a snapshot
        if ($targetVM.IsSnapshot) {
            Write-Error -Message "Cannot clone '$($targetVM.Name)': VM is a snapshot. Clone the parent VM instead." -ErrorId 'CannotCloneSnapshot'
            return
        }

        # Generate clone name if not provided
        $cloneName = if ($Name) {
            $Name
        } else {
            "$($targetVM.Name)_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        }

        # Build action body
        $body = @{
            vm     = $targetVM.Key
            action = 'clone'
            params = @{
                name          = $cloneName
                preserve_macs = $PreserveMACAddresses.IsPresent
            }
        }

        $macText = if ($PreserveMACAddresses) { ' (preserving MAC addresses)' } else { '' }

        if ($PSCmdlet.ShouldProcess($targetVM.Name, "Clone VM to '$cloneName'$macText")) {
            try {
                Write-Verbose "Cloning VM '$($targetVM.Name)' to '$cloneName'"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'vm_actions' -Body $body -Connection $Server

                Write-Verbose "Clone command sent for VM '$($targetVM.Name)'"

                # Wait for clone to be created
                Start-Sleep -Seconds 3

                # Try to get the cloned VM
                $clonedVM = Get-VergeVM -Name $cloneName -Server $Server | Select-Object -First 1

                if ($clonedVM) {
                    Write-Verbose "Clone '$cloneName' created with Key: $($clonedVM.Key)"

                    # Power on if requested
                    if ($PowerOn) {
                        Write-Verbose "Powering on cloned VM '$cloneName'"
                        Start-VergeVM -Key $clonedVM.Key -Server $Server
                        Start-Sleep -Milliseconds 500
                        $clonedVM = Get-VergeVM -Key $clonedVM.Key -Server $Server
                    }

                    if ($PassThru) {
                        Write-Output $clonedVM
                    }
                }
                else {
                    Write-Warning "Clone operation initiated but cloned VM '$cloneName' not immediately available. It may still be creating."
                }
            }
            catch {
                Write-Error -Message "Failed to clone VM '$($targetVM.Name)': $($_.Exception.Message)" -ErrorId 'CloneFailed'
            }
        }
    }
}
