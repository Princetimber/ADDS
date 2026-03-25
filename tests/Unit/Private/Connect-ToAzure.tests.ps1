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

Describe 'Connect-ToAzure' -Tag 'Unit' {

    BeforeEach {
        InModuleScope -ModuleName $script:dscModuleName {
            Mock Write-ToLog
        }
    }

    Context 'When an active Azure context already exists' {
        It 'Should skip authentication and not call Connect-AzAccountWrapper' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-AzContextWrapper { [PSCustomObject]@{ Account = 'user@contoso.com' } }
                Mock Connect-AzAccountWrapper

                Connect-ToAzure

                Should -Invoke Connect-AzAccountWrapper -Times 0
            }
        }
    }

    Context 'When no context exists and authentication succeeds' {
        It 'Should call Connect-AzAccountWrapper then poll until context is confirmed' {
            InModuleScope -ModuleName $script:dscModuleName {
                # $script: scope is shared between mock scriptblocks in InModuleScope
                $script:_azConnected = $false
                Mock Get-AzContextWrapper {
                    if ($script:_azConnected) { [PSCustomObject]@{ Account = 'user@contoso.com' } }
                    else { $null }
                }
                Mock Connect-AzAccountWrapper { $script:_azConnected = $true }
                Mock Test-TimeoutElapsedWrapper { $false }
                Mock Start-Sleep

                Connect-ToAzure

                Should -Invoke Connect-AzAccountWrapper -Times 1
            }
        }
    }

    Context 'When authentication times out' {
        It 'Should throw a timeout error after the timeout period elapses' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-AzContextWrapper { $null }
                Mock Connect-AzAccountWrapper
                Mock Test-TimeoutElapsedWrapper { $true }
                Mock Start-Sleep

                { Connect-ToAzure -TimeoutMinutes 1 } | Should -Throw -ExpectedMessage '*timed out*'
            }
        }
    }

    Context 'When Connect-AzAccountWrapper throws an exception' {
        It 'Should surface the error' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-AzContextWrapper { $null }
                Mock Connect-AzAccountWrapper { throw 'Auth failure' }

                { Connect-ToAzure } | Should -Throw
            }
        }
    }

    Context 'When using -WhatIf' {
        It 'Should not call Connect-AzAccountWrapper' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-AzContextWrapper { $null }
                Mock Connect-AzAccountWrapper

                Connect-ToAzure -WhatIf

                Should -Invoke Connect-AzAccountWrapper -Times 0
            }
        }
    }

    Context 'When validating TimeoutMinutes parameter' {
        It 'Should throw a validation error when TimeoutMinutes is 0' {
            InModuleScope -ModuleName $script:dscModuleName {
                { Connect-ToAzure -TimeoutMinutes 0 } | Should -Throw
            }
        }

        It 'Should throw a validation error when TimeoutMinutes exceeds 120' {
            InModuleScope -ModuleName $script:dscModuleName {
                { Connect-ToAzure -TimeoutMinutes 121 } | Should -Throw
            }
        }

        It 'Should accept TimeoutMinutes = 1 (minimum valid value)' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-AzContextWrapper { [PSCustomObject]@{ Account = 'user@contoso.com' } }

                { Connect-ToAzure -TimeoutMinutes 1 } | Should -Not -Throw
            }
        }
    }
}
