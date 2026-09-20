#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0.0' }

BeforeAll {
    $script:dscModuleName = 'Invoke-ADDS'

    Import-Module -Name $script:dscModuleName
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Clear-LogFile' -Tag 'Unit' {

    BeforeEach {
        InModuleScope -ModuleName $script:dscModuleName {
            $script:LogFile = Join-Path $TestDrive 'module.log'
            $script:LogTimestampFormat = 'yyyyMMdd_HHmmss'
        }
    }

    Context 'When the log file does not exist' {
        It 'Should return without error and not call Clear-Content' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Test-PathWrapper { $false }
                Mock Clear-ContentWrapper

                Clear-LogFile -Confirm:$false

                Should -Invoke Clear-ContentWrapper -Times 0
            }
        }
    }

    Context 'When clearing without archiving' {
        It 'Should clear the log file' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Test-PathWrapper { $true }
                Mock Clear-ContentWrapper
                Mock Write-ToLog

                Clear-LogFile -Confirm:$false

                Should -Invoke Clear-ContentWrapper -Times 1 -ParameterFilter {
                    $LiteralPath -eq $script:LogFile
                }
            }
        }

        It 'Should not call Copy-Item when Archive is not specified' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Test-PathWrapper { $true }
                Mock Clear-ContentWrapper
                Mock Copy-ItemWrapper
                Mock Write-ToLog

                Clear-LogFile -Confirm:$false

                Should -Invoke Copy-ItemWrapper -Times 0
            }
        }

        It 'Should log a cleared message after clearing' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Test-PathWrapper { $true }
                Mock Clear-ContentWrapper
                Mock Write-ToLog

                Clear-LogFile -Confirm:$false

                Should -Invoke Write-ToLog -Times 1 -ParameterFilter {
                    $Message -match 'cleared' -and $Level -eq 'INFO'
                }
            }
        }
    }

    Context 'When clearing with the Archive switch' {
        It 'Should copy the log file before clearing' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Test-PathWrapper { $true }
                Mock Copy-ItemWrapper
                Mock Clear-ContentWrapper
                Mock Write-ToLog

                Clear-LogFile -Archive -Confirm:$false

                Should -Invoke Copy-ItemWrapper -Times 1 -ParameterFilter {
                    $LiteralPath -eq $script:LogFile -and
                    $Destination -match '\.bak$'
                }
            }
        }

        It 'Should still clear the log after archiving' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Test-PathWrapper { $true }
                Mock Copy-ItemWrapper
                Mock Clear-ContentWrapper
                Mock Write-ToLog

                Clear-LogFile -Archive -Confirm:$false

                Should -Invoke Clear-ContentWrapper -Times 1
            }
        }

        It 'Should throw when the archive destination directory does not exist' {
            InModuleScope -ModuleName $script:dscModuleName {
                # File exists but archive dir check returns false
                Mock Test-PathWrapper -ParameterFilter { $LiteralPath -eq $script:LogFile } { $true }
                Mock Test-PathWrapper { $false }

                { Clear-LogFile -Archive -Confirm:$false } | Should -Throw
            }
        }
    }

    Context 'When using -WhatIf' {
        It 'Should not clear or archive the log file' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Test-PathWrapper { $true }
                Mock Clear-ContentWrapper
                Mock Copy-ItemWrapper

                Clear-LogFile -WhatIf

                Should -Invoke Clear-ContentWrapper -Times 0
                Should -Invoke Copy-ItemWrapper -Times 0
            }
        }
    }

    Context 'When using -Force' {
        It 'Should bypass the confirmation prompt and clear the file' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Test-PathWrapper { $true }
                Mock Clear-ContentWrapper
                Mock Write-ToLog

                # -Force sets ConfirmPreference = 'None', no -Confirm needed
                Clear-LogFile -Force

                Should -Invoke Clear-ContentWrapper -Times 1
            }
        }
    }

    Context 'Copy-ItemWrapper' {
        It 'Should call Copy-Item -LiteralPath -Destination' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Copy-Item

                Copy-ItemWrapper -LiteralPath 'C:\log.txt' -Destination 'C:\log.bak'

                Should -Invoke Copy-Item -Times 1 -ParameterFilter {
                    $LiteralPath -eq 'C:\log.txt' -and $Destination -eq 'C:\log.bak'
                }
            }
        }
    }

    Context 'Clear-ContentWrapper' {
        It 'Should call Clear-Content -LiteralPath' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Clear-Content

                Clear-ContentWrapper -LiteralPath 'C:\log.txt'

                Should -Invoke Clear-Content -Times 1 -ParameterFilter { $LiteralPath -eq 'C:\log.txt' }
            }
        }
    }
}
