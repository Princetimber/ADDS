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
}
