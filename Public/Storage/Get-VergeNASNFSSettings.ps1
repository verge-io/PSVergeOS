function Get-VergeNASNFSSettings {
    <#
    .SYNOPSIS
        Retrieves NFS settings for a NAS service in VergeOS.

    .DESCRIPTION
        Get-VergeNASNFSSettings retrieves the NFS configuration for a NAS service,
        including NFSv4 status, allowed hosts, squashing options, and access settings.

    .PARAMETER NASService
        A NAS service object from Get-VergeNASService. Accepts pipeline input.

    .PARAMETER Name
        The name of the NAS service to get NFS settings for.

    .PARAMETER Key
        The unique key (ID) of the NAS service.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeNASNFSSettings -Name "NAS01"

        Gets NFS settings for the NAS service named "NAS01".

    .EXAMPLE
        Get-VergeNASService | Get-VergeNASNFSSettings

        Gets NFS settings for all NAS services.

    .EXAMPLE
        Get-VergeNASNFSSettings -Name "FileServer" | Format-List

        Gets detailed NFS settings for a specific NAS service.

    .OUTPUTS
        Verge.NASNFSSettings objects containing:
        - Key: The NFS settings unique identifier
        - NASServiceName: Name of the parent NAS service
        - EnableNFSv4: Whether NFSv4 is enabled
        - AllowedHosts: List of allowed hosts/networks
        - AllowAll: Whether all hosts are allowed
        - Squash: User/group squashing mode
        - DataAccess: Read-only or read-write
        - AnonUID: Anonymous user ID
        - AnonGID: Anonymous group ID
        - NoACL: Whether ACLs are disabled
        - Insecure: Whether insecure port mode is enabled
        - Async: Whether async mode is enabled

    .NOTES
        Use Set-VergeNASNFSSettings to modify NFS configuration.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [PSTypeName('Verge.NASService')]
        [PSCustomObject]$NASService,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
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
        # Resolve NAS service based on parameter set
        $targetServices = switch ($PSCmdlet.ParameterSetName) {
            'ByName' {
                Get-VergeNASService -Name $Name -Server $Server
            }
            'ByKey' {
                Get-VergeNASService -Key $Key -Server $Server
            }
            'ByObject' {
                $NASService
            }
        }

        foreach ($service in $targetServices) {
            if (-not $service) {
                if ($PSCmdlet.ParameterSetName -eq 'ByName') {
                    Write-Error -Message "NAS service '$Name' not found." -ErrorId 'NASServiceNotFound'
                }
                continue
            }

            try {
                # Query NFS settings for this service
                $queryParams = @{
                    filter = "service eq $($service.Key)"
                    fields = @(
                        '$key'
                        'service'
                        'service#$display as service_name'
                        'enable_nfsv4'
                        'allowed_hosts'
                        'fsid'
                        'anonuid'
                        'anongid'
                        'no_acl'
                        'insecure'
                        'async'
                        'squash'
                        'data_access'
                        'allow_all'
                    ) -join ','
                }

                Write-Verbose "Querying NFS settings for NAS service '$($service.Name)'"
                $response = Invoke-VergeAPI -Method GET -Endpoint 'vm_service_nfs' -Query $queryParams -Connection $Server

                # Handle response
                $settings = if ($response -is [array]) { $response } else { @($response) }

                foreach ($nfs in $settings) {
                    if (-not $nfs -or -not $nfs.'$key') {
                        continue
                    }

                    # Map squash to display
                    $squashDisplay = switch ($nfs.squash) {
                        'root_squash'    { 'Squash Root' }
                        'all_squash'     { 'Squash All' }
                        'no_root_squash' { 'No Squashing' }
                        default          { $nfs.squash }
                    }

                    # Map data access to display
                    $dataAccessDisplay = switch ($nfs.data_access) {
                        'ro' { 'Read Only' }
                        'rw' { 'Read/Write' }
                        default { $nfs.data_access }
                    }

                    [PSCustomObject]@{
                        PSTypeName         = 'Verge.NASNFSSettings'
                        Key                = $nfs.'$key'
                        NASServiceKey      = $nfs.service
                        NASServiceName     = $nfs.service_name ?? $service.Name
                        EnableNFSv4        = [bool]$nfs.enable_nfsv4
                        AllowedHosts       = $nfs.allowed_hosts
                        AllowAll           = [bool]$nfs.allow_all
                        Squash             = $nfs.squash
                        SquashDisplay      = $squashDisplay
                        DataAccess         = $nfs.data_access
                        DataAccessDisplay  = $dataAccessDisplay
                        FilesystemID       = $nfs.fsid
                        AnonUID            = $nfs.anonuid
                        AnonGID            = $nfs.anongid
                        NoACL              = [bool]$nfs.no_acl
                        Insecure           = [bool]$nfs.insecure
                        Async              = [bool]$nfs.async
                    }
                }
            }
            catch {
                Write-Error -Message "Failed to get NFS settings for NAS service '$($service.Name)': $($_.Exception.Message)" -ErrorId 'GetNFSSettingsFailed'
            }
        }
    }
}
