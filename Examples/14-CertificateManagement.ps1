<#
.SYNOPSIS
    Examples for VergeOS SSL/TLS certificate management.

.DESCRIPTION
    This script demonstrates certificate management capabilities:
    - Listing and filtering certificates
    - Creating self-signed certificates
    - Creating manual certificates (uploading existing certs)
    - Creating Let's Encrypt certificates (ACME)
    - Modifying certificate properties
    - Renewing and regenerating certificates
    - Certificate expiration monitoring
    - Common certificate workflows

.NOTES
    Prerequisites:
    - PowerShell 7.4 or later
    - PSVergeOS module installed
    - Connected to a VergeOS system

    Certificate Types:
    - Manual: Upload your own certificate and private key
    - LetsEncrypt: Automatically obtain via ACME protocol
    - SelfSigned: Generate a self-signed certificate
#>

# Import the module
Import-Module PSVergeOS

#region Listing Certificates
# ============================================================================
# LISTING AND FILTERING CERTIFICATES
# ============================================================================

# List all certificates
Get-VergeCertificate

# View certificates in a formatted table
Get-VergeCertificate | Format-Table Key, Domain, Type, Valid, DaysUntilExpiry, Expires -AutoSize

# Get a specific certificate by key
Get-VergeCertificate -Key 1

# Filter by certificate type
Get-VergeCertificate -Type SelfSigned
Get-VergeCertificate -Type LetsEncrypt
Get-VergeCertificate -Type Manual

# Get only valid (unexpired) certificates
Get-VergeCertificate -Valid

# Filter by domain (supports wildcards)
Get-VergeCertificate -Domain "*.example.com"
Get-VergeCertificate -Domain "api*"

# View detailed certificate information
Get-VergeCertificate -Key 1 | Format-List *

# Include sensitive key material (use with caution)
Get-VergeCertificate -Key 1 -IncludeKeys | Select-Object Domain, PublicKey, PrivateKey, Chain

#endregion

#region Creating Self-Signed Certificates
# ============================================================================
# CREATING SELF-SIGNED CERTIFICATES
# ============================================================================

# Create a basic self-signed certificate
New-VergeCertificate -DomainName "myapp.local" -Type SelfSigned

# Create with description and get the result
$cert = New-VergeCertificate -DomainName "internal.local" `
    -Type SelfSigned `
    -Description "Internal services certificate" `
    -PassThru

$cert | Format-List Key, Domain, Type, Valid, Expires

# Create with specific key type
New-VergeCertificate -DomainName "secure.local" `
    -Type SelfSigned `
    -KeyType RSA `
    -RSAKeySize 4096 `
    -Description "RSA 4096-bit certificate"

# Create with Subject Alternative Names (SANs)
New-VergeCertificate -DomainName "app.local" `
    -Type SelfSigned `
    -DomainList "www.app.local", "api.app.local", "admin.app.local" `
    -Description "Multi-domain certificate"

#endregion

#region Creating Manual Certificates
# ============================================================================
# UPLOADING MANUAL CERTIFICATES
# ============================================================================

# Upload an existing certificate from files
# Note: Replace paths with your actual certificate files

<#
# Read certificate files
$publicKey = Get-Content -Path "./cert.pem" -Raw
$privateKey = Get-Content -Path "./key.pem" -Raw
$chain = Get-Content -Path "./chain.pem" -Raw

