#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for PSVergeOS Get-VergeVM cmdlet.

.DESCRIPTION
    Tests for Get-VergeVM cmdlet.
#>

BeforeAll {
    # Import the module
    $ModulePath = Join-Path -Path $PSScriptRoot -ChildPath '../../PSVergeOS.psd1'
    Import-Module $ModulePath -Force

    InModuleScope PSVergeOS {
        $script:DefaultConnection = [PSCustomObject]@{ Server = 'test.local' }
    }
}

AfterAll {
    # Clean up
    Remove-Module PSVergeOS -Force -ErrorAction SilentlyContinue
}

Describe 'Get-VergeVM' {
    BeforeAll {
        $vmFixture = Get-Content "$PSScriptRoot/Fixtures/vms.json" -Raw | ConvertFrom-Json
        Mock -ModuleName PSVergeOS Invoke-VergeAPI -ParameterFilter { $Method -eq 'GET' } { $vmFixture }
    }

    Context 'Output' {
        It 'Returns all VMs when no filter is applied' {
            (Get-VergeVM).Count | Should -Be 2
        }

        It 'Maps allow_export to AllowExport' {
            $vms = Get-VergeVM

            ($vms | Where-Object Name -eq 'LAB-VM1').AllowExport    | Should -Be $True
            ($vms | Where-Object Name -eq 'LAB-VM2').AllowExport    | Should -Be $False
        }

        It 'Requests the <Field> field fields from the API' -ForEach @(
            @{ Field = 'allow_export' }
            @{ Field = 'owner_user' }
            @{ Field = 'boot_delay' }
            @{ Field = 'nested_virtualization' }
            @{ Field = 'note' }
        ) {
            Get-VergeVM | Out-Null

            Should -Invoke -ModuleName PSVergeOS Invoke-VergeAPI -ParameterFilter {
                ($Query.fields -split ',') -contains $Field
            }
        }

        It 'Maps allow_export to AllowExport' {
            $vms = Get-VergeVM

            ($vms | Where-Object Name -eq 'LAB-VM1').AllowExport    | Should -Be $True
            ($vms | Where-Object Name -eq 'LAB-VM2').AllowExport    | Should -Be $False
        }

        It 'Maps owner_user to OwnerUser' {
            $vms = Get-VergeVM

            ($vms | Where-Object Name -eq 'LAB-VM1').OwnerUser      | Should -Be 1
            ($vms | Where-Object Name -eq 'LAB-VM2').OwnerUser      | Should -Be $Null 
        }

        It 'Maps boot_delay to BootDelay' {
            $vms = Get-VergeVM

            ($vms | Where-Object Name -eq 'LAB-VM1').BootDelay      | Should -Be 5
            ($vms | Where-Object Name -eq 'LAB-VM2').BootDelay      | Should -Be 20
        }
        
        It 'Maps nexted_virtualization to NestedVirtualization' {
            $vms = Get-VergeVM

            ($vms | Where-Object Name -eq 'LAB-VM1').NestedVirtualization   | Should -Be $True
            ($vms | Where-Object Name -eq 'LAB-VM2').NestedVirtualization   | Should -Be $False
        }

        It 'Maps note to Note' {
            $vms = Get-VergeVM

            ($vms | Where-Object Name -eq 'LAB-VM1').Note   | Should -Be "Testing this note`nnew lines as well?`nMaybe..."
            ($vms | Where-Object Name -eq 'LAB-VM2').Note   | Should -Be ""
        }
    }
}
