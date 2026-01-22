#Requires -Version 7.4
<#
.SYNOPSIS
    PSVergeOS - PowerShell module for VergeOS infrastructure management.

.DESCRIPTION
    This module provides cmdlets for managing VergeOS infrastructure through the REST API.
    It supports VM lifecycle, networking, storage, and multi-tenant management.

.NOTES
    Author: Verge Engineering
    Version: 0.1.0
    Requires: PowerShell 7.4+, VergeOS 26.0+
#>

# Module-level variables for connection state
$script:VergeConnections = [System.Collections.Generic.List[PSCustomObject]]::new()
$script:DefaultConnection = $null

# Get the module root path
$ModuleRoot = $PSScriptRoot

# Import Classes first (order matters for dependencies)
$classFiles = @(
    'VergeConnection.ps1'
)

foreach ($file in $classFiles) {
    $classPath = Join-Path -Path $ModuleRoot -ChildPath "Classes/$file"
    if (Test-Path -Path $classPath) {
        . $classPath
    }
}

# Import Private functions
$privatePath = Join-Path -Path $ModuleRoot -ChildPath 'Private'
if (Test-Path -Path $privatePath) {
    $privateFiles = Get-ChildItem -Path $privatePath -Filter '*.ps1' -Recurse -ErrorAction SilentlyContinue
    foreach ($file in $privateFiles) {
        try {
            . $file.FullName
        }
        catch {
            Write-Error -Message "Failed to import private function '$($file.FullName)': $_"
        }
    }
}

# Import Public functions
$publicPath = Join-Path -Path $ModuleRoot -ChildPath 'Public'
if (Test-Path -Path $publicPath) {
    $publicFiles = Get-ChildItem -Path $publicPath -Filter '*.ps1' -Recurse -ErrorAction SilentlyContinue
    foreach ($file in $publicFiles) {
        try {
            . $file.FullName
        }
        catch {
            Write-Error -Message "Failed to import public function '$($file.FullName)': $_"
        }
    }
}

# Module cleanup when removed
$ExecutionContext.SessionState.Module.OnRemove = {
    # Disconnect all active connections
    if ($script:VergeConnections.Count -gt 0) {
        Write-Verbose "Cleaning up $($script:VergeConnections.Count) VergeOS connection(s)"
        $script:VergeConnections.Clear()
        $script:DefaultConnection = $null
    }
}
