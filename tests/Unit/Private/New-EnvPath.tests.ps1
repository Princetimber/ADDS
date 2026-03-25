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

Describe 'New-EnvPath' -Tag 'Unit' {

    Context 'When joining valid path segments' {
        It 'Should return the correctly joined path string' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = New-EnvPath -Path 'C:\Windows' -ChildPath 'System32'

                $result | Should -Be 'C:\Windows\System32'
            }
        }

        It 'Should return a string type' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = New-EnvPath -Path 'C:\' -ChildPath 'Temp'

                $result | Should -BeOfType [string]
            }
        }

        It 'Should accept positional parameters' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = New-EnvPath 'C:\NTDS' 'logs'

                $result | Should -Be 'C:\NTDS\logs'
            }
        }

        It 'Should correctly build the AD database path' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = New-EnvPath -Path "$env:SYSTEMDRIVE\Windows" -ChildPath 'ntds'

                $result | Should -Be "$env:SYSTEMDRIVE\Windows\ntds"
            }
        }

        It 'Should correctly build the SYSVOL path' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = New-EnvPath -Path "$env:SYSTEMDRIVE\Windows" -ChildPath 'sysvol'

                $result | Should -Be "$env:SYSTEMDRIVE\Windows\sysvol"
            }
        }

        It 'Should correctly build the log path' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = New-EnvPath -Path "$env:SYSTEMDRIVE\Windows\NTDS" -ChildPath 'logs'

                $result | Should -Be "$env:SYSTEMDRIVE\Windows\NTDS\logs"
            }
        }
    }

    Context 'When validating parameters' {
        It 'Should throw when Path is an empty string' {
            InModuleScope -ModuleName $script:dscModuleName {
                { New-EnvPath -Path '' -ChildPath 'logs' } | Should -Throw
            }
        }

        It 'Should throw when ChildPath is an empty string' {
            InModuleScope -ModuleName $script:dscModuleName {
                { New-EnvPath -Path 'C:\Windows' -ChildPath '' } | Should -Throw
            }
        }

        It 'Should throw when Path is not provided' {
            InModuleScope -ModuleName $script:dscModuleName {
                { New-EnvPath -ChildPath 'logs' } | Should -Throw
            }
        }

        It 'Should throw when ChildPath is not provided' {
            InModuleScope -ModuleName $script:dscModuleName {
                { New-EnvPath -Path 'C:\Windows' } | Should -Throw
            }
        }
    }
}
