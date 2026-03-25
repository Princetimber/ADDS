#Requires -Version 7.0

BeforeAll {
    $script:dscModuleName = 'Invoke-ADDS'

    $builtModulePath = Join-Path -Path $PSScriptRoot -ChildPath '../../../output/module' | Convert-Path -ErrorAction SilentlyContinue
    if ($builtModulePath -and ($env:PSModulePath -notlike "*$builtModulePath*"))
    {
        $env:PSModulePath = $builtModulePath + [IO.Path]::PathSeparator + $env:PSModulePath
    }

    Import-Module -Name $script:dscModuleName
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Get-SafeModePassword' -Tag 'Unit' {

    Context 'When a SecureString password is provided directly' {
        It 'Should return the exact SecureString that was supplied' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Read-HostWrapper
                $securePass = ConvertTo-SecureString 'TestPassword123!' -AsPlainText -Force

                $result = Get-SafeModePassword -Password $securePass

                $result | Should -Be $securePass
            }
        }

        It 'Should not call Read-HostWrapper when a password is supplied' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Read-HostWrapper
                $securePass = ConvertTo-SecureString 'TestPassword123!' -AsPlainText -Force

                Get-SafeModePassword -Password $securePass

                Should -Invoke Read-HostWrapper -Times 0
            }
        }

        It 'Should return a SecureString type' {
            InModuleScope -ModuleName $script:dscModuleName {
                $securePass = ConvertTo-SecureString 'AnotherPass!' -AsPlainText -Force

                $result = Get-SafeModePassword -Password $securePass

                $result | Should -BeOfType [System.Security.SecureString]
            }
        }
    }

    Context 'When no password is provided' {
        It 'Should call Read-HostWrapper with AsSecureString' {
            InModuleScope -ModuleName $script:dscModuleName {
                $mockSecure = ConvertTo-SecureString 'PromptedPassword!' -AsPlainText -Force
                Mock Read-HostWrapper { $mockSecure }

                Get-SafeModePassword

                Should -Invoke Read-HostWrapper -Times 1 -ParameterFilter {
                    $Prompt -match 'Safe Mode' -and $AsSecureString -eq $true
                }
            }
        }

        It 'Should return the SecureString from the interactive prompt' {
            InModuleScope -ModuleName $script:dscModuleName {
                $mockSecure = ConvertTo-SecureString 'PromptedPassword!' -AsPlainText -Force
                Mock Read-HostWrapper { $mockSecure }

                $result = Get-SafeModePassword

                $result | Should -Be $mockSecure
            }
        }

        It 'Should throw when Read-HostWrapper returns null (user cancelled)' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Read-HostWrapper { $null }

                { Get-SafeModePassword } | Should -Throw
            }
        }
    }

    Context 'When Read-HostWrapper throws an exception' {
        It 'Should throw with a descriptive message about failing to obtain the password' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Read-HostWrapper { throw 'Unexpected error' }

                { Get-SafeModePassword } |
                    Should -Throw -ExpectedMessage '*Failed to obtain Safe Mode Administrator password*'
            }
        }
    }
}
