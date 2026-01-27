function Remove-VergeCertificate {
    <#
    .SYNOPSIS
        Deletes an SSL/TLS certificate from VergeOS.

    .DESCRIPTION
        Remove-VergeCertificate deletes one or more SSL/TLS certificates from VergeOS.
        The cmdlet supports pipeline input from Get-VergeCertificate for bulk operations.

    .PARAMETER Domain
        The primary domain of the certificate to delete.

    .PARAMETER Key
        The unique key (ID) of the certificate to delete.

    .PARAMETER Certificate
        A certificate object from Get-VergeCertificate. Accepts pipeline input.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Remove-VergeCertificate -Key 2

        Deletes the certificate with Key 2 after confirmation.

    .EXAMPLE
        Remove-VergeCertificate -Key 2 -Confirm:$false

        Deletes the certificate without confirmation prompt.

    .EXAMPLE
        Get-VergeCertificate -Key 2 | Remove-VergeCertificate

        Deletes a certificate using pipeline input.

    .EXAMPLE
        Get-VergeCertificate | Where-Object { $_.Description -like "*test*" } | Remove-VergeCertificate

        Deletes all certificates with "test" in the description.

    .OUTPUTS
        None

    .NOTES
        Be careful when deleting certificates that are in use by the system or services.
        The default system certificate (typically Key 1) may be protected from deletion.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByKey')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByDomain')]
        [string]$Domain,

        [Parameter(Mandatory, ParameterSetName = 'ByKey')]
        [int]$Key,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByCertificate')]
        [PSTypeName('Verge.Certificate')]
        [PSCustomObject]$Certificate,

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
        # Get certificates to delete based on parameter set
        $certsToDelete = switch ($PSCmdlet.ParameterSetName) {
            'ByDomain' {
                Get-VergeCertificate -Domain $Domain -Server $Server
            }
            'ByKey' {
                Get-VergeCertificate -Key $Key -Server $Server
            }
            'ByCertificate' {
                $Certificate
            }
        }

        foreach ($cert in $certsToDelete) {
            if (-not $cert) {
                continue
            }

            # Build display string for confirmation
            $certDisplay = "$($cert.Domain) (Key: $($cert.Key), Type: $($cert.Type))"

            # Confirm deletion
            if ($PSCmdlet.ShouldProcess($certDisplay, 'Remove Certificate')) {
                try {
                    Write-Verbose "Deleting certificate '$($cert.Domain)' (Key: $($cert.Key))"
                    $null = Invoke-VergeAPI -Method DELETE -Endpoint "certificates/$($cert.Key)" -Connection $Server

                    Write-Verbose "Certificate '$($cert.Domain)' deleted successfully"
                }
                catch {
                    $errorMessage = $_.Exception.Message
                    if ($errorMessage -match 'in use' -or $errorMessage -match 'protected') {
                        Write-Error -Message "Cannot delete certificate '$($cert.Domain)': Certificate is in use or protected." -ErrorId 'CertificateInUse'
                    }
                    else {
                        Write-Error -Message "Failed to delete certificate '$($cert.Domain)': $errorMessage" -ErrorId 'CertificateDeleteFailed'
                    }
                }
            }
        }
    }
}
