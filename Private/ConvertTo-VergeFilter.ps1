function ConvertTo-VergeFilter {
    <#
    .SYNOPSIS
        Converts filter parameters to VergeOS API filter syntax.

    .DESCRIPTION
        Takes PowerShell-style filter parameters and converts them to the
        VergeOS API filter query string format.

    .PARAMETER Filters
        A hashtable of filter conditions.

    .EXAMPLE
        ConvertTo-VergeFilter -Filters @{ name = 'Web*'; status = 'running' }
        # Returns: "name like 'Web%' and status eq 'running'"

    .NOTES
        This is an internal function.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Filters
    )

    $filterParts = [System.Collections.Generic.List[string]]::new()

    foreach ($key in $Filters.Keys) {
        $value = $Filters[$key]

        if ($null -eq $value) {
            continue
        }

        # Handle wildcards - convert to LIKE query
        if ($value -is [string] -and $value -match '\*') {
            $likeValue = $value -replace '\*', '%'
            $filterParts.Add("$key like '$likeValue'")
        }
        # Handle arrays - convert to IN query
        elseif ($value -is [array]) {
            $inValues = ($value | ForEach-Object { "'$_'" }) -join ','
            $filterParts.Add("$key in ($inValues)")
        }
        # Handle booleans
        elseif ($value -is [bool]) {
            $boolValue = if ($value) { 'true' } else { 'false' }
            $filterParts.Add("$key eq $boolValue")
        }
        # Handle numbers
        elseif ($value -is [int] -or $value -is [long] -or $value -is [double]) {
            $filterParts.Add("$key eq $value")
        }
        # Handle strings
        else {
            $filterParts.Add("$key eq '$value'")
        }
    }

    if ($filterParts.Count -eq 0) {
        return $null
    }

    return $filterParts -join ' and '
}
