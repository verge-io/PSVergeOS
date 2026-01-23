function Invoke-VergeAPI {
    <#
    .SYNOPSIS
        Internal function to make HTTP requests to the VergeOS API.

    .DESCRIPTION
        Invoke-VergeAPI is the core HTTP client for all VergeOS API operations.
        It handles authentication, TLS configuration, error handling, and pagination.

    .PARAMETER Method
        The HTTP method (GET, POST, PUT, DELETE, PATCH).

    .PARAMETER Endpoint
        The API endpoint path (e.g., 'vms', 'vnets/123').

    .PARAMETER Body
        The request body for POST/PUT/PATCH requests.

    .PARAMETER Query
        Query string parameters as a hashtable.

    .PARAMETER Connection
        The VergeConnection object to use. Defaults to the current default connection.

    .EXAMPLE
        Invoke-VergeAPI -Method GET -Endpoint 'vms'

    .EXAMPLE
        Invoke-VergeAPI -Method POST -Endpoint 'vm_actions' -Body @{ action = 'poweron'; vm = 123 }

    .NOTES
        This is an internal function and should not be called directly by users.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE', 'PATCH')]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Endpoint,

        [Parameter()]
        [hashtable]$Body,

        [Parameter()]
        [hashtable]$Query,

        [Parameter()]
        [object]$Connection
    )

    # Get connection
    if (-not $Connection) {
        $Connection = $script:DefaultConnection
    }

    if (-not $Connection) {
        throw [System.InvalidOperationException]::new(
            'Not connected to VergeOS. Use Connect-VergeOS to establish a connection.'
        )
    }

    if (-not $Connection.IsTokenValid()) {
        throw [System.InvalidOperationException]::new(
            "Session token is invalid or expired for '$($Connection.Server)'. Please reconnect."
        )
    }

    # Build URI
    $uri = "$($Connection.ApiBaseUrl)/$Endpoint"

    # Add query parameters
    if ($Query -and $Query.Count -gt 0) {
        $queryParts = foreach ($key in $Query.Keys) {
            $encodedKey = [System.Uri]::EscapeDataString($key)
            $encodedValue = [System.Uri]::EscapeDataString($Query[$key])
            "$encodedKey=$encodedValue"
        }
        $uri = "$uri`?$($queryParts -join '&')"
    }

    # Build authorization header based on auth type
    $authType = if ($Connection.AuthType) { $Connection.AuthType } else { 'Basic' }
    $authHeader = "$authType $($Connection.Token)"

    # Build request parameters
    $requestParams = @{
        Method  = $Method
        Uri     = $uri
        Headers = @{
            'Authorization' = $authHeader
            'Content-Type'  = 'application/json'
            'Accept'        = 'application/json'
        }
    }

    # Add body for POST/PUT/PATCH
    if ($Body -and $Method -in @('POST', 'PUT', 'PATCH')) {
        $requestParams['Body'] = ($Body | ConvertTo-Json -Depth 10 -Compress)
    }

    # Handle certificate validation
    if ($Connection.SkipCertificateCheck) {
        $requestParams['SkipCertificateCheck'] = $true
    }

    # Make the request
    Write-Verbose "[$Method] $uri"

    try {
        $response = Invoke-RestMethod @requestParams -ErrorAction Stop
        return $response
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $errorMessage = $_.ErrorDetails.Message

        # Try to parse error response
        if ($errorMessage) {
            try {
                $errorObj = $errorMessage | ConvertFrom-Json
                # Check for error message in various fields (handle both string and bool 'err')
                if ($errorObj.err -and $errorObj.err -is [string]) {
                    $errorMessage = $errorObj.err
                }
                elseif ($errorObj.error -and $errorObj.error -is [string]) {
                    $errorMessage = $errorObj.error
                }
                elseif ($errorObj.message -and $errorObj.message -is [string]) {
                    $errorMessage = $errorObj.message
                }
                elseif ($errorObj.err -eq $true -and $errorObj.message) {
                    $errorMessage = $errorObj.message
                }
                # Keep original error message if no string found
            }
            catch {
                # Keep original error message
            }
        }

        $fullError = "VergeOS API Error [$statusCode]: $errorMessage"

        switch ($statusCode) {
            401 { throw [System.UnauthorizedAccessException]::new($fullError) }
            403 { throw [System.UnauthorizedAccessException]::new($fullError) }
            404 { throw [System.Management.Automation.ItemNotFoundException]::new($fullError) }
            default { throw [System.Net.Http.HttpRequestException]::new($fullError) }
        }
    }
}
