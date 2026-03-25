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

Describe 'Disconnect-FromAzure' -Tag 'Unit' {

    BeforeEach {
        InModuleScope -ModuleName $script:dscModuleName {
            Mock Write-ToLog
        }
    }

    Context 'When no active Azure context exists' {
        It 'Should return without error and not call Disconnect-AzAccountWrapper' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-AzContextWrapper { $null }
                Mock Disconnect-AzAccountWrapper

                { Disconnect-FromAzure } | Should -Not -Throw

                Should -Invoke Disconnect-AzAccountWrapper -Times 0
            }
        }
    }

    Context 'When an active context exists and disconnection succeeds' {
        It 'Should call Disconnect-AzAccountWrapper' {
            InModuleScope -ModuleName $script:dscModuleName {
                $script:_azDisconnected = $false
                Mock Get-AzContextWrapper {
                    if ($script:_azDisconnected) { $null }
                    else { [PSCustomObject]@{ Account = 'user@contoso.com' } }
                }
                Mock Disconnect-AzAccountWrapper { $script:_azDisconnected = $true }

                Disconnect-FromAzure

                Should -Invoke Disconnect-AzAccountWrapper -Times 1
            }
        }

        It 'Should not throw when the context is cleared after disconnect' {
            InModuleScope -ModuleName $script:dscModuleName {
                $script:_azDisconnected = $false
                Mock Get-AzContextWrapper {
                    if ($script:_azDisconnected) { $null }
                    else { [PSCustomObject]@{ Account = 'user@contoso.com' } }
                }
                Mock Disconnect-AzAccountWrapper { $script:_azDisconnected = $true }

                { Disconnect-FromAzure } | Should -Not -Throw
            }
        }
    }

    Context 'When the context is still present after disconnection' {
        It 'Should throw a verification failure error' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-AzContextWrapper { [PSCustomObject]@{ Account = 'user@contoso.com' } }
                Mock Disconnect-AzAccountWrapper

                { Disconnect-FromAzure } | Should -Throw -ExpectedMessage '*Disconnection verification failed*'
            }
        }
    }

    Context 'When using -WhatIf' {
        It 'Should not call Disconnect-AzAccountWrapper' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-AzContextWrapper { [PSCustomObject]@{ Account = 'user@contoso.com' } }
                Mock Disconnect-AzAccountWrapper

                Disconnect-FromAzure -WhatIf

                Should -Invoke Disconnect-AzAccountWrapper -Times 0
            }
        }
    }
}
