#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for PSVergeOS Set-VergeVM cmdlet.

.DESCRIPTION
    Tests for Set-VergeVM cmdlet.
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

Describe 'Set-VergeVM' {
    BeforeAll {
        Mock -ModuleName PSVergeOS Invoke-VergeAPI -ParameterFilter { $Method -eq 'GET' } {
            @(
                [PSCustomObject]@{
                    '$key'       = 1
                    name         = 'TestVM'
                    status       = 'running'
                    allow_export = $true
                    is_snapshot  = $False
                }
            )
        }
    
        Mock -ModuleName PSVergeOS Invoke-VergeAPI -ParameterFilter { $Method -eq 'PUT' } { }
    }

    Context 'Parameter Validation' {
        It 'Should require AllowExport to be a boolean' -ForEach @(
            @{ Description = 'a string';            Value = 'true' }
            @{ Description = 'a PSCustomObject';    Value = [PSCustomObject]@{ a = 1 } }
            @{ Description = 'null';                Value = $Null }
        ) {
            { Set-VergeVM -key 1 -AllowExport $Value } | 
                Should -Throw -ErrorId 'ParameterArgumentTransformationError*'
        }

        It 'Should require NestedVirtualization to be a boolean' -ForEach @(
            @{ Description = 'a string';            Value = 'true' }
            @{ Description = 'a PSCustomObject';    Value = [PSCustomObject]@{ a = 1 } }
            @{ Description = 'null';                Value = $Null }
        ) {
            { Set-VergeVM -Key 1 -NestedVirtualization $Value } |
                Should -Throw -ErrorId 'ParameterArgumentTransformationError*'
        }
    }

    Context 'Output' {
        It 'Includes the <field> = <value> field in the API call' -ForEach @(
            @{ Field = 'allow_export';              Params = 'AllowExport';                 Value = $True }
            @{ Field = 'allow_export';              Params = 'AllowExport';                 Value = $False }
            @{ Field = 'nested_virtualization';     Params = 'NestedVirtualization';        Value = $True }
            @{ Field = 'nested_virtualization';     Params = 'NestedVirtualization';        Value = $False }
            @{ Field = 'note';                      Params = 'Note';                        Value = 'Testing`nmultiline text.' }
            @{ Field = 'note';                      Params = 'Note';                        Value = '' }
            @{ Field = 'note';                      Params = 'Note';                        Value = $True }
            @{ Field = 'note';                      Params = 'Note';                        Value = [PSCustomObject]@{ a = 1 } }
        ) {
            $arg = @{ $Params = $Value }
            Set-VergeVM -key 1 @arg
            
            Should -Invoke -ModuleName PSVergeOS Invoke-VergeAPI -ParameterFilter {
                $Method -eq 'PUT' -and
                $Endpoint -eq 'vms/1' -and 
                $Body.ContainsKey($Field) -and 
                $Body.$Field -eq $Value
            }

        }

        It 'Does not include the <field> field if it is not being set' -ForEach @(
            @{ Field = 'allow_export' }
            @{ Field = 'nested_virtualization' }
            @{ Field = 'note' }
        ) {
            Set-VergeVM -Key 1 -Description 'New description'

            Should -Invoke -ModuleName PSVergeOS Invoke-VergeAPI -ParameterFilter {
                $Method -eq 'PUT' -and
                $Endpoint -eq 'vms/1' -and
                -not $Body.ContainsKey($Field)
            }
        }
    }
}
