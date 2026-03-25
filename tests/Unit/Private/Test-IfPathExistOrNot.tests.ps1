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

Describe 'Test-IfPathExistOrNot' -Tag 'Unit' {

    Context 'When all paths exist' {
        It 'Should not throw when all paths are found' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Test-PathWrapper { $true }

                { Test-IfPathExistOrNot -Paths @('C:\Windows', 'C:\Windows\System32') } | Should -Not -Throw
            }
        }

        It 'Should call Test-PathWrapper once for each supplied path' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Test-PathWrapper { $true }

                Test-IfPathExistOrNot -Paths @('C:\Windows', 'C:\Temp')

                Should -Invoke Test-PathWrapper -Times 2
            }
        }

        It 'Should accept a single path' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Test-PathWrapper { $true }

                { Test-IfPathExistOrNot -Paths @('C:\Windows') } | Should -Not -Throw
            }
        }
    }

    Context 'When one path is missing' {
        It 'Should throw with a path validation failure message' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Test-PathWrapper -ParameterFilter { $Path -eq 'C:\Missing' } { $false }
                Mock Test-PathWrapper { $true }

                { Test-IfPathExistOrNot -Paths @('C:\Windows', 'C:\Missing') } |
                    Should -Throw -ExpectedMessage '*Path validation failed*'
            }
        }

        It 'Should include the missing path name in the error message' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Test-PathWrapper { $false }

                { Test-IfPathExistOrNot -Paths @('C:\DoesNotExist') } |
                    Should -Throw -ExpectedMessage '*C:\DoesNotExist*'
            }
        }
    }

    Context 'When multiple paths are missing' {
        It 'Should validate all paths before throwing — not stop at the first failure' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Test-PathWrapper { $false }

                { Test-IfPathExistOrNot -Paths @('C:\A', 'C:\B', 'C:\C') } | Should -Throw

                Should -Invoke Test-PathWrapper -Times 3
            }
        }

        It 'Should report the total count of missing paths in the error message' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Test-PathWrapper { $false }

                { Test-IfPathExistOrNot -Paths @('C:\A', 'C:\B') } |
                    Should -Throw -ExpectedMessage '*2 of 2*'
            }
        }
    }

    Context 'When validating parameters' {
        It 'Should throw when Paths contains an empty string' {
            InModuleScope -ModuleName $script:dscModuleName {
                { Test-IfPathExistOrNot -Paths @('') } | Should -Throw
            }
        }
    }
}
