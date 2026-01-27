function New-VergeCertificate {
    <#
    .SYNOPSIS
        Creates a new SSL/TLS certificate in VergeOS.

    .DESCRIPTION
        New-VergeCertificate creates a new SSL/TLS certificate in VergeOS.
        Three certificate types are supported:
        - Manual: Upload your own certificate and private key
        - LetsEncrypt: Automatically obtain a certificate via ACME protocol
        - SelfSigned: Generate a self-signed certificate

    .PARAMETER DomainName
        The primary domain for the certificate. Required for all certificate types.

    .PARAMETER DomainList
        Additional domain names (Subject Alternative Names) for the certificate.
        Can be specified as an array or comma-separated string.

    .PARAMETER Description
        An optional description for the certificate.

    .PARAMETER Type
        The certificate type: Manual, LetsEncrypt, or SelfSigned.
        Defaults to SelfSigned.

    .PARAMETER PublicKey
        The public certificate in PEM format. Required for Manual type.

    .PARAMETER PrivateKey
        The private key in PEM format. Required for Manual type.

    .PARAMETER Chain
        The certificate chain in PEM format. Optional for Manual type.

    .PARAMETER ACMEServer
        The ACME server URL for Let's Encrypt certificates.
        Defaults to https://acme-v02.api.letsencrypt.org/directory

    .PARAMETER EABKeyId
        Key Identifier for External Account Binding (ACME).
        Used with some ACME providers that require EAB.

    .PARAMETER EABHMACKey
        HMAC key for External Account Binding (ACME).

    .PARAMETER KeyType
        The key type for self-signed or Let's Encrypt certificates: ECDSA or RSA.
        Defaults to ECDSA.

    .PARAMETER RSAKeySize
        The RSA key size when using RSA key type. Default is 2048.

    .PARAMETER ContactUserId
        The user ID to use as contact for Let's Encrypt certificates.

    .PARAMETER AgreeTOS
        Accept the Let's Encrypt Terms of Service.
        Required for Let's Encrypt certificates.

    .PARAMETER PassThru
        Return the created certificate object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeCertificate -DomainName "example.com" -Type SelfSigned

        Creates a self-signed certificate for example.com.

    .EXAMPLE
        New-VergeCertificate -DomainName "example.com" -DomainList "www.example.com","api.example.com" -Type SelfSigned -PassThru

        Creates a self-signed certificate with SANs and returns the created object.

    .EXAMPLE
        $pubKey = Get-Content ./cert.pem -Raw
        $privKey = Get-Content ./key.pem -Raw
        New-VergeCertificate -DomainName "example.com" -Type Manual -PublicKey $pubKey -PrivateKey $privKey

        Uploads a manual certificate with public and private keys.

    .EXAMPLE
        New-VergeCertificate -DomainName "example.com" -Type LetsEncrypt -AgreeTOS -ContactUserId 1

        Creates a Let's Encrypt certificate (requires proper DNS/HTTP validation).

    .OUTPUTS
        None by default. Verge.Certificate when -PassThru is specified.

    .NOTES
        For Let's Encrypt certificates, ensure your domain's DNS points to the VergeOS
        system and that port 80 is accessible for HTTP validation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$DomainName,

        [Parameter()]
        [string[]]$DomainList,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [ValidateSet('Manual', 'LetsEncrypt', 'SelfSigned')]
        [string]$Type = 'SelfSigned',

        [Parameter()]
        [string]$PublicKey,

        [Parameter()]
        [string]$PrivateKey,

        [Parameter()]
        [string]$Chain,

        [Parameter()]
        [string]$ACMEServer,

        [Parameter()]
        [string]$EABKeyId,

        [Parameter()]
        [string]$EABHMACKey,

        [Parameter()]
        [ValidateSet('ECDSA', 'RSA')]
        [string]$KeyType,

        [Parameter()]
        [ValidateSet('2048', '3072', '4096')]
        [string]$RSAKeySize,

        [Parameter()]
        [int]$ContactUserId,

        [Parameter()]
        [switch]$AgreeTOS,

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

        # Map friendly type names to API values
        $typeMapping = @{
            'Manual'      = 'manual'
            'LetsEncrypt' = 'letsencrypt'
            'SelfSigned'  = 'self_signed'
        }
    }

    process {
        # Validate parameters based on certificate type
        if ($Type -eq 'Manual') {
            if (-not $PublicKey) {
                throw "PublicKey is required for Manual certificate type."
            }
            if (-not $PrivateKey) {
                throw "PrivateKey is required for Manual certificate type."
            }
        }
        elseif ($Type -eq 'LetsEncrypt') {
            if (-not $AgreeTOS) {
                throw "You must accept the Let's Encrypt Terms of Service using -AgreeTOS."
            }
        }

        # Build request body
        $body = @{
            domainname = $DomainName
            type       = $typeMapping[$Type]
        }

        # Add domain list (SANs)
        if ($DomainList) {
            $body['domainlist'] = $DomainList -join ','
        }

        # Add optional description
        if ($Description) {
            $body['description'] = $Description
        }

        # Manual certificate specific fields
        if ($Type -eq 'Manual') {
            $body['public'] = $PublicKey
            $body['private'] = $PrivateKey
            if ($Chain) {
                $body['chain'] = $Chain
            }
        }

        # Let's Encrypt specific fields
        if ($Type -eq 'LetsEncrypt') {
            $body['agree_tos'] = $true

            if ($ACMEServer) {
                $body['acme_server'] = $ACMEServer
            }

            if ($EABKeyId) {
                $body['eab_kid'] = $EABKeyId
            }

            if ($EABHMACKey) {
                $body['eab_hmac_key'] = $EABHMACKey
            }

            if ($ContactUserId) {
                $body['contact'] = $ContactUserId
            }
        }

        # Key type for self-signed and Let's Encrypt
        if ($Type -ne 'Manual') {
            if ($KeyType) {
                $body['key_type'] = $KeyType.ToLower()
            }

            if ($RSAKeySize) {
                $body['rsa_key_size'] = $RSAKeySize
            }
        }

        # Determine display name for confirmation
        $typeDisplay = switch ($Type) {
            'Manual' { 'Manual' }
            'LetsEncrypt' { "Let's Encrypt" }
            'SelfSigned' { 'Self-Signed' }
        }

        if ($PSCmdlet.ShouldProcess("$DomainName ($typeDisplay)", 'Create Certificate')) {
            try {
                Write-Verbose "Creating $typeDisplay certificate for domain '$DomainName'"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'certificates' -Body $body -Connection $Server

                # Get the created certificate key
                $certKey = $response.'$key'
                if (-not $certKey -and $response.key) {
                    $certKey = $response.key
                }

                Write-Verbose "Certificate created with Key: $certKey"

                if ($PassThru -and $certKey) {
                    # Return the created certificate
                    Start-Sleep -Milliseconds 500
                    Get-VergeCertificate -Key $certKey -Server $Server
                }
            }
            catch {
                $errorMessage = $_.Exception.Message
                if ($errorMessage -match 'already exists' -or $errorMessage -match 'duplicate') {
                    throw "A certificate for domain '$DomainName' already exists."
                }
                throw "Failed to create certificate for '$DomainName': $errorMessage"
            }
        }
    }
}
