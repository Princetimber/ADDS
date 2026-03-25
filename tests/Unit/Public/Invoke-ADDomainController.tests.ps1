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

Describe 'Invoke-ADDomainController' -Tag 'Unit' {

    BeforeEach {
        InModuleScope -ModuleName $script:dscModuleName {
            Mock Write-ToLog
            Mock New-ADDomainController
        }
    }

    Context 'When using -WhatIf' {
        It 'Should not call New-ADDomainController' {
            InModuleScope -ModuleName $script:dscModuleName {
                Invoke-ADDomainController -DomainName 'contoso.com' -WhatIf

                Should -Invoke New-ADDomainController -Times 0
            }
        }
    }

    Context 'When called with a mandatory DomainName' {
        It 'Should call New-ADDomainController with the provided DomainName' {
            InModuleScope -ModuleName $script:dscModuleName {
                Invoke-ADDomainController -DomainName 'contoso.com' -Confirm:$false

                Should -Invoke New-ADDomainController -Times 1 -ParameterFilter {
                    $DomainName -eq 'contoso.com'
                }
            }
        }
    }

    Context 'When -SiteName is provided' {
        It 'Should pass SiteName to New-ADDomainController' {
            InModuleScope -ModuleName $script:dscModuleName {
                Invoke-ADDomainController -DomainName 'contoso.com' -SiteName 'London-Site' -Confirm:$false

                Should -Invoke New-ADDomainController -Times 1 -ParameterFilter {
                    $SiteName -eq 'London-Site'
                }
            }
        }
    }

    Context 'When -PassThru is specified' {
        It 'Should return a PSCustomObject with type Invoke-ADDomainController.ADDSDomainController' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = Invoke-ADDomainController -DomainName 'contoso.com' -PassThru -Confirm:$false

                $result | Should -Not -BeNullOrEmpty
                $result.PSObject.TypeNames | Should -Contain 'Invoke-ADDomainController.ADDSDomainController'
            }
        }

        It 'Should return an object with DomainName matching the input' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = Invoke-ADDomainController -DomainName 'contoso.com' -PassThru -Confirm:$false

                $result.DomainName | Should -Be 'contoso.com'
            }
        }

        It 'Should return the default SiteName when none is specified' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = Invoke-ADDomainController -DomainName 'contoso.com' -PassThru -Confirm:$false

                $result.SiteName | Should -Be 'Default-First-Site-Name'
            }
        }

        It 'Should return the explicit SiteName when specified' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = Invoke-ADDomainController -DomainName 'contoso.com' -SiteName 'HQ-Site' -PassThru -Confirm:$false

                $result.SiteName | Should -Be 'HQ-Site'
            }
        }

        It 'Should return Status = Completed' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = Invoke-ADDomainController -DomainName 'contoso.com' -PassThru -Confirm:$false

                $result.Status | Should -Be 'Completed'
            }
        }

        It 'Should return a non-null Timestamp' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = Invoke-ADDomainController -DomainName 'contoso.com' -PassThru -Confirm:$false

                $result.Timestamp | Should -Not -BeNullOrEmpty
            }
        }

        It 'Should return InstallDNS = $true when -InstallDNS is specified' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = Invoke-ADDomainController -DomainName 'contoso.com' -InstallDNS -PassThru -Confirm:$false

                $result.InstallDNS | Should -BeTrue
            }
        }
    }

    Context 'When -PassThru is not specified' {
        It 'Should return no output' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = Invoke-ADDomainController -DomainName 'contoso.com' -Confirm:$false

                $result | Should -BeNullOrEmpty
            }
        }
    }

    Context 'When -Force is specified' {
        It 'Should pass Force = $true and Confirm = $false to New-ADDomainController' {
            InModuleScope -ModuleName $script:dscModuleName {
                Invoke-ADDomainController -DomainName 'contoso.com' -Force

                Should -Invoke New-ADDomainController -Times 1 -ParameterFilter {
                    $Force -eq $true -and $Confirm -eq $false
                }
            }
        }
    }

    Context 'When path parameters are forwarded to New-ADDomainController' {
        It 'Should forward DatabasePath when calling New-ADDomainController' {
            InModuleScope -ModuleName $script:dscModuleName {
                Invoke-ADDomainController -DomainName 'contoso.com' -DatabasePath 'D:\NTDS' -Confirm:$false

                Should -Invoke New-ADDomainController -Times 1 -ParameterFilter {
                    $DatabasePath -eq 'D:\NTDS'
                }
            }
        }

        It 'Should forward SysvolPath when calling New-ADDomainController' {
            InModuleScope -ModuleName $script:dscModuleName {
                Invoke-ADDomainController -DomainName 'contoso.com' -SysvolPath 'D:\SYSVOL' -Confirm:$false

                Should -Invoke New-ADDomainController -Times 1 -ParameterFilter {
                    $SysvolPath -eq 'D:\SYSVOL'
                }
            }
        }

        It 'Should forward LogPath unchanged' {
            InModuleScope -ModuleName $script:dscModuleName {
                Invoke-ADDomainController -DomainName 'contoso.com' -LogPath 'E:\Logs' -Confirm:$false

                Should -Invoke New-ADDomainController -Times 1 -ParameterFilter {
                    $LogPath -eq 'E:\Logs'
                }
            }
        }
    }

    Context 'When parameter validation fails' {
        It 'Should throw when DomainName is an empty string' {
            InModuleScope -ModuleName $script:dscModuleName {
                { Invoke-ADDomainController -DomainName '' } | Should -Throw
            }
        }
    }

    Context 'When PassThru reflects custom paths' {
        It 'Should show the supplied DatabasePath in the PassThru object' {
            InModuleScope -ModuleName $script:dscModuleName {
                $result = Invoke-ADDomainController -DomainName 'contoso.com' -DatabasePath 'D:\NTDS' -PassThru -Confirm:$false

                $result.DatabasePath | Should -Be 'D:\NTDS'
            }
        }
    }
}
