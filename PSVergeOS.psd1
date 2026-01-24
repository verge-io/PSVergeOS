@{
    # Module manifest for PSVergeOS
    # Generated on: 2026-01-22

    # Script module or binary module file associated with this manifest
    RootModule = 'PSVergeOS.psm1'

    # Version number of this module
    ModuleVersion = '1.0.0'

    # Supported PSEditions
    CompatiblePSEditions = @('Core')

    # ID used to uniquely identify this module
    GUID = 'f8a7b3c1-5d2e-4f6a-9b8c-1e2d3f4a5b6c'

    # Author of this module
    Author = 'Larry Ludlow (support@verge.io)'

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
        'Get-VergeVMConsole'
        'Import-VergeVM'
        'Move-VergeVM'
        'New-VergeVM'
        'New-VergeVMClone'
        'Remove-VergeVM'
        'Restart-VergeVM'
        'Set-VergeVM'
        'Start-VergeVM'
        'Stop-VergeVM'

        # VM Drives
        'Get-VergeDrive'
        'Import-VergeDrive'
        'New-VergeDrive'
        'Remove-VergeDrive'
        'Set-VergeDrive'

        # VM NICs
        'Get-VergeNIC'
        'New-VergeNIC'
        'Remove-VergeNIC'
        'Set-VergeNIC'

        # VM Snapshots
        'Get-VergeVMSnapshot'
        'New-VergeVMSnapshot'
        'Remove-VergeVMSnapshot'
        'Restore-VergeVMSnapshot'

        # Storage/Files
        'Get-VergeFile'
        'Get-VergeStorageTier'
        'Get-VergevSANStatus'
        'Remove-VergeFile'
        'Save-VergeFile'
        'Send-VergeFile'

        # Network
        'Get-VergeNetwork'
        'Get-VergeNetworkAlias'
        'Get-VergeNetworkHost'
        'Get-VergeNetworkRule'
        'Invoke-VergeNetworkApply'
        'New-VergeNetwork'
        'New-VergeNetworkAlias'
        'New-VergeNetworkHost'
        'New-VergeNetworkRule'
        'Remove-VergeNetwork'
        'Remove-VergeNetworkAlias'
        'Remove-VergeNetworkHost'
        'Remove-VergeNetworkRule'
        'Restart-VergeNetwork'
        'Set-VergeNetwork'
        'Set-VergeNetworkHost'
        'Set-VergeNetworkRule'
        'Start-VergeNetwork'
        'Stop-VergeNetwork'

        # DNS
        'Get-VergeDNSRecord'
        'Get-VergeDNSZone'
        'New-VergeDNSRecord'
        'Remove-VergeDNSRecord'

        # Network Diagnostics
        'Get-VergeNetworkDiagnostics'
        'Get-VergeNetworkStatistics'

        # IPSec VPN
        'Get-VergeIPSecConnection'
        'Get-VergeIPSecPolicy'
        'New-VergeIPSecConnection'
        'New-VergeIPSecPolicy'
        'Remove-VergeIPSecConnection'
        'Remove-VergeIPSecPolicy'
        'Set-VergeIPSecConnection'

        # WireGuard VPN
        'Get-VergeWireGuard'
        'Get-VergeWireGuardPeer'
        'New-VergeWireGuard'
        'New-VergeWireGuardPeer'
        'Remove-VergeWireGuard'
        'Remove-VergeWireGuardPeer'
        'Set-VergeWireGuard'

        # NAS Services
        'Get-VergeNASService'
        'New-VergeNASService'
        'Set-VergeNASService'
        'Remove-VergeNASService'
        'Get-VergeNASCIFSSettings'
        'Set-VergeNASCIFSSettings'
        'Get-VergeNASNFSSettings'
        'Set-VergeNASNFSSettings'

        # NAS Volumes
        'Get-VergeNASVolume'
        'New-VergeNASVolume'
        'Set-VergeNASVolume'
        'Remove-VergeNASVolume'
        'Get-VergeNASVolumeSnapshot'
        'New-VergeNASVolumeSnapshot'
        'Remove-VergeNASVolumeSnapshot'

        # NAS CIFS Shares
        'Get-VergeNASCIFSShare'
        'New-VergeNASCIFSShare'
        'Set-VergeNASCIFSShare'
        'Remove-VergeNASCIFSShare'

        # NAS NFS Shares
        'Get-VergeNASNFSShare'
        'New-VergeNASNFSShare'
        'Set-VergeNASNFSShare'
        'Remove-VergeNASNFSShare'

        # NAS Local Users
        'Get-VergeNASUser'
        'New-VergeNASUser'
        'Set-VergeNASUser'
        'Remove-VergeNASUser'
        'Enable-VergeNASUser'
        'Disable-VergeNASUser'

        # NAS Volume Sync
        'Get-VergeNASVolumeSync'
        'New-VergeNASVolumeSync'
        'Set-VergeNASVolumeSync'
        'Remove-VergeNASVolumeSync'
        'Start-VergeNASVolumeSync'
        'Stop-VergeNASVolumeSync'

        # NAS Volume Browser
        'Get-VergeNASVolumeFile'

        # Users
        'Get-VergeUser'
        'New-VergeUser'
        'Set-VergeUser'
        'Remove-VergeUser'
        'Enable-VergeUser'
        'Disable-VergeUser'

        # API Keys
        'Get-VergeAPIKey'
        'New-VergeAPIKey'
        'Remove-VergeAPIKey'

        # Groups
        'Get-VergeGroup'
        'New-VergeGroup'
        'Set-VergeGroup'
        'Remove-VergeGroup'

        # Group Members
        'Get-VergeGroupMember'
        'Add-VergeGroupMember'
        'Remove-VergeGroupMember'

        # Permissions
        'Get-VergePermission'
        'Grant-VergePermission'
        'Revoke-VergePermission'

        # Tenants
        'Get-VergeTenant'
        'New-VergeTenant'
        'Set-VergeTenant'
        'Remove-VergeTenant'
        'Start-VergeTenant'
        'Stop-VergeTenant'
        'Restart-VergeTenant'
        'New-VergeTenantClone'
        'Get-VergeTenantSnapshot'
        'New-VergeTenantSnapshot'
        'Remove-VergeTenantSnapshot'
        'Restore-VergeTenantSnapshot'
        'Get-VergeTenantStorage'
        'New-VergeTenantStorage'
        'Set-VergeTenantStorage'
        'Remove-VergeTenantStorage'
        'Get-VergeTenantExternalIP'
        'New-VergeTenantExternalIP'
        'Remove-VergeTenantExternalIP'
        'Get-VergeTenantNetworkBlock'
        'New-VergeTenantNetworkBlock'
        'Remove-VergeTenantNetworkBlock'
        'Connect-VergeTenantContext'
        'Get-VergeSharedObject'
        'New-VergeSharedObject'
        'Import-VergeSharedObject'
        'Remove-VergeSharedObject'
        'New-VergeTenantCrashCart'
        'Remove-VergeTenantCrashCart'
        'Enable-VergeTenantIsolation'
        'Disable-VergeTenantIsolation'
        'Send-VergeTenantFile'
        'Get-VergeTenantLayer2Network'
        'New-VergeTenantLayer2Network'
        'Set-VergeTenantLayer2Network'
        'Remove-VergeTenantLayer2Network'

        # System
        'Get-VergeVersion'
        'Get-VergeCluster'
        'New-VergeCluster'
        'Set-VergeCluster'
        'Remove-VergeCluster'
        'Get-VergeNode'
        'Enable-VergeNodeMaintenance'
        'Disable-VergeNodeMaintenance'
        'Restart-VergeNode'
        'Get-VergeSystemStatistics'
        'Get-VergeSystemSetting'
        'Get-VergeLicense'
        'Get-VergeNodeDriver'
        'Get-VergeNodeDevice'

        # Tasks/Monitoring
        'Get-VergeTask'
        'Wait-VergeTask'
        'Stop-VergeTask'
        'Enable-VergeTask'

        # Alarms
        'Get-VergeAlarm'
        'Set-VergeAlarm'

        # Logs
        'Get-VergeLog'

        # Backup/DR - Snapshot Profiles
        'Get-VergeSnapshotProfile'
        'New-VergeSnapshotProfile'
        'Set-VergeSnapshotProfile'
        'Remove-VergeSnapshotProfile'

        # Backup/DR - Cloud Snapshots
        'Get-VergeCloudSnapshot'
        'New-VergeCloudSnapshot'
        'Remove-VergeCloudSnapshot'
        'Restore-VergeVMFromCloudSnapshot'
        'Restore-VergeTenantFromCloudSnapshot'

        # Backup/DR - Sites
        'Get-VergeSite'
        'New-VergeSite'
        'Remove-VergeSite'

        # Backup/DR - Site Syncs
        'Get-VergeSiteSync'
        'Get-VergeSiteSyncIncoming'
        'Start-VergeSiteSync'
        'Stop-VergeSiteSync'
        'Invoke-VergeSiteSync'

        # Backup/DR - Site Sync Schedules
        'Get-VergeSiteSyncSchedule'
        'New-VergeSiteSyncSchedule'
        'Remove-VergeSiteSyncSchedule'
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

            # SPDX license expression
            License = 'MIT'

            # A URL to the main website for this project
            ProjectUri = 'https://github.com/verge-io/PSVergeOS'

            # A URL to an icon representing this module
            # IconUri = ''

            # README file to display on PowerShell Gallery
            Readme = 'README.md'

            # ReleaseNotes of this module
            ReleaseNotes = 'Initial stable release. Full VergeOS API coverage for VM lifecycle, networking, storage, NAS, tenants, backup/DR, and monitoring.'

            # Flag to indicate whether the module requires explicit user acceptance for install/update/save
            RequireLicenseAcceptance = $false
        }
    }

    # HelpInfo URI of this module
    # HelpInfoURI = ''
}
