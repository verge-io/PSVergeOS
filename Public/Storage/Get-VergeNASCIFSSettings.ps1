function Get-VergeNASCIFSSettings {
    <#
    .SYNOPSIS
        Retrieves CIFS/SMB settings for a NAS service in VergeOS.

    .DESCRIPTION
        Get-VergeNASCIFSSettings retrieves the CIFS/SMB configuration for a NAS service,
        including workgroup, realm, Active Directory status, protocol settings, and
        guest user mapping configuration.

    .PARAMETER NASService
        A NAS service object from Get-VergeNASService. Accepts pipeline input.

    .PARAMETER Name
        The name of the NAS service to get CIFS settings for.

    .PARAMETER Key
        The unique key (ID) of the NAS service.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeNASCIFSSettings -Name "NAS01"

        Gets CIFS settings for the NAS service named "NAS01".

    .EXAMPLE
        Get-VergeNASService | Get-VergeNASCIFSSettings

        Gets CIFS settings for all NAS services.

    .EXAMPLE
        Get-VergeNASCIFSSettings -Name "FileServer" | Format-List

        Gets detailed CIFS settings for a specific NAS service.

    .OUTPUTS
        Verge.NASCIFSSettings objects containing:
        - Key: The CIFS settings unique identifier
        - NASServiceName: Name of the parent NAS service
        - Workgroup: NetBIOS workgroup name
        - Realm: Kerberos realm for AD
        - ServerType: Server role (default, Member, BDC, PDC)
        - GuestMapping: How invalid users/passwords are handled
        - MinProtocol: Minimum SMB protocol version
        - ExtendedACLSupport: Whether extended ACLs are enabled
        - ADStatus: Active Directory join status
        - ADStatusInfo: Additional AD status information

    .NOTES
        Use Set-VergeNASCIFSSettings to modify CIFS configuration.
        Active Directory integration requires additional setup.
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
                # Query CIFS settings for this service
                $queryParams = @{
                    filter = "service eq $($service.Key)"
                    fields = @(
                        '$key'
                        'service'
                        'service#$display as service_name'
                        'map_to_guest'
                        'realm'
                        'workgroup'
                        'server_type'
                        'extended_acl_support'
                        'server_min_protocol'
                        'ad_status'
                        'ad_status_info'
                        'ad_upn'
                        'ad_ou'
                        'ad_osname'
                        'ad_osver'
                        'advanced'
                    ) -join ','
                }

                Write-Verbose "Querying CIFS settings for NAS service '$($service.Name)'"
                $response = Invoke-VergeAPI -Method GET -Endpoint 'vm_service_cifs' -Query $queryParams -Connection $Server

                # Handle response
                $settings = if ($response -is [array]) { $response } else { @($response) }

                foreach ($cifs in $settings) {
                    if (-not $cifs -or -not $cifs.'$key') {
                        continue
                    }

                    # Map guest mapping to display
                    $guestMappingDisplay = switch ($cifs.map_to_guest) {
                        'never'        { 'Invalid passwords rejected' }
                        'bad user'     { 'Invalid users treated as guest' }
                        'bad password' { 'Invalid passwords treated as guest' }
                        'bad uid'      { 'Invalid linux users treated as guest' }
                        default        { $cifs.map_to_guest }
                    }

                    # Map server type to display
                    $serverTypeDisplay = switch ($cifs.server_type) {
                        'default' { 'Default' }
                        'MEMBER'  { 'Domain Member' }
                        'BDC'     { 'Backup Domain Controller' }
                        'PDC'     { 'Primary Domain Controller' }
                        default   { $cifs.server_type }
                    }

                    # Map AD status to display
                    $adStatusDisplay = switch ($cifs.ad_status) {
                        'offline' { 'Offline' }
                        'online'  { 'Online' }
                        'joining' { 'Joining' }
                        'joined'  { 'Joined' }
                        'error'   { 'Error' }
                        default   { $cifs.ad_status }
                    }

                    # Map min protocol to display
                    $minProtocolDisplay = switch ($cifs.server_min_protocol) {
                        'none'    { 'None (Any)' }
                        'SMB2'    { 'SMB 2.0' }
                        'SMB2_02' { 'SMB 2.0.2' }
                        'SMB2_10' { 'SMB 2.1' }
                        'SMB3'    { 'SMB 3.0' }
                        'SMB3_00' { 'SMB 3.0.0' }
                        'SMB3_02' { 'SMB 3.0.2' }
                        'SMB3_11' { 'SMB 3.1.1' }
                        default   { $cifs.server_min_protocol }
                    }

                    [PSCustomObject]@{
                        PSTypeName            = 'Verge.NASCIFSSettings'
                        Key                   = $cifs.'$key'
                        NASServiceKey         = $cifs.service
                        NASServiceName        = $cifs.service_name ?? $service.Name
                        Workgroup             = $cifs.workgroup
                        Realm                 = $cifs.realm
                        ServerType            = $cifs.server_type
                        ServerTypeDisplay     = $serverTypeDisplay
                        GuestMapping          = $cifs.map_to_guest
                        GuestMappingDisplay   = $guestMappingDisplay
                        MinProtocol           = $cifs.server_min_protocol
                        MinProtocolDisplay    = $minProtocolDisplay
                        ExtendedACLSupport    = [bool]$cifs.extended_acl_support
                        ADStatus              = $cifs.ad_status
                        ADStatusDisplay       = $adStatusDisplay
                        ADStatusInfo          = $cifs.ad_status_info
                        ADUserPrincipalName   = $cifs.ad_upn
                        ADOrganizationalUnit  = $cifs.ad_ou
                        ADOperatingSystem     = $cifs.ad_osname
                        ADOperatingSystemVer  = $cifs.ad_osver
                        AdvancedConfig        = $cifs.advanced
                    }
                }
            }
            catch {
                Write-Error -Message "Failed to get CIFS settings for NAS service '$($service.Name)': $($_.Exception.Message)" -ErrorId 'GetCIFSSettingsFailed'
            }
        }
    }
}
