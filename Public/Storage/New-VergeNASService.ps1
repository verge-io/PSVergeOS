function New-VergeNASService {
    <#
    .SYNOPSIS
        Deploys a new NAS service VM in VergeOS.

    .DESCRIPTION
        New-VergeNASService deploys a new NAS (Network Attached Storage) service VM
        using the Services recipe. NAS services manage volumes and file shares
        (CIFS/SMB and NFS) in VergeOS.

    .PARAMETER Name
        The name for the new NAS service. This will be the name of both the
        recipe instance and the underlying VM.

    .PARAMETER Hostname
        The hostname for the NAS service VM. If not specified, defaults to the
        Name parameter value (with invalid characters removed).

    .PARAMETER Network
        The network to connect the NAS service to. Can be a network name, key,
        or network object. If not specified, defaults to 'Internal' or the first
        available internal network.

    .PARAMETER Cores
        The number of CPU cores for the NAS service VM. Default is 4.

    .PARAMETER MemoryGB
        The amount of RAM in GB for the NAS service VM. Default is 8.

    .PARAMETER AutoUpdate
        If specified, the NAS service VM will automatically update when powered off.

    .PARAMETER PassThru
        Return the created NAS service object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeNASService -Name "NAS01"

        Deploys a new NAS service named "NAS01" with default settings.

    .EXAMPLE
        New-VergeNASService -Name "FileServer" -Network "Internal" -PassThru

        Deploys a new NAS service on the Internal network and returns the object.

    .EXAMPLE
        New-VergeNASService -Name "NAS02" -Cores 8 -MemoryGB 16

        Deploys a NAS service with 8 CPU cores and 16 GB RAM.

    .EXAMPLE
        New-VergeNASService -Name "NAS03" -Hostname "fileserver" -AutoUpdate

        Deploys a NAS service with a custom hostname and auto-update enabled.

    .OUTPUTS
        None by default. Verge.NASService when -PassThru is specified.

    .NOTES
        The Services recipe must be available in the system. NAS services are
        specialized VMs that manage NAS volumes and file shares. Once deployed,
        use Get-VergeNASService to view the service and New-VergeVolume to create
        volumes on the service.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateLength(1, 128)]
        [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9\-_. ]*$')]
        [string]$Name,

        [Parameter()]
        [ValidateLength(1, 63)]
        [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9]$|^[a-zA-Z0-9]$')]
        [string]$Hostname,

        [Parameter()]
        [object]$Network,

        [Parameter()]
        [ValidateRange(1, 128)]
        [int]$Cores = 4,

        [Parameter()]
        [ValidateRange(1, 1024)]
        [int]$MemoryGB = 8,

        [Parameter()]
        [switch]$AutoUpdate,

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
        # Find the Services recipe
        $recipeQuery = @{
            filter = "name eq 'Services'"
            fields = 'id,name,description,version'
        }

        try {
            Write-Verbose "Looking up Services recipe"
            $recipe = Invoke-VergeAPI -Method GET -Endpoint 'vm_recipes' -Query $recipeQuery -Connection $Server
        }
        catch {
            throw [System.InvalidOperationException]::new(
                "Failed to find Services recipe: $($_.Exception.Message)"
            )
        }

        if (-not $recipe) {
            throw [System.InvalidOperationException]::new(
                "Services recipe not found. Ensure the Services recipe is available in the system."
            )
        }

        # Handle array response
        if ($recipe -is [array]) {
            $recipe = $recipe[0]
        }

        Write-Verbose "Found Services recipe: $($recipe.name) (ID: $($recipe.id))"

        # Check if a NAS service with this name already exists
        try {
            $existing = Get-VergeNASService -Name $Name -Server $Server -ErrorAction SilentlyContinue
            if ($existing) {
                throw [System.InvalidOperationException]::new(
                    "A NAS service with name '$Name' already exists."
                )
            }
        }
        catch [System.InvalidOperationException] {
            throw
        }
        catch {
            # Continue if not found
        }

        # Determine hostname (default to Name with invalid characters removed)
        if (-not $Hostname) {
            $Hostname = $Name -replace '[^a-zA-Z0-9\-]', '' -replace '^-+', '' -replace '-+$', ''
            if ($Hostname.Length -gt 63) {
                $Hostname = $Hostname.Substring(0, 63)
            }
            if (-not $Hostname) {
                $Hostname = 'nas'
            }
        }

        # Resolve network
        $networkKey = $null
        if ($Network) {
            if ($Network -is [int]) {
                $networkKey = $Network
            }
            elseif ($Network -is [string]) {
                # Look up network by name
                $netObj = Get-VergeNetwork -Name $Network -Server $Server -ErrorAction SilentlyContinue
                if (-not $netObj) {
                    throw [System.ArgumentException]::new("Network '$Network' not found.")
                }
                $networkKey = $netObj.Key
            }
            elseif ($Network.Key) {
                $networkKey = $Network.Key
            }
        }
        else {
            # Try to find 'Internal' network or first available internal network
            $netObj = Get-VergeNetwork -Name 'Internal' -Server $Server -ErrorAction SilentlyContinue
            if (-not $netObj) {
                $allNets = Get-VergeNetwork -Server $Server
                $netObj = $allNets | Where-Object { $_.Type -eq 'Internal' } | Select-Object -First 1
            }
            if ($netObj) {
                $networkKey = $netObj.Key
                Write-Verbose "Using network '$($netObj.Name)' (Key: $networkKey)"
            }
        }

        if (-not $networkKey) {
            throw [System.InvalidOperationException]::new(
                "No network specified and no Internal network found. Use -Network to specify a network."
            )
        }

        # Build request body for vm_recipe_instances
        $body = @{
            recipe  = $recipe.id
            name    = $Name
            answers = @{
                HOSTNAME         = $Hostname
                YB_HOSTNAME      = $Hostname
                YB_CPU_CORES     = $Cores
                YB_RAM           = ($MemoryGB * 1024)  # Convert GB to MB
                YB_NIC_1         = $networkKey.ToString()
                YB_NIC_1_IP_TYPE = 'dhcp'
                YB_TIMEZONE      = 'America/New_York'
                YB_NTP           = 'time.nist.gov 0.pool.ntp.org 1.pool.ntp.org'
                YB_DOMAINNAME    = ''
            }
        }

        if ($AutoUpdate) {
            $body['auto_update'] = $true
        }

        # Confirm action
        if ($PSCmdlet.ShouldProcess($Name, "Deploy NAS service VM (Hostname: $Hostname, Network: $networkKey, Cores: $Cores, RAM: ${MemoryGB}GB)")) {
            try {
                Write-Verbose "Deploying NAS service VM '$Name' with hostname '$Hostname'"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'vm_recipe_instances' -Body $body -Connection $Server

                Write-Verbose "NAS service VM deployment initiated"

                if ($PassThru) {
                    # Wait for the service to be created
                    $maxAttempts = 15
                    $attempt = 0
                    $service = $null

                    while ($attempt -lt $maxAttempts -and -not $service) {
                        $attempt++
                        Start-Sleep -Seconds 2
                        Write-Verbose "Waiting for NAS service to be created (attempt $attempt of $maxAttempts)"
                        $service = Get-VergeNASService -Name $Name -Server $Server -ErrorAction SilentlyContinue
                    }

                    if ($service) {
                        Write-Output $service
                    }
                    else {
                        Write-Warning "NAS service deployment initiated but service '$Name' not yet found. It may still be creating."
                    }
                }
            }
            catch {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.InvalidOperationException]::new("Failed to deploy NAS service '$Name': $($_.Exception.Message)"),
                        'NASServiceDeployFailed',
                        [System.Management.Automation.ErrorCategory]::InvalidOperation,
                        $Name
                    )
                )
            }
        }
    }
}
