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

Describe 'Test-IsWindowsPlatform' -Tag 'Unit' {

    Context 'When running on the current platform' {
        It 'Should return a boolean value' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = Test-IsWindowsPlatform
                $result | Should -BeOfType [bool]
            }
        }

        It 'Should match the automatic $IsWindows variable' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = Test-IsWindowsPlatform
                $result | Should -Be ([bool]$IsWindows)
            }
        }
    }
}
