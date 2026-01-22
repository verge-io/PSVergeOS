function Connect-VergeOS {
    <#
    .SYNOPSIS
        Establishes a connection to a VergeOS system.

    .DESCRIPTION
        Connect-VergeOS authenticates to a VergeOS system using either
        username/password credentials or an API token. The connection is
        stored and can be used by subsequent cmdlets.

    .PARAMETER Server
        The hostname or IP address of the VergeOS system.

    .PARAMETER Credential
        A PSCredential object containing the username and password.

    .PARAMETER Token
        An API token for authentication. Use this for non-interactive scenarios.

    .PARAMETER SkipCertificateCheck
        Skip TLS certificate validation. Use for self-signed certificates.

    .PARAMETER PassThru
        Return the connection object.

    .EXAMPLE
        Connect-VergeOS -Server "vergeos.company.com" -Credential (Get-Credential)

        Connects using interactive credential prompt.

    .EXAMPLE
        Connect-VergeOS -Server "vergeos.local" -Token $env:VERGE_TOKEN -SkipCertificateCheck

        Connects using an API token with certificate validation disabled.

    .EXAMPLE
        $conn = Connect-VergeOS -Server "prod.vergeos.local" -Credential $cred -PassThru

        Connects and returns the connection object for multi-server scenarios.

    .OUTPUTS
        VergeConnection (when -PassThru is specified)

    .NOTES
        The most recent connection becomes the default for subsequent cmdlets.
        Use Get-VergeConnection to view active connections.
        Use Set-VergeConnection to change the default connection.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Credential')]
    [OutputType('VergeConnection')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Server,

        [Parameter(Mandatory, ParameterSetName = 'Credential')]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential,

        [Parameter(Mandatory, ParameterSetName = 'Token')]
        [ValidateNotNullOrEmpty()]
        [string]$Token,

        [Parameter()]
        [switch]$SkipCertificateCheck,

        [Parameter()]
        [switch]$PassThru
    )

    # Remove protocol prefix if provided
    $Server = $Server -replace '^https?://', ''

    # Create connection object
    $connection = [VergeConnection]::new($Server)
    $connection.SkipCertificateCheck = $SkipCertificateCheck.IsPresent

    # Build request parameters
    $requestParams = @{
        Method      = 'POST'
        Uri         = "$($connection.ApiBaseUrl)/auth/login"
        ContentType = 'application/json'
    }

    if ($SkipCertificateCheck) {
        $requestParams['SkipCertificateCheck'] = $true
    }

    try {
        # Build Basic Auth header
        if ($PSCmdlet.ParameterSetName -eq 'Token') {
            # Token-based authentication (Bearer token)
            $connection.Token = $Token
            $authHeader = "Bearer $Token"
            $connection.Username = 'API Token'
        }
        else {
            # Credential-based authentication (Basic Auth)
            $base64Auth = [Convert]::ToBase64String(
                [Text.Encoding]::ASCII.GetBytes(
                    "$($Credential.UserName):$($Credential.GetNetworkCredential().Password)"
                )
            )
            $authHeader = "Basic $base64Auth"
            $connection.Token = $base64Auth
            $connection.Username = $Credential.UserName
        }

        # Test authentication by calling system endpoint to get version info
        $testParams = @{
            Method  = 'GET'
            Uri     = "$($connection.ApiBaseUrl)/system?fields=yb_version,os_version,cloud_name,branch"
            Headers = @{
                'Authorization' = $authHeader
                'Accept'        = 'application/json'
            }
        }
        if ($SkipCertificateCheck) {
            $testParams['SkipCertificateCheck'] = $true
        }

        Write-Verbose "Authenticating to $Server as $($connection.Username)"
        $systemResponse = Invoke-RestMethod @testParams -ErrorAction Stop

        # Response is an array, get first element
        $systemInfo = if ($systemResponse -is [array]) { $systemResponse[0] } else { $systemResponse }

        # Get version from yb_version or os_version
        $connection.VergeOSVersion = $systemInfo.yb_version ?? $systemInfo.os_version

        # Store additional system info
        $connection | Add-Member -NotePropertyName 'CloudName' -NotePropertyValue $systemInfo.cloud_name -Force
        $connection | Add-Member -NotePropertyName 'Branch' -NotePropertyValue $systemInfo.branch -Force

        # Store auth type for later use
        $connection | Add-Member -NotePropertyName 'AuthType' -NotePropertyValue $(
            if ($PSCmdlet.ParameterSetName -eq 'Token') { 'Bearer' } else { 'Basic' }
        ) -Force

        # Mark as connected
        $connection.ConnectedAt = [datetime]::UtcNow
        $connection.IsConnected = $true

        # Check if already connected to this server
        $existing = $script:VergeConnections | Where-Object { $_.Server -eq $Server }
        if ($existing) {
            $script:VergeConnections.Remove($existing) | Out-Null
        }

        # Add to connection list and set as default
        $script:VergeConnections.Add($connection)
        $script:DefaultConnection = $connection

        Write-Verbose "Connected to $Server (VergeOS $($connection.VergeOSVersion))"

        if ($PassThru) {
            return $connection
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        if ($_.ErrorDetails.Message) {
            try {
                $errorObj = $_.ErrorDetails.Message | ConvertFrom-Json
                $errorMessage = $errorObj.err -or $errorObj.error -or $errorMessage
            }
            catch { }
        }

        throw "Failed to connect to VergeOS at '$Server': $errorMessage"
    }
}
