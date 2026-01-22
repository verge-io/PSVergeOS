<#
.SYNOPSIS
    Represents a connection to a VergeOS system.

.DESCRIPTION
    The VergeConnection class stores connection state including server address,
    authentication tokens, and session information.
#>

class VergeConnection {
    [string]$Server
    [string]$ApiBaseUrl
    [string]$Token
    [datetime]$TokenExpires
    [string]$Username
    [bool]$SkipCertificateCheck
    [datetime]$ConnectedAt
    [string]$VergeOSVersion
    [bool]$IsConnected

    VergeConnection() {
        $this.IsConnected = $false
        $this.SkipCertificateCheck = $false
    }

    VergeConnection([string]$server) {
        $this.Server = $server
        $this.ApiBaseUrl = "https://$server/api/v4"
        $this.IsConnected = $false
        $this.SkipCertificateCheck = $false
    }

    [string] ToString() {
        $status = if ($this.IsConnected) { 'Connected' } else { 'Disconnected' }
        return "$($this.Server) ($status)"
    }

    [bool] IsTokenValid() {
        if (-not $this.Token) {
            return $false
        }
        # Only check expiration if a real expiration was set (not default MinValue)
        if ($this.TokenExpires -gt [datetime]::MinValue -and $this.TokenExpires -lt [datetime]::UtcNow) {
            return $false
        }
        return $true
    }

    [void] Disconnect() {
        $this.Token = $null
        $this.TokenExpires = [datetime]::MinValue
        $this.IsConnected = $false
    }
}
