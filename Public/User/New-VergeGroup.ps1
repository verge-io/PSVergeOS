function New-VergeGroup {
    <#
    .SYNOPSIS
        Creates a new group in VergeOS.

    .DESCRIPTION
        New-VergeGroup creates a new group that can be used for organizing
        users and assigning permissions.

    .PARAMETER Name
        The name of the group. Must be unique and 1-128 characters.

    .PARAMETER Description
        An optional description for the group.

    .PARAMETER Email
        An optional email address for the group.

    .PARAMETER Enabled
        Whether the group is enabled. Default is $true.

    .PARAMETER PassThru
        Return the created group object.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        New-VergeGroup -Name "Developers"

        Creates a new group named Developers.

    .EXAMPLE
        New-VergeGroup -Name "QA Team" -Description "Quality Assurance team" -Email "qa@company.com" -PassThru

        Creates a new group with description and email, returning the group object.

    .OUTPUTS
        None by default. Verge.Group when -PassThru is specified.

    .NOTES
        Use Add-VergeGroupMember to add users to the group.
        Use Grant-VergePermission to assign permissions to the group.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [ValidateLength(1, 128)]
        [string]$Name,

        [Parameter()]
        [ValidateLength(0, 2048)]
        [string]$Description,

        [Parameter()]
        [ValidatePattern('^[a-zA-Z0-9.!#$%&''*+/=?^_`{|}~-]+@([a-zA-Z0-9][a-zA-Z0-9_-]{0,61}[a-zA-Z0-9])+(\.[a-zA-Z0-9][a-zA-Z0-9_-]{0,61}[a-zA-Z0-9])*$', ErrorMessage = 'Invalid email address format')]
        [string]$Email,

        [Parameter()]
        [bool]$Enabled = $true,

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
        # Build request body
        $body = @{
            name    = $Name
            enabled = $Enabled
        }

        if ($Description) {
            $body['description'] = $Description
        }

        if ($Email) {
            $body['email'] = $Email.ToLower()
        }

        if ($PSCmdlet.ShouldProcess($Name, 'Create Group')) {
            try {
                Write-Verbose "Creating group '$Name'"
                $response = Invoke-VergeAPI -Method POST -Endpoint 'groups' -Body $body -Connection $Server

                # Get the created group key
                $groupKey = $response.'$key'

                Write-Verbose "Group '$Name' created with Key: $groupKey"

                if ($PassThru -and $groupKey) {
                    Start-Sleep -Milliseconds 500
                    Get-VergeGroup -Key $groupKey -Server $Server
                }
            }
            catch {
                $errorMessage = $_.Exception.Message
                if ($errorMessage -match 'already in use') {
                    throw "A group with the name '$Name' already exists."
                }
                throw "Failed to create group '$Name': $errorMessage"
            }
        }
    }
}