# Upload the certificate
New-VergeCertificate -DomainName "example.com" `
    -Type Manual `
    -PublicKey $publicKey `
    -PrivateKey $privateKey `
    -Chain $chain `
    -Description "Uploaded production certificate"
#>

# Upload certificate from variables (example with placeholder content)
<#
$publicKey = @"
-----BEGIN CERTIFICATE-----
MIIDXTCCAkWgAwIBAgIJAJC1HiIAZAiUMA0Gcz93vGr...
-----END CERTIFICATE-----
"@

$privateKey = @"
-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwgg...
-----END PRIVATE KEY-----
"@

New-VergeCertificate -DomainName "example.com" `
    -Type Manual `
    -PublicKey $publicKey `
    -PrivateKey $privateKey `
    -Description "Manually uploaded certificate"
#>

#endregion

#region Creating Let's Encrypt Certificates
# ============================================================================
# CREATING LET'S ENCRYPT (ACME) CERTIFICATES
# ============================================================================

# Create a Let's Encrypt certificate
# Note: Requires proper DNS/HTTP validation setup
<#
New-VergeCertificate -DomainName "public.example.com" `
    -Type LetsEncrypt `
    -AgreeTOS `
    -ContactUserId 1 `
    -Description "Let's Encrypt production certificate"

# Create with custom ACME server (e.g., staging for testing)
New-VergeCertificate -DomainName "test.example.com" `
    -Type LetsEncrypt `
    -ACMEServer "https://acme-staging-v02.api.letsencrypt.org/directory" `
    -AgreeTOS `
    -ContactUserId 1 `
    -Description "Let's Encrypt staging certificate"

# Create with External Account Binding (for providers that require it)
New-VergeCertificate -DomainName "eab.example.com" `
    -Type LetsEncrypt `
    -ACMEServer "https://acme.provider.com/directory" `
    -EABKeyId "kid_12345" `
    -EABHMACKey "hmac_secret_key" `
    -AgreeTOS `
    -ContactUserId 1

# Create with multiple domains (SANs)
New-VergeCertificate -DomainName "example.com" `
    -DomainList "www.example.com", "api.example.com" `
    -Type LetsEncrypt `
    -AgreeTOS `
    -ContactUserId 1
#>

#endregion

#region Modifying Certificates
# ============================================================================
# MODIFYING CERTIFICATE PROPERTIES
# ============================================================================

# Update certificate description
Set-VergeCertificate -Key 1 -Description "Primary API certificate - updated"

# Update using pipeline
Get-VergeCertificate -Key 1 | Set-VergeCertificate -Description "Updated via pipeline" -PassThru

# Update multiple properties
Set-VergeCertificate -Key 1 `
    -Description "Production web certificate" `
    -DomainList "www.example.com", "api.example.com", "admin.example.com"

# Update ACME settings for Let's Encrypt certificate
<#
Set-VergeCertificate -Key 2 `
    -ACMEServer "https://acme-v02.api.letsencrypt.org/directory" `
    -ContactUserId 1
#>

# Update certificate keys (manual certificates only)
<#
$newPublicKey = Get-Content "./new-cert.pem" -Raw
$newPrivateKey = Get-Content "./new-key.pem" -Raw

