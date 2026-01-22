#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for PSVergeOS connection cmdlets.

.DESCRIPTION
    Tests for Connect-VergeOS, Disconnect-VergeOS, Get-VergeConnection,
    and Set-VergeConnection cmdlets.
#>

BeforeAll {
    # Import the module
    $ModulePath = Join-Path -Path $PSScriptRoot -ChildPath '../../PSVergeOS.psd1'
    Import-Module $ModulePath -Force
}

AfterAll {
    # Clean up
    Remove-Module PSVergeOS -Force -ErrorAction SilentlyContinue
}

Describe 'Connect-VergeOS' {
    BeforeEach {
        # Disconnect any existing connections before each test
        Disconnect-VergeOS -All -ErrorAction SilentlyContinue
    }

    Context 'Parameter Validation' {
        It 'Should require Server parameter' {
            { Connect-VergeOS } | Should -Throw
        }

        It 'Should require either Credential or Token' {
            { Connect-VergeOS -Server 'test.local' } | Should -Throw
        }

        It 'Should strip protocol prefix from Server' {
            # This will fail to connect but we're testing parameter handling
            Mock Invoke-RestMethod { throw 'Connection refused' }

            { Connect-VergeOS -Server 'https://test.local' -Token 'test' } |
                Should -Throw -ExpectedMessage '*test.local*'
        }
    }

    Context 'Token Authentication' {
        BeforeAll {
            Mock Invoke-RestMethod {
                param($Uri)
                if ($Uri -match '/system$') {
                    return @{ version = '26.1.0' }
                }
                throw 'Unexpected endpoint'
            }
        }

        It 'Should connect successfully with valid token' {
            $result = Connect-VergeOS -Server 'test.local' -Token 'valid-token' -PassThru

            $result | Should -Not -BeNullOrEmpty
            $result.Server | Should -Be 'test.local'
            $result.IsConnected | Should -BeTrue
        }

        It 'Should set connection as default' {
            Connect-VergeOS -Server 'test.local' -Token 'valid-token'

            $default = Get-VergeConnection -Default
            $default.Server | Should -Be 'test.local'
        }
    }

    Context 'Credential Authentication' {
        BeforeAll {
            Mock Invoke-RestMethod {
                param($Uri, $Body)
                if ($Uri -match '/auth/login$') {
                    return @{
                        token   = 'session-token-123'
                        expires = (Get-Date).AddHours(8).ToString('o')
                    }
                }
                if ($Uri -match '/system$') {
                    return @{ version = '26.1.0' }
                }
                throw 'Unexpected endpoint'
            }
        }

        It 'Should connect successfully with credentials' {
            $cred = [PSCredential]::new('admin', (ConvertTo-SecureString 'password' -AsPlainText -Force))
            $result = Connect-VergeOS -Server 'test.local' -Credential $cred -PassThru

            $result | Should -Not -BeNullOrEmpty
            $result.Username | Should -Be 'admin'
            $result.IsConnected | Should -BeTrue
        }
    }
}

Describe 'Disconnect-VergeOS' {
    BeforeEach {
        # Set up mock connections
        Mock Invoke-RestMethod {
            param($Uri)
            if ($Uri -match '/system$') {
                return @{ version = '26.1.0' }
            }
            throw 'Unexpected endpoint'
        }

        Connect-VergeOS -Server 'test1.local' -Token 'token1'
        Connect-VergeOS -Server 'test2.local' -Token 'token2'
    }

    It 'Should disconnect the default connection' {
        Disconnect-VergeOS

        $connections = Get-VergeConnection
        $connections.Count | Should -Be 1
        $connections.Server | Should -Be 'test1.local'
    }

    It 'Should disconnect a specific server' {
        Disconnect-VergeOS -Server 'test1.local'

        $connections = Get-VergeConnection
        $connections.Count | Should -Be 1
        $connections.Server | Should -Be 'test2.local'
    }

    It 'Should disconnect all connections' {
        Disconnect-VergeOS -All

        Get-VergeConnection | Should -BeNullOrEmpty
    }
}

Describe 'Get-VergeConnection' {
    BeforeEach {
        Disconnect-VergeOS -All -ErrorAction SilentlyContinue

        Mock Invoke-RestMethod {
            return @{ version = '26.1.0' }
        }
    }

    It 'Should return warning when no connections exist' {
        Get-VergeConnection -WarningVariable warn -WarningAction SilentlyContinue
        $warn | Should -Not -BeNullOrEmpty
    }

    It 'Should return all connections' {
        Connect-VergeOS -Server 'test1.local' -Token 'token1'
        Connect-VergeOS -Server 'test2.local' -Token 'token2'

        $connections = Get-VergeConnection
        $connections.Count | Should -Be 2
    }

    It 'Should filter connections by server name' {
        Connect-VergeOS -Server 'prod.local' -Token 'token1'
        Connect-VergeOS -Server 'dev.local' -Token 'token2'

        $connections = Get-VergeConnection -Server 'prod*'
        $connections.Count | Should -Be 1
        $connections.Server | Should -Be 'prod.local'
    }

    It 'Should return only default connection with -Default' {
        Connect-VergeOS -Server 'test1.local' -Token 'token1'
        Connect-VergeOS -Server 'test2.local' -Token 'token2'

        $default = Get-VergeConnection -Default
        $default.Server | Should -Be 'test2.local'
    }
}

Describe 'Set-VergeConnection' {
    BeforeEach {
        Disconnect-VergeOS -All -ErrorAction SilentlyContinue

        Mock Invoke-RestMethod {
            return @{ version = '26.1.0' }
        }

        Connect-VergeOS -Server 'test1.local' -Token 'token1'
        Connect-VergeOS -Server 'test2.local' -Token 'token2'
    }

    It 'Should change the default connection' {
        Set-VergeConnection -Server 'test1.local'

        $default = Get-VergeConnection -Default
        $default.Server | Should -Be 'test1.local'
    }

    It 'Should error for unknown server' {
        { Set-VergeConnection -Server 'unknown.local' } | Should -Throw
    }

    It 'Should support pipeline input' {
        $conn = Get-VergeConnection | Where-Object { $_.Server -eq 'test1.local' }
        $conn | Set-VergeConnection

        $default = Get-VergeConnection -Default
        $default.Server | Should -Be 'test1.local'
    }

    It 'Should return connection with -PassThru' {
        $result = Set-VergeConnection -Server 'test1.local' -PassThru

        $result | Should -Not -BeNullOrEmpty
        $result.Server | Should -Be 'test1.local'
    }
}
