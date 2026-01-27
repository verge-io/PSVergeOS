function Set-VergeCertificate {
    <#
    .SYNOPSIS
        Modifies the configuration of a VergeOS SSL/TLS certificate.

    .DESCRIPTION
        Set-VergeCertificate modifies certificate settings such as description,
        domain list (SANs), keys (for manual certificates), and ACME settings
        (for Let's Encrypt certificates).

    .PARAMETER Certificate
        A certificate object from Get-VergeCertificate. Accepts pipeline input.

    .PARAMETER Key
        The key (ID) of the certificate to modify.

    .PARAMETER Description
        Set the certificate description.

    .PARAMETER DomainList
        Set additional domain names (Subject Alternative Names).
        Can be specified as an array or comma-separated string.

    .PARAMETER PublicKey
        Update the public certificate in PEM format (manual certificates only).

    .PARAMETER PrivateKey
        Update the private key in PEM format (manual certificates only).

    .PARAMETER Chain
        Update the certificate chain in PEM format (manual certificates only).

    .PARAMETER ACMEServer
        Update the ACME server URL (Let's Encrypt certificates only).

    .PARAMETER EABKeyId
        Update the External Account Binding Key ID.

    .PARAMETER EABHMACKey
        Update the External Account Binding HMAC Key.

    .PARAMETER KeyType
        Update the key type: ECDSA or RSA.

    .PARAMETER RSAKeySize
        Update the RSA key size: 2048, 3072, or 4096.

    .PARAMETER ContactUserId
        Update the contact user ID for Let's Encrypt certificates.

    .PARAMETER AgreeTOS
        Accept the Terms of Service (for Let's Encrypt certificates).

    .PARAMETER PassThru
        Return the modified certificate object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Set-VergeCertificate -Key 1 -Description "Primary API certificate"

        Updates the description of a certificate.

    .EXAMPLE
        Get-VergeCertificate -Key 1 | Set-VergeCertificate -Description "Updated description" -PassThru

        Updates a certificate using pipeline input and returns the result.

    .EXAMPLE
        Set-VergeCertificate -Key 2 -DomainList "www.example.com","api.example.com"

        Updates the Subject Alternative Names for a certificate.

    .OUTPUTS
        None by default. Verge.Certificate when -PassThru is specified.

    .NOTES
        Some fields may be read-only depending on the certificate type.
        Changing keys on a manual certificate will require the new keys to be valid.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByKey')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByCertificate')]
        [PSTypeName('Verge.Certificate')]
        [PSCustomObject]$Certificate,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [string[]]$DomainList,

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
    }

    process {
        # Resolve certificate based on parameter set
        $targetCert = switch ($PSCmdlet.ParameterSetName) {
            'ByKey' {
                Get-VergeCertificate -Key $Key -Server $Server
            }
            'ByCertificate' {
                $Certificate
            }
        }

        if (-not $targetCert) {
            Write-Error -Message "Certificate not found" -ErrorId 'CertificateNotFound'
            return
        }

        # Build the update body with only specified parameters
        $body = @{}
        $changes = [System.Collections.Generic.List[string]]::new()

        if ($PSBoundParameters.ContainsKey('Description')) {
            $body['description'] = $Description
            $changes.Add("Description updated")
        }

        if ($PSBoundParameters.ContainsKey('DomainList')) {
            $body['domainlist'] = $DomainList -join ','
            $changes.Add("DomainList: $($DomainList -join ', ')")
        }

        if ($PSBoundParameters.ContainsKey('PublicKey')) {
            $body['public'] = $PublicKey
            $changes.Add("PublicKey updated")
        }

        if ($PSBoundParameters.ContainsKey('PrivateKey')) {
            $body['private'] = $PrivateKey
            $changes.Add("PrivateKey updated")
        }

        if ($PSBoundParameters.ContainsKey('Chain')) {
            $body['chain'] = $Chain
            $changes.Add("Chain updated")
        }

        if ($PSBoundParameters.ContainsKey('ACMEServer')) {
            $body['acme_server'] = $ACMEServer
            $changes.Add("ACMEServer: $ACMEServer")
        }

        if ($PSBoundParameters.ContainsKey('EABKeyId')) {
            $body['eab_kid'] = $EABKeyId
            $changes.Add("EABKeyId updated")
        }

        if ($PSBoundParameters.ContainsKey('EABHMACKey')) {
            $body['eab_hmac_key'] = $EABHMACKey
            $changes.Add("EABHMACKey updated")
        }

        if ($PSBoundParameters.ContainsKey('KeyType')) {
            $body['key_type'] = $KeyType.ToLower()
            $changes.Add("KeyType: $KeyType")
        }

        if ($PSBoundParameters.ContainsKey('RSAKeySize')) {
            $body['rsa_key_size'] = $RSAKeySize
            $changes.Add("RSAKeySize: $RSAKeySize")
        }

        if ($PSBoundParameters.ContainsKey('ContactUserId')) {
            $body['contact'] = $ContactUserId
            $changes.Add("ContactUserId: $ContactUserId")
        }

        if ($AgreeTOS) {
            $body['agree_tos'] = $true
            $changes.Add("AgreeTOS: True")
        }

        # Check if there are any changes to make
        if ($body.Count -eq 0) {
            Write-Warning "No changes specified for certificate '$($targetCert.Domain)'"
            if ($PassThru) {
                Write-Output $targetCert
            }
            return
        }

        # Build change summary for confirmation
        $changeSummary = $changes -join ', '
        $certDisplay = "$($targetCert.Domain) (Key: $($targetCert.Key))"

        if ($PSCmdlet.ShouldProcess($certDisplay, "Modify Certificate ($changeSummary)")) {
            try {
                Write-Verbose "Modifying certificate '$($targetCert.Domain)' (Key: $($targetCert.Key))"
                Write-Verbose "Changes: $changeSummary"

                $null = Invoke-VergeAPI -Method PUT -Endpoint "certificates/$($targetCert.Key)" -Body $body -Connection $Server

                Write-Verbose "Certificate '$($targetCert.Domain)' modified successfully"

                if ($PassThru) {
                    # Return the updated certificate
                    Start-Sleep -Milliseconds 500
                    Get-VergeCertificate -Key $targetCert.Key -Server $Server
                }
            }
            catch {
                $errorMessage = $_.Exception.Message
                Write-Error -Message "Failed to modify certificate '$($targetCert.Domain)': $errorMessage" -ErrorId 'CertificateModifyFailed'
            }
        }
    }
}
