function Get-VergeVMConsole {
    <#
    .SYNOPSIS
        Gets console access information for a VergeOS virtual machine.

    .DESCRIPTION
        Get-VergeVMConsole retrieves the console connection details for a VM,
        including the host, port, and full URL for VNC/Spice access.
        The VM must be running to have an active console.

    .PARAMETER VM
        A VM object from Get-VergeVM. Accepts pipeline input.

    .PARAMETER Name
        The name of the VM to get console info for.

    .PARAMETER Key
        The key (ID) of the VM to get console info for.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeVMConsole -Name "WebServer01"

        Gets the console connection details for the VM.

    .EXAMPLE
        Get-VergeVM -Name "Web*" | Get-VergeVMConsole

        Gets console details for all web servers.

    .EXAMPLE
        Get-VergeVMConsole -Name "WebServer01" | Select-Object -ExpandProperty URL

        Gets just the console URL.

    .OUTPUTS
        Verge.VMConsole object containing:
        - VMKey: The VM key
        - VMName: The VM name
        - ConsoleType: VNC, Spice, Serial, or None
        - Host: The console host address
        - Port: The console port
        - URL: The full console URL
        - Active: Whether there are active console connections

    .NOTES
        The VM must be running to have an active console.
        Console type depends on VM configuration (VNC is default).
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByVM')]
        [PSTypeName('Verge.VM')]
        [PSCustomObject]$VM,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [SupportsWildcards()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

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
            'ByName' {
                Get-VergeVM -Name $Name -Server $Server
            }
            'ByKey' {
                Get-VergeVM -Key $Key -Server $Server
            }
            'ByVM' {
                $VM
            }
        }

        foreach ($targetVM in $targetVMs) {
            if (-not $targetVM) {
                continue
            }

            try {
                # Get VM details with console_status
                $vmResponse = Invoke-VergeAPI -Method GET -Endpoint "vms/$($targetVM.Key)?fields=name,console,machine,console_status[host,port,active]" -Connection $Server

                if (-not $vmResponse) {
                    Write-Error -Message "VM '$($targetVM.Name)' not found" -ErrorId 'VMNotFound'
                    continue
                }

                $consoleType = $vmResponse.console ?? 'vnc'
                $consoleStatus = $vmResponse.console_status

                $host = $null
                $port = $null
                $activeConnections = @()

                if ($consoleStatus) {
                    $host = $consoleStatus.host
                    $port = $consoleStatus.port
                    $activeConnections = $consoleStatus.active ?? @()
                }

                # Build console URL
                $url = $null
                if ($host -and $port) {
                    $protocol = switch ($consoleType) {
                        'vnc'    { 'vnc' }
                        'spice'  { 'spice' }
                        'serial' { 'telnet' }
                        default  { 'vnc' }
                    }
                    $url = "${protocol}://${host}:${port}"
                }

                # Build web console URL (through VergeOS UI)
                $serverUrl = $Server.ServerUrl ?? "https://$($Server.Server)"
                $webConsoleUrl = "$serverUrl/#/vm-console/$($targetVM.Key)"

                [PSCustomObject]@{
                    PSTypeName        = 'Verge.VMConsole'
                    VMKey             = $targetVM.Key
                    VMName            = $targetVM.Name
                    ConsoleType       = $consoleType
                    Host              = $host
                    Port              = $port
                    URL               = $url
                    WebConsoleURL     = $webConsoleUrl
                    PowerState        = $targetVM.PowerState
                    ActiveConnections = $activeConnections.Count
                    IsAvailable       = ($null -ne $host -and $null -ne $port)
                }
            }
            catch {
                Write-Error -Message "Failed to get console info for VM '$($targetVM.Name)': $($_.Exception.Message)" -ErrorId 'ConsoleInfoFailed'
            }
        }
    }
}
