#Requires -Version 7.0

BeforeAll {
    $script:dscModuleName = 'Invoke-ADDS'

    Import-Module -Name $script:dscModuleName
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Set-LogFilePath' -Tag 'Unit' {

    BeforeEach {
        InModuleScope -ModuleName $script:dscModuleName {
            $script:LogFile = $null
            $script:LogDirectoryCreated = $true
            $Global:LogFile = $null
        }
    }

    AfterEach {
        InModuleScope -ModuleName $script:dscModuleName {
            $Global:LogFile = $null
        }
    }

    Context 'When a valid absolute path is provided' {
        It 'Should update script:LogFile to the new path' {
            InModuleScope -ModuleName $script:dscModuleName {
                $newPath = Join-Path $TestDrive 'new.log'

                Set-LogFilePath -Path $newPath

                $script:LogFile | Should -Be $newPath
            }
        }

        It 'Should update Global:LogFile for backward compatibility' {
            InModuleScope -ModuleName $script:dscModuleName {
                $newPath = Join-Path $TestDrive 'global.log'

                Set-LogFilePath -Path $newPath

                $Global:LogFile | Should -Be $newPath
            }
        }

        It 'Should reset LogDirectoryCreated so directory is re-validated on next write' {
            InModuleScope -ModuleName $script:dscModuleName {
                $newPath = Join-Path $TestDrive 'reset.log'
                $script:LogDirectoryCreated = $true

                Set-LogFilePath -Path $newPath

                $script:LogDirectoryCreated | Should -BeFalse
            }
        }
    }

    Context 'When a relative path is provided' {
        It 'Should throw a validation error' {
            InModuleScope -ModuleName $script:dscModuleName {
                { Set-LogFilePath -Path 'relative\path\module.log' } | Should -Throw
            }
        }
    }

    Context 'When an empty or null path is provided' {
        It 'Should throw on an empty string' {
            InModuleScope -ModuleName $script:dscModuleName {
                { Set-LogFilePath -Path '' } | Should -Throw
            }
        }
    }

    Context 'When -Force is specified and the directory does not exist' {
        It 'Should create the destination directory' {
            InModuleScope -ModuleName $script:dscModuleName {
                # Use a subdirectory that does not yet exist inside TestDrive
                $newDir = Join-Path $TestDrive 'newsubdir'
                $newPath = Join-Path $newDir 'module.log'

                Set-LogFilePath -Path $newPath -Force

                Test-Path -LiteralPath $newDir | Should -BeTrue
            }
        }
    }

    Context 'When -Force is not specified and the directory does not exist' {
        It 'Should not create the directory' {
            InModuleScope -ModuleName $script:dscModuleName {
                $missingDir = Join-Path $TestDrive 'missing'
                $newPath = Join-Path $missingDir 'module.log'

                # Should succeed (path is set) but directory should not be created
                Set-LogFilePath -Path $newPath

                Test-Path -LiteralPath $missingDir | Should -BeFalse
            }
        }
    }

    Context 'When using -WhatIf' {
        It 'Should not update script:LogFile' {
            InModuleScope -ModuleName $script:dscModuleName {
                $original = Join-Path $TestDrive 'original.log'
                $script:LogFile = $original

                Set-LogFilePath -Path (Join-Path $TestDrive 'new.log') -WhatIf

                $script:LogFile | Should -Be $original
            }
        }
    }
}