Set-VergeCertificate -Key 1 `
    -PublicKey $newPublicKey `
    -PrivateKey $newPrivateKey `
    -Description "Renewed certificate"
#>

#endregion

#region Renewing and Regenerating Certificates
# ============================================================================
# RENEWING AND REGENERATING CERTIFICATES
# ============================================================================

# Regenerate a self-signed certificate (creates new key pair)
Update-VergeCertificate -Key 1 -Force

# Renew using pipeline
Get-VergeCertificate -Key 1 | Update-VergeCertificate -Force

# Renew a Let's Encrypt certificate
<#
Update-VergeCertificate -Domain "example.com"
#>

# Renew with PassThru to see the updated certificate
$renewed = Update-VergeCertificate -Key 1 -Force -PassThru
$renewed | Format-List Domain, Type, Valid, Expires, DaysUntilExpiry

# Renew all certificates expiring within 30 days
Get-VergeCertificate | Where-Object { $_.DaysUntilExpiry -lt 30 } | ForEach-Object {
    Write-Host "Renewing certificate: $($_.Domain) (expires in $($_.DaysUntilExpiry) days)"
    Update-VergeCertificate -Key $_.Key -Force
}

#endregion

#region Removing Certificates
# ============================================================================
# REMOVING CERTIFICATES
# ============================================================================

# Remove a certificate by key
Remove-VergeCertificate -Key 2

# Remove without confirmation (for automation)
Remove-VergeCertificate -Key 2 -Confirm:$false

# Remove using pipeline
Get-VergeCertificate -Key 2 | Remove-VergeCertificate

# Remove multiple certificates matching criteria
Get-VergeCertificate | Where-Object { $_.Description -like "*test*" } | Remove-VergeCertificate -Confirm:$false

# Safe removal with confirmation
$certToRemove = Get-VergeCertificate -Key 2
if ($certToRemove) {
    Write-Host "About to remove certificate: $($certToRemove.Domain)"
    Remove-VergeCertificate -Key $certToRemove.Key
}

#endregion

#region Certificate Expiration Monitoring
# ============================================================================
# MONITORING CERTIFICATE EXPIRATION
# ============================================================================

# List certificates sorted by expiration
Get-VergeCertificate | Sort-Object Expires | Format-Table Domain, Type, Valid, DaysUntilExpiry, Expires -AutoSize

# Find certificates expiring within specified days
function Get-ExpiringCertificates {
    param(
        [int]$Days = 30
    )

    Get-VergeCertificate | Where-Object {
        $_.DaysUntilExpiry -lt $Days -and $_.DaysUntilExpiry -ge 0
    } | Sort-Object DaysUntilExpiry
}

# Check for certificates expiring in 30 days
$expiring = Get-ExpiringCertificates -Days 30
if ($expiring) {
    Write-Host "Certificates expiring within 30 days:" -ForegroundColor Yellow
    $expiring | Format-Table Domain, Type, DaysUntilExpiry, Expires -AutoSize
} else {
    Write-Host "No certificates expiring within 30 days." -ForegroundColor Green
}

# Find already expired certificates
$expired = Get-VergeCertificate | Where-Object { $_.DaysUntilExpiry -lt 0 }
if ($expired) {
    Write-Host "EXPIRED CERTIFICATES:" -ForegroundColor Red
    $expired | Format-Table Domain, Type, Expires -AutoSize
}

# Generate certificate health report
function Get-CertificateHealthReport {
    $certs = Get-VergeCertificate

    $report = @{
        Total    = $certs.Count
        Valid    = ($certs | Where-Object Valid).Count
        Expired  = ($certs | Where-Object { $_.DaysUntilExpiry -lt 0 }).Count
        Critical = ($certs | Where-Object { $_.DaysUntilExpiry -ge 0 -and $_.DaysUntilExpiry -lt 7 }).Count
        Warning  = ($certs | Where-Object { $_.DaysUntilExpiry -ge 7 -and $_.DaysUntilExpiry -lt 30 }).Count
        Healthy  = ($certs | Where-Object { $_.DaysUntilExpiry -ge 30 }).Count
    }

    [PSCustomObject]$report
}

Write-Host "`nCertificate Health Summary:"
Get-CertificateHealthReport | Format-List

#endregion

#region Common Certificate Workflows
# ============================================================================
# PRACTICAL CERTIFICATE WORKFLOWS
# ============================================================================

# Workflow: Auto-renew all expiring certificates
function Invoke-CertificateAutoRenewal {
    param(
        [int]$DaysThreshold = 14
    )

    $expiring = Get-VergeCertificate | Where-Object {
        $_.DaysUntilExpiry -lt $DaysThreshold -and
        $_.DaysUntilExpiry -ge 0 -and
        $_.TypeValue -in @('letsencrypt', 'self_signed')
    }

    if (-not $expiring) {
        Write-Host "No certificates need renewal." -ForegroundColor Green
        return
    }

    foreach ($cert in $expiring) {
        Write-Host "Renewing: $($cert.Domain) (Type: $($cert.Type), Expires in: $($cert.DaysUntilExpiry) days)"
        try {
            Update-VergeCertificate -Key $cert.Key -Force
            Write-Host "  Success" -ForegroundColor Green
        }
        catch {
            Write-Host "  Failed: $_" -ForegroundColor Red
        }
    }
}

# Invoke-CertificateAutoRenewal -DaysThreshold 30

