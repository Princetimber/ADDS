#Requires -Version 7.0

BeforeAll {
    $script:dscModuleName = 'Invoke-ADDS'

    Import-Module -Name $script:dscModuleName
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Get-LogFileSize' -Tag 'Unit' {

    BeforeEach {
        InModuleScope -ModuleName $script:dscModuleName {
            $script:LogFile = Join-Path $TestDrive 'module.log'
        }
    }

    Context 'When the log file does not exist' {
        It 'Should return 0' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Test-PathWrapper { $false }

                $result = Get-LogFileSize

                $result | Should -Be 0
            }
        }

        It 'Should return a [long] typed value of 0' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Test-PathWrapper { $false }

                $result = Get-LogFileSize

                $result | Should -BeOfType [long]
            }
        }
    }

    Context 'When the log file exists' {
        It 'Should return the file size in bytes' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Test-PathWrapper { $true }
                Mock Get-ItemWrapper { [PSCustomObject]@{ Length = [long]2048 } }

                $result = Get-LogFileSize

                $result | Should -Be 2048
            }
        }

        It 'Should return the correct size for a large file' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Test-PathWrapper { $true }
                Mock Get-ItemWrapper { [PSCustomObject]@{ Length = [long]10485760 } }  # 10 MB

                $result = Get-LogFileSize

                $result | Should -Be 10485760
            }
        }

        It 'Should return 0 for an empty file' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Test-PathWrapper { $true }
                Mock Get-ItemWrapper { [PSCustomObject]@{ Length = [long]0 } }

                $result = Get-LogFileSize

                $result | Should -Be 0
            }
        }
    }
}
