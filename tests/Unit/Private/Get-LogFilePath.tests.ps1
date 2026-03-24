#Requires -Version 7.0

BeforeAll {
    $script:dscModuleName = 'TemplateModule'

    Import-Module -Name $script:dscModuleName
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Get-LogFilePath' -Tag 'Unit' {

    Context 'When the module-scoped log path is set' {
        It 'Should return the current script:LogFile value' {
            InModuleScope -ModuleName $script:dscModuleName {
                $expectedPath = Join-Path $TestDrive 'expected.log'
                $script:LogFile = $expectedPath

                $result = Get-LogFilePath

                $result | Should -Be $expectedPath
            }
        }
    }

    Context 'When the log path has been updated via Set-LogFilePath' {
        It 'Should reflect the updated path' {
            InModuleScope -ModuleName $script:dscModuleName {
                $newPath = Join-Path $TestDrive 'updated.log'
                $script:LogFile = $newPath

                $result = Get-LogFilePath

                $result | Should -Be $newPath
            }
        }
    }

    Context 'When called multiple times' {
        It 'Should consistently return the same path' {
            InModuleScope -ModuleName $script:dscModuleName {
                $path = Join-Path $TestDrive 'consistent.log'
                $script:LogFile = $path

                $result1 = Get-LogFilePath
                $result2 = Get-LogFilePath

                $result1 | Should -Be $result2
            }
        }
    }
}
