function Update-VergeCertificate {
    <#
    .SYNOPSIS
        Renews or regenerates a VergeOS SSL/TLS certificate.

    .DESCRIPTION
        Update-VergeCertificate triggers renewal of a Let's Encrypt certificate
        or regeneration of a self-signed certificate. This is useful when:
        - A Let's Encrypt certificate is approaching expiration
        - You want to force renewal before automatic renewal
        - You need to regenerate a self-signed certificate

    .PARAMETER Certificate
        A certificate object from Get-VergeCertificate. Accepts pipeline input.

    .PARAMETER Key
        The key (ID) of the certificate to renew/regenerate.

    .PARAMETER Domain
        The domain of the certificate to renew/regenerate.

    .PARAMETER Force
        Force renewal even if the certificate is not near expiration.

    .PARAMETER PassThru
        Return the updated certificate object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Update-VergeCertificate -Key 1

        Renews/regenerates the certificate with Key 1.

    .EXAMPLE
        Get-VergeCertificate -Type LetsEncrypt | Update-VergeCertificate

        Renews all Let's Encrypt certificates.

    .EXAMPLE
        Get-VergeCertificate | Where-Object { $_.DaysUntilExpiry -lt 30 } | Update-VergeCertificate

        Renews all certificates expiring within 30 days.

    .EXAMPLE
        Update-VergeCertificate -Domain "example.com" -PassThru

        Renews a certificate by domain and returns the updated certificate.

    .OUTPUTS
        None by default. Verge.Certificate when -PassThru is specified.

    .NOTES
        For Let's Encrypt certificates, ensure DNS and HTTP validation can succeed.
        Self-signed certificates will be regenerated with a new key pair.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByKey')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByCertificate')]
        [PSTypeName('Verge.Certificate')]
        [PSCustomObject]$Certificate,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByDomain')]
        [string]$Domain,

        [Parameter()]
        [switch]$Force,

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
        $targetCerts = switch ($PSCmdlet.ParameterSetName) {
            'ByKey' {
                Get-VergeCertificate -Key $Key -Server $Server
            }
            'ByDomain' {
                Get-VergeCertificate -Domain $Domain -Server $Server
            }
            'ByCertificate' {
                $Certificate
            }
        }

        foreach ($targetCert in $targetCerts) {
            if (-not $targetCert) {
                continue
            }

            # Build display string
            $certDisplay = "$($targetCert.Domain) (Key: $($targetCert.Key), Type: $($targetCert.Type))"

            # Check if renewal makes sense (warn but allow with -Force)
            if (-not $Force -and $targetCert.DaysUntilExpiry -and $targetCert.DaysUntilExpiry -gt 30) {
                Write-Warning "Certificate '$($targetCert.Domain)' expires in $($targetCert.DaysUntilExpiry) days. Use -Force to renew anyway."
                if (-not $PSCmdlet.ShouldProcess($certDisplay, "Renew Certificate (expires in $($targetCert.DaysUntilExpiry) days)")) {
                    continue
                }
            }

            $actionVerb = switch ($targetCert.TypeValue) {
                'letsencrypt' { 'Renew' }
                'self_signed' { 'Regenerate' }
                default { 'Update' }
            }

            if ($PSCmdlet.ShouldProcess($certDisplay, "$actionVerb Certificate")) {
                try {
                    $actionVerbing = switch ($targetCert.TypeValue) {
                        'letsencrypt' { 'Renewing' }
                        'self_signed' { 'Regenerating' }
                        default { 'Updating' }
                    }
                    $actionVerbed = switch ($targetCert.TypeValue) {
                        'letsencrypt' { 'renewed' }
                        'self_signed' { 'regenerated' }
                        default { 'updated' }
                    }

                    Write-Verbose "$actionVerbing certificate '$($targetCert.Domain)' (Key: $($targetCert.Key))"

                    # Send renewal request
                    $body = @{
                        renew = $true
                    }

                    $null = Invoke-VergeAPI -Method PUT -Endpoint "certificates/$($targetCert.Key)" -Body $body -Connection $Server

                    Write-Verbose "Certificate '$($targetCert.Domain)' $actionVerbed successfully"

                    if ($PassThru) {
                        # Wait for renewal to process
                        Start-Sleep -Seconds 2
                        Get-VergeCertificate -Key $targetCert.Key -Server $Server
                    }
                }
                catch {
                    $errorMessage = $_.Exception.Message
                    $actionVerbLower = $actionVerb.ToLower()
                    if ($errorMessage -match 'validation' -or $errorMessage -match 'challenge') {
                        Write-Error -Message "Failed to $actionVerbLower certificate '$($targetCert.Domain)': ACME validation failed. Check DNS/HTTP configuration." -ErrorId 'CertificateRenewalFailed'
                    }
                    else {
                        Write-Error -Message "Failed to $actionVerbLower certificate '$($targetCert.Domain)': $errorMessage" -ErrorId 'CertificateRenewalFailed'
                    }
                }
            }
        }
    }
}
