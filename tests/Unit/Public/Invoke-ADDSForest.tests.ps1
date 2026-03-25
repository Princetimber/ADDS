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

Describe 'Invoke-ADDSForest' -Tag 'Unit' {

    BeforeEach {
        InModuleScope -ModuleName $script:dscModuleName {
            Mock Write-ToLog
            Mock New-ADDSForest
        }
    }

    Context 'When using -WhatIf' {
        It 'Should not call New-ADDSForest' {
            InModuleScope -ModuleName $script:dscModuleName {
                Invoke-ADDSForest -DomainName 'contoso.com' -WhatIf

                Should -Invoke New-ADDSForest -Times 0
            }
        }
    }

    Context 'When called with a mandatory DomainName' {
        It 'Should call New-ADDSForest with the provided DomainName' {
            InModuleScope -ModuleName $script:dscModuleName {
                Invoke-ADDSForest -DomainName 'contoso.com' -Confirm:$false

                Should -Invoke New-ADDSForest -Times 1 -ParameterFilter {
                    $DomainName -eq 'contoso.com'
                }
            }
        }
    }

    Context 'When -PassThru is specified' {
        It 'Should return a PSCustomObject with type Invoke-ADDSForest.ADDSForest' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = Invoke-ADDSForest -DomainName 'contoso.com' -PassThru -Confirm:$false

                $result | Should -Not -BeNullOrEmpty
                $result.PSObject.TypeNames | Should -Contain 'Invoke-ADDSForest.ADDSForest'
            }
        }

        It 'Should return an object with DomainName matching the input' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = Invoke-ADDSForest -DomainName 'contoso.com' -PassThru -Confirm:$false

                $result.DomainName | Should -Be 'contoso.com'
            }
        }

        It 'Should derive the NetBIOS name from the first domain label when not specified' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = Invoke-ADDSForest -DomainName 'contoso.com' -PassThru -Confirm:$false

                $result.DomainNetBiosName | Should -Be 'CONTOSO'
            }
        }

        It 'Should use the explicit NetBIOS name when DomainNetBiosName is provided' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = Invoke-ADDSForest -DomainName 'contoso.com' -DomainNetBiosName 'CORP' -PassThru -Confirm:$false

                $result.DomainNetBiosName | Should -Be 'CORP'
            }
        }

        It 'Should return Status = Completed' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = Invoke-ADDSForest -DomainName 'contoso.com' -PassThru -Confirm:$false

                $result.Status | Should -Be 'Completed'
            }
        }

        It 'Should return a non-null Timestamp' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = Invoke-ADDSForest -DomainName 'contoso.com' -PassThru -Confirm:$false

                $result.Timestamp | Should -Not -BeNullOrEmpty
            }
        }

        It 'Should include InstallDNS = $true when -InstallDNS is specified' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = Invoke-ADDSForest -DomainName 'contoso.com' -InstallDNS -PassThru -Confirm:$false

                $result.InstallDNS | Should -BeTrue
            }
        }
    }

    Context 'When -PassThru is not specified' {
        It 'Should return no output' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = Invoke-ADDSForest -DomainName 'contoso.com' -Confirm:$false

                $result | Should -BeNullOrEmpty
            }
        }
    }

    Context 'When -Force is specified' {
        It 'Should pass Force = $true and Confirm = $false to New-ADDSForest' {
            InModuleScope -ModuleName $script:dscModuleName {
                Invoke-ADDSForest -DomainName 'contoso.com' -Force

                Should -Invoke New-ADDSForest -Times 1 -ParameterFilter {
                    $Force -eq $true -and $Confirm -eq $false
                }
            }
        }
    }

    Context 'When optional path parameters are provided' {
        It 'Should forward DatabasePath to New-ADDSForest' {
            InModuleScope -ModuleName $script:dscModuleName {
                Invoke-ADDSForest -DomainName 'contoso.com' -DatabasePath 'D:\NTDS' -Confirm:$false

                Should -Invoke New-ADDSForest -Times 1 -ParameterFilter {
                    $DatabasePath -eq 'D:\NTDS'
                }
            }
        }

        It 'Should forward LogPath to New-ADDSForest' {
            InModuleScope -ModuleName $script:dscModuleName {
                Invoke-ADDSForest -DomainName 'contoso.com' -LogPath 'E:\Logs' -Confirm:$false

                Should -Invoke New-ADDSForest -Times 1 -ParameterFilter {
                    $LogPath -eq 'E:\Logs'
                }
            }
        }

        It 'Should forward DomainMode and ForestMode to New-ADDSForest' {
            InModuleScope -ModuleName $script:dscModuleName {
                Invoke-ADDSForest -DomainName 'contoso.com' -DomainMode 'Win2012R2' -ForestMode 'Win2012R2' -Confirm:$false

                Should -Invoke New-ADDSForest -Times 1 -ParameterFilter {
                    $DomainMode -eq 'Win2012R2' -and $ForestMode -eq 'Win2012R2'
                }
            }
        }
    }

    Context 'When parameter validation fails' {
        It 'Should throw when DomainMode has an invalid value' {
            InModuleScope -ModuleName $script:dscModuleName {
                { Invoke-ADDSForest -DomainName 'contoso.com' -DomainMode 'Win1999' } | Should -Throw
            }
        }

        It 'Should throw when ForestMode has an invalid value' {
            InModuleScope -ModuleName $script:dscModuleName {
                { Invoke-ADDSForest -DomainName 'contoso.com' -ForestMode 'Invalid' } | Should -Throw
            }
        }

        It 'Should throw when DomainName is an empty string' {
            InModuleScope -ModuleName $script:dscModuleName {
                { Invoke-ADDSForest -DomainName '' } | Should -Throw
            }
        }
    }

    Context 'When PassThru returns custom paths' {
        It 'Should reflect the supplied DatabasePath in the PassThru object' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = Invoke-ADDSForest -DomainName 'contoso.com' -DatabasePath 'D:\NTDS' -PassThru -Confirm:$false

                $result.DatabasePath | Should -Be 'D:\NTDS'
            }
        }
    }
}
