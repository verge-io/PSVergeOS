@{
    # Module manifest for PSVergeOS
    # Generated on: 2026-01-22

    # Script module or binary module file associated with this manifest
    RootModule = 'PSVergeOS.psm1'

    # Version number of this module
    ModuleVersion = '0.1.0'

    # Supported PSEditions
    CompatiblePSEditions = @('Core')

    # ID used to uniquely identify this module
    GUID = 'f8a7b3c1-5d2e-4f6a-9b8c-1e2d3f4a5b6c'

    # Author of this module
    Author = 'Verge Engineering'

    # Company or vendor of this module
    CompanyName = 'Verge.io'

    # Copyright statement for this module
    Copyright = '(c) 2026 Verge.io. MIT License.'

    # Description of the functionality provided by this module
    Description = 'PowerShell module for managing VergeOS infrastructure. Provides cmdlets for VM lifecycle, networking, storage, and multi-tenant management through the VergeOS REST API.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.4'

    # Functions to export from this module
    FunctionsToExport = @(
        # Connection
        'Connect-VergeOS'
        'Disconnect-VergeOS'
        'Get-VergeConnection'
        'Set-VergeConnection'

        # VM
        'Get-VergeVM'
        'Start-VergeVM'
        'Stop-VergeVM'
    )

    # Cmdlets to export from this module
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport = @()

    # Private data to pass to the module specified in RootModule
    PrivateData = @{
        PSData = @{
            # Tags applied to this module for discoverability in online galleries
            Tags = @('VergeOS', 'Virtualization', 'Infrastructure', 'Automation', 'VM', 'Hypervisor', 'API')

            # A URL to the license for this module
            LicenseUri = 'https://github.com/verge-io/PSVergeOS/blob/main/LICENSE'

            # A URL to the main website for this project
            ProjectUri = 'https://github.com/verge-io/PSVergeOS'

            # A URL to an icon representing this module
            # IconUri = ''

            # ReleaseNotes of this module
            ReleaseNotes = 'Initial development release'

            # Prerelease string of this module
            Prerelease = 'alpha'

            # Flag to indicate whether the module requires explicit user acceptance for install/update/save
            RequireLicenseAcceptance = $false
        }
    }

    # HelpInfo URI of this module
    # HelpInfoURI = ''
}
