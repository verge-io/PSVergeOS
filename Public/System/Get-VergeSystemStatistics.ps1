function Get-VergeSystemStatistics {
    <#
    .SYNOPSIS
        Retrieves system dashboard statistics from VergeOS.

    .DESCRIPTION
        Get-VergeSystemStatistics retrieves overview statistics for a VergeOS system
        including counts of VMs, tenants, networks, nodes, clusters, storage tiers,
        users, groups, and alarms.

    .PARAMETER Server
        The VergeOS connection to use. Defaults to the current default connection.

    .EXAMPLE
        Get-VergeSystemStatistics

        Retrieves dashboard statistics from the connected VergeOS system.

    .EXAMPLE
        Get-VergeSystemStatistics | Select-Object VMs*, Nodes*, Storage*

        Shows VM, node, and storage statistics.

    .OUTPUTS
        PSCustomObject with PSTypeName 'Verge.SystemStatistics'

    .NOTES
        This cmdlet provides a quick overview of system health and resource status.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
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
        try {
            Write-Verbose "Querying system statistics from $($Server.Server)"

            $response = Invoke-VergeAPI -Method GET -Endpoint 'dashboard' -Connection $Server

            # Helper function to safely extract count values
            function Get-CountValue {
                param($Value)
                if ($null -eq $Value) { return 0 }
                if ($Value -is [int] -or $Value -is [long]) { return [int]$Value }
                if ($Value -is [PSCustomObject]) {
                    # Handle objects like { "$count": 0 } or { "instances_total": 0 }
                    if ($null -ne $Value.'$count') { return [int]$Value.'$count' }
                    if ($null -ne $Value.instances_total) { return [int]$Value.instances_total }
                }
                return 0
            }

            # Create output object with organized statistics
            $output = [PSCustomObject]@{
                PSTypeName              = 'Verge.SystemStatistics'

                # VM Statistics
                VMsTotal                = Get-CountValue $response.machines_count
                VMsOnline               = Get-CountValue $response.machines_online
                VMsWarning              = Get-CountValue $response.machines_warn
                VMsError                = Get-CountValue $response.machines_error

                # Tenant Statistics
                TenantsTotal            = Get-CountValue $response.tenants_count
                TenantsOnline           = Get-CountValue $response.tenants_online
                TenantsWarning          = Get-CountValue $response.tenants_warn
                TenantsError            = Get-CountValue $response.tenants_error

                # Network Statistics
                NetworksTotal           = Get-CountValue $response.vnets_count
                NetworksOnline          = Get-CountValue $response.vnets_online
                NetworksWarning         = Get-CountValue $response.vnets_warn
                NetworksError           = Get-CountValue $response.vnets_error

                # Node Statistics
                NodesTotal              = Get-CountValue $response.nodes_count
                NodesOnline             = Get-CountValue $response.nodes_online
                NodesWarning            = Get-CountValue $response.nodes_warn
                NodesError              = Get-CountValue $response.nodes_error

                # Cluster Statistics
                ClustersTotal           = Get-CountValue $response.clusters_count
                ClustersOnline          = Get-CountValue $response.clusters_online
                ClustersWarning         = Get-CountValue $response.clusters_warn
                ClustersError           = Get-CountValue $response.clusters_error

                # Storage Tier Statistics
                StorageTiersTotal       = Get-CountValue $response.storage_tiers_count
                ClusterTiersTotal       = Get-CountValue $response.cluster_tiers_count
                ClusterTiersOnline      = Get-CountValue $response.cluster_tiers_online
                ClusterTiersWarning     = Get-CountValue $response.cluster_tiers_warn
                ClusterTiersError       = Get-CountValue $response.cluster_tiers_error

                # User and Group Statistics
                UsersTotal              = Get-CountValue $response.users_count
                UsersEnabled            = Get-CountValue $response.users_online
                GroupsTotal             = Get-CountValue $response.groups_count
                GroupsEnabled           = Get-CountValue $response.groups_online

                # Site Statistics
                SitesTotal              = Get-CountValue $response.sites_count
                SitesOnline             = Get-CountValue $response.sites_online
                SitesWarning            = Get-CountValue $response.sites_warn
                SitesError              = Get-CountValue $response.sites_error

                # Repository Statistics
                RepositoriesTotal       = Get-CountValue $response.repos_count
                RepositoriesOnline      = Get-CountValue $response.repos_online
                RepositoriesWarning     = Get-CountValue $response.repos_warn
                RepositoriesError       = Get-CountValue $response.repos_error

                # Alarm Statistics
                AlarmsTotal             = Get-CountValue $response.alarms_count
                AlarmsWarning           = Get-CountValue $response.alarms_warning
                AlarmsError             = Get-CountValue $response.alarms_error

                # Device Resource Statistics
                ResourceInstanceCount   = Get-CountValue $response.resource_instance_count
                ResourceInstanceMax     = Get-CountValue $response.resource_instance_max

                # Server info
                Server                  = $Server.Server
            }

            # Add hidden properties for pipeline support
            $output | Add-Member -MemberType NoteProperty -Name '_Connection' -Value $Server -Force

            Write-Output $output
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}
