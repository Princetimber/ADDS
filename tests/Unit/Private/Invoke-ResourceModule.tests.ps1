#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0.0' }

BeforeAll {
    $script:dscModuleName = 'Invoke-ADDS'
    Import-Module -Name $script:dscModuleName
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Invoke-ResourceModule' -Tag 'Unit' {

    BeforeEach {
        InModuleScope -ModuleName $script:dscModuleName {
            Mock Write-ToLog
        }
    }

    Context 'When PSGallery is not registered' {
        It 'Should throw when PSGallery is not found' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-PSResourceRepository { $null } -ParameterFilter { $Name -eq 'PSGallery' }

                { Invoke-ResourceModule } | Should -Throw -ExpectedMessage '*PSGallery not found*'
            }
        }

        It 'Should throw when Get-PSResourceRepository itself throws' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-PSResourceRepository { throw 'Repository not accessible' }

                { Invoke-ResourceModule } | Should -Throw
            }
        }

        It 'Should list other registered repositories when PSGallery is not found' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-PSResourceRepository {
                    if ($Name) { $null } else {
                        @([PSCustomObject]@{ Name = 'MyPrivateFeed'; Uri = 'https://example.com/nuget' })
                    }
                }

                { Invoke-ResourceModule } | Should -Throw -ExpectedMessage '*Available repositories:*MyPrivateFeed*'
            }
        }
    }

    Context 'When a module is already installed' {
        It 'Should skip installation and not call Install-PSResourceWrapper' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-PSResourceRepository {
                    [PSCustomObject]@{ Name = 'PSGallery'; Uri = 'https://www.powershellgallery.com/api/v2' }
                }
                Mock Get-ModuleWrapper { [PSCustomObject]@{ Name = 'Az.KeyVault'; Version = '6.0.0' } }
                Mock Install-PSResourceWrapper

                Invoke-ResourceModule -Name @('Az.KeyVault')

                Should -Invoke Install-PSResourceWrapper -Times 0
            }
        }
    }

    Context 'When a module is not installed' {
        It 'Should install the module from PSGallery' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-PSResourceRepository {
                    [PSCustomObject]@{ Name = 'PSGallery'; Uri = 'https://www.powershellgallery.com/api/v2' }
                }
                $script:_moduleInstalled = $false
                Mock Get-ModuleWrapper {
                    if ($script:_moduleInstalled) { [PSCustomObject]@{ Name = 'Az.KeyVault'; Version = '6.0.0' } }
                    else { $null }
                }
                Mock Set-PSResourceRepositoryWrapper
                Mock Install-PSResourceWrapper { $script:_moduleInstalled = $true }

                Invoke-ResourceModule -Name @('Az.KeyVault')

                Should -Invoke Install-PSResourceWrapper -Times 1 -ParameterFilter {
                    $Name -eq 'Az.KeyVault' -and $Repository -eq 'PSGallery'
                }
            }
        }

        It 'Should set PSGallery as trusted before installing' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-PSResourceRepository {
                    [PSCustomObject]@{ Name = 'PSGallery'; Uri = 'https://www.powershellgallery.com/api/v2' }
                }
                $script:_moduleInstalled = $false
                Mock Get-ModuleWrapper {
                    if ($script:_moduleInstalled) { [PSCustomObject]@{ Name = 'Az.KeyVault'; Version = '1.0.0' } }
                    else { $null }
                }
                Mock Set-PSResourceRepositoryWrapper
                Mock Install-PSResourceWrapper { $script:_moduleInstalled = $true }

                Invoke-ResourceModule -Name @('Az.KeyVault')

                Should -Invoke Set-PSResourceRepositoryWrapper -Times 1 -ParameterFilter {
                    $Name -eq 'PSGallery' -and $Trusted -eq $true
                }
            }
        }

        It 'Should give an enhanced error message when the module is not found in PSGallery' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-PSResourceRepository {
                    [PSCustomObject]@{ Name = 'PSGallery'; Uri = 'https://www.powershellgallery.com/api/v2' }
                }
                Mock Get-ModuleWrapper { $null }
                Mock Set-PSResourceRepositoryWrapper
                Mock Install-PSResourceWrapper { throw 'Package not found in the repository' }

                { Invoke-ResourceModule -Name @('NonExistentModule') } |
                    Should -Throw -ExpectedMessage "*Module 'NonExistentModule' not found in PSGallery*"
            }
        }

        It 'Should throw when post-install verification fails' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-PSResourceRepository {
                    [PSCustomObject]@{ Name = 'PSGallery'; Uri = 'https://www.powershellgallery.com/api/v2' }
                }
                Mock Get-ModuleWrapper { $null }
                Mock Set-PSResourceRepositoryWrapper
                Mock Install-PSResourceWrapper

                { Invoke-ResourceModule -Name @('SomeModule') } |
                    Should -Throw -ExpectedMessage '*Post-install verification failed*'
            }
        }
    }

    Context 'When using default module names' {
        It 'Should process both Microsoft.PowerShell.SecretManagement and Az.KeyVault by default' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-PSResourceRepository {
                    [PSCustomObject]@{ Name = 'PSGallery'; Uri = 'https://www.powershellgallery.com/api/v2' }
                }
                Mock Get-ModuleWrapper { [PSCustomObject]@{ Name = 'module'; Version = '1.0.0' } }

                Invoke-ResourceModule

                Should -Invoke Get-ModuleWrapper -Times 2
            }
        }
    }

    Context 'Get-ModuleWrapper' {
        It 'Should call Get-Module -Name -ListAvailable when Name is supplied' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-Module { [PSCustomObject]@{ Name = 'Az.KeyVault' } }

                $result = Get-ModuleWrapper -Name 'Az.KeyVault' -ListAvailable

                $result.Name | Should -Be 'Az.KeyVault'
                Should -Invoke Get-Module -Times 1 -ParameterFilter {
                    $Name -eq 'Az.KeyVault' -and $ListAvailable -eq $true
                }
            }
        }

        It 'Should call Get-Module -ListAvailable with no name when Name is not supplied' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-Module { @() }

                Get-ModuleWrapper -ListAvailable

                Should -Invoke Get-Module -Times 1 -ParameterFilter {
                    -not $Name -and $ListAvailable -eq $true
                }
            }
        }
    }
}
