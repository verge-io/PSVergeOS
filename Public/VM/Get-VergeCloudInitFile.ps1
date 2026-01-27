function Get-VergeCloudInitFile {
    <#
    .SYNOPSIS
        Retrieves cloud-init files from VergeOS.

    .DESCRIPTION
        Get-VergeCloudInitFile retrieves one or more cloud-init files from a VergeOS system.
        Cloud-init files are used for VM provisioning automation, providing user-data,
        meta-data, and other configuration files to VMs during boot.

    .PARAMETER VMId
        Filter cloud-init files by the VM ID they belong to.

    .PARAMETER Name
        The name of the cloud-init file to retrieve. Supports wildcards (* and ?).
        If not specified, all cloud-init files are returned.

    .PARAMETER Key
        The unique key (ID) of the cloud-init file to retrieve.

    .PARAMETER Render
        Filter cloud-init files by render type: No, Variables, or Jinja2.

    .PARAMETER IncludeContents
        Include the file contents in the output. By default, contents are excluded
        for listing operations to reduce data transfer.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeCloudInitFile

        Retrieves all cloud-init files from the connected VergeOS system.

    .EXAMPLE
        Get-VergeCloudInitFile -Name "user-data"

        Retrieves the cloud-init file named "user-data".

    .EXAMPLE
        Get-VergeCloudInitFile -Name "*.yaml" -IncludeContents

        Retrieves all YAML cloud-init files including their contents.

    .EXAMPLE
        Get-VergeCloudInitFile -Render Variables

        Retrieves all cloud-init files that use variable rendering.

    .EXAMPLE
        Get-VergeCloudInitFile -Key 5

        Retrieves a specific cloud-init file by its key.

    .EXAMPLE
        Get-VergeCloudInitFile -VMId 30

        Retrieves all cloud-init files belonging to VM 30.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.CloudInitFile'

    .NOTES
        Cloud-init files have a maximum size of 65536 bytes (64KB).

        Render types:
        - No: File is used as-is without any processing
        - Variables: File supports VergeOS variable substitution
        - Jinja2: File is processed as a Jinja2 template
    #>
    [CmdletBinding(DefaultParameterSetName = 'Filter')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'Filter')]
        [int]$VMId,

        [Parameter(Position = 0, ParameterSetName = 'Filter')]
        [SupportsWildcards()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByKey', ValueFromPipelineByPropertyName)]
        [Alias('Id', '$key')]
        [int]$Key,

        [Parameter(ParameterSetName = 'Filter')]
        [ValidateSet('No', 'Variables', 'Jinja2')]
        [string]$Render,

        [Parameter()]
        [switch]$IncludeContents,

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

        # Map friendly render names to API values
        $renderMapping = @{
            'No'        = 'no'
            'Variables' = 'variables'
            'Jinja2'    = 'jinja2'
        }

        # Map API render values to friendly names
        $renderDisplayMapping = @{
            'no'        = 'No'
            'variables' = 'Variables'
            'jinja2'    = 'Jinja2'
        }
    }

    process {
        try {
            Write-Verbose "Querying cloud-init files from $($Server.Server)"

            # Build query parameters
            $queryParams = @{}
            $filters = [System.Collections.Generic.List[string]]::new()

            # Filter by key
            if ($PSCmdlet.ParameterSetName -eq 'ByKey') {
                $filters.Add("`$key eq $Key")
            }
            else {
                # Filter by VM ID
                if ($VMId) {
                    $filters.Add("owner eq 'vms/$VMId'")
                }

                # Filter by name
                if ($Name) {
                    if ($Name -match '[\*\?]') {
                        # Wildcard search - use contains for partial match
                        $searchTerm = $Name -replace '[\*\?]', ''
                        if ($searchTerm) {
                            $filters.Add("name ct '$searchTerm'")
                        }
                    }
                    else {
                        $filters.Add("name eq '$Name'")
                    }
                }

                # Filter by render type
                if ($Render) {
                    $apiRender = $renderMapping[$Render]
                    $filters.Add("render eq '$apiRender'")
                }
            }

            # Apply filters
            if ($filters.Count -gt 0) {
                $queryParams['filter'] = $filters -join ' and '
            }

            # Request fields
            $fieldList = @(
                '$key'
                'owner'
                'name'
                'filesize'
                'allocated_bytes'
                'used_bytes'
                'modified'
                'contains_variables'
                'render'
                'creator'
            )

            # Include contents if requested or fetching by key
            if ($IncludeContents -or $PSCmdlet.ParameterSetName -eq 'ByKey') {
                $fieldList += 'contents'
            }

            $queryParams['fields'] = $fieldList -join ','

            $response = Invoke-VergeAPI -Method GET -Endpoint 'cloudinit_files' -Query $queryParams -Connection $Server

            # Handle both single object and array responses
            $files = if ($response -is [array]) { $response } else { @($response) }

            foreach ($file in $files) {
                # Skip null entries
                if (-not $file -or -not $file.'$key') {
                    continue
                }

                # Apply wildcard filtering for client-side matching
                if ($Name -and ($Name -match '[\*\?]')) {
                    if ($file.name -notlike $Name) {
                        continue
                    }
                }

                # Get render display name
                $renderDisplay = $renderDisplayMapping[$file.render]
                if (-not $renderDisplay) {
                    $renderDisplay = $file.render
                }

                # Create output object
                $output = [PSCustomObject]@{
                    PSTypeName         = 'Verge.CloudInitFile'
                    Key                = [int]$file.'$key'
                    Name               = $file.name
                    FileSize           = [int64]$file.filesize
                    AllocatedBytes     = [int64]$file.allocated_bytes
                    UsedBytes          = [int64]$file.used_bytes
                    Render             = $renderDisplay
                    RenderValue        = $file.render
                    ContainsVariables  = [bool]$file.contains_variables
                    Creator            = $file.creator
                    Owner              = $file.owner
                    Modified           = if ($file.modified) { [DateTimeOffset]::FromUnixTimeSeconds($file.modified).LocalDateTime } else { $null }
                }

                # Add contents if requested or fetching by key
                if ($IncludeContents -or $PSCmdlet.ParameterSetName -eq 'ByKey') {
                    $output | Add-Member -MemberType NoteProperty -Name 'Contents' -Value $file.contents
                }

                # Add hidden properties for pipeline support
                $output | Add-Member -MemberType NoteProperty -Name '_Connection' -Value $Server -Force

                Write-Output $output
            }
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}