# Workflow: Export certificate inventory to CSV
function Export-CertificateInventory {
    param(
        [string]$Path = "certificate-inventory.csv"
    )

    Get-VergeCertificate | Select-Object `
        Key,
        Domain,
        @{N='AdditionalDomains';E={$_.DomainList -join '; '}},
        Type,
        Valid,
        KeyType,
        DaysUntilExpiry,
        Expires,
        Created,
        Description |
        Export-Csv -Path $Path -NoTypeInformation

    Write-Host "Certificate inventory exported to: $Path"
}

# Export-CertificateInventory -Path "certs.csv"

# Workflow: Certificate type summary
function Get-CertificateTypeSummary {
    Get-VergeCertificate | Group-Object Type | ForEach-Object {
        [PSCustomObject]@{
            Type        = $_.Name
            Count       = $_.Count
            ValidCount  = ($_.Group | Where-Object Valid).Count
            AvgDaysLeft = [math]::Round(($_.Group | Where-Object { $_.DaysUntilExpiry -ge 0 } |
                Measure-Object DaysUntilExpiry -Average).Average, 0)
        }
    }
}

Write-Host "`nCertificate Summary by Type:"
Get-CertificateTypeSummary | Format-Table -AutoSize

# Workflow: Backup certificate keys (manual certs only)
function Backup-CertificateKeys {
    param(
        [int]$Key,
        [string]$OutputDirectory = "."
    )

    $cert = Get-VergeCertificate -Key $Key -IncludeKeys

    if (-not $cert) {
        Write-Error "Certificate with Key $Key not found."
        return
    }

    $safeDomain = $cert.Domain -replace '[^a-zA-Z0-9\-\.]', '_'
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $baseFileName = "$safeDomain-$timestamp"

    if ($cert.PublicKey) {
        $pubPath = Join-Path $OutputDirectory "$baseFileName.crt"
        $cert.PublicKey | Set-Content -Path $pubPath -NoNewline
        Write-Host "Public key saved to: $pubPath"
    }

    if ($cert.PrivateKey) {
        $keyPath = Join-Path $OutputDirectory "$baseFileName.key"
        $cert.PrivateKey | Set-Content -Path $keyPath -NoNewline
        Write-Host "Private key saved to: $keyPath"
    }

    if ($cert.Chain) {
        $chainPath = Join-Path $OutputDirectory "$baseFileName-chain.crt"
        $cert.Chain | Set-Content -Path $chainPath -NoNewline
        Write-Host "Chain saved to: $chainPath"
    }
}

# Backup-CertificateKeys -Key 1 -OutputDirectory "./cert-backup"

#endregion

#region Certificate Alerting
# ============================================================================
# CERTIFICATE ALERTING FUNCTIONS
# ============================================================================

# Function to check certificate health and return status
function Test-CertificateHealth {
    param(
        [int]$CriticalDays = 7,
        [int]$WarningDays = 30
    )

    $certs = Get-VergeCertificate
    $results = @()

    foreach ($cert in $certs) {
        $status = switch ($true) {
            { $cert.DaysUntilExpiry -lt 0 } { 'Expired' }
            { $cert.DaysUntilExpiry -lt $CriticalDays } { 'Critical' }
            { $cert.DaysUntilExpiry -lt $WarningDays } { 'Warning' }
            default { 'Healthy' }
        }

        $results += [PSCustomObject]@{
            Domain          = $cert.Domain
            Type            = $cert.Type
            Status          = $status
            DaysUntilExpiry = $cert.DaysUntilExpiry
            Expires         = $cert.Expires
        }
    }

    return $results
}

# Check certificate health
$health = Test-CertificateHealth
Write-Host "`nCertificate Health Status:"
$health | Sort-Object @{E={
    switch ($_.Status) {
        'Expired' { 0 }
        'Critical' { 1 }
        'Warning' { 2 }
        'Healthy' { 3 }
    }
}} | Format-Table Domain, Type, Status, DaysUntilExpiry, Expires -AutoSize

# Show only certificates needing attention
$attention = $health | Where-Object { $_.Status -in @('Expired', 'Critical', 'Warning') }
if ($attention) {
    Write-Host "`nCertificates Needing Attention:" -ForegroundColor Yellow
    $attention | Format-Table -AutoSize
}

#endregion
