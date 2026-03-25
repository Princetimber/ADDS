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

Describe 'Install-ADModule' -Tag 'Unit' {

    BeforeEach {
        InModuleScope -ModuleName $script:dscModuleName {
            Mock Write-ToLog
        }
    }

    Context 'When the feature is already installed' {
        It 'Should skip installation and not call Install-WindowsFeatureWrapper' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-WindowsFeatureWrapper {
                    [PSCustomObject]@{ Name = 'AD-Domain-Services'; Installed = $true; InstallState = 'Installed' }
                }
                Mock Install-WindowsFeatureWrapper

                Install-ADModule -Name 'AD-Domain-Services'

                Should -Invoke Install-WindowsFeatureWrapper -Times 0
            }
        }
    }

    Context 'When the feature is not yet installed' {
        It 'Should call Install-WindowsFeatureWrapper with IncludeAllSubFeature and IncludeManagementTools' {
            InModuleScope -ModuleName $script:dscModuleName {
                $script:_featureInstalled = $false
                Mock Get-WindowsFeatureWrapper {
                    if ($script:_featureInstalled) {
                        [PSCustomObject]@{ Name = 'AD-Domain-Services'; Installed = $true; InstallState = 'Installed' }
                    } else {
                        [PSCustomObject]@{ Name = 'AD-Domain-Services'; Installed = $false; InstallState = 'Available' }
                    }
                }
                Mock Install-WindowsFeatureWrapper {
                    $script:_featureInstalled = $true
                    [PSCustomObject]@{ RestartNeeded = 'No' }
                }

                Install-ADModule -Name 'AD-Domain-Services'

                Should -Invoke Install-WindowsFeatureWrapper -Times 1 -ParameterFilter {
                    $Name -eq 'AD-Domain-Services' -and
                    $IncludeAllSubFeature -eq $true -and
                    $IncludeManagementTools -eq $true
                }
            }
        }

        It 'Should throw when post-install verification fails' {
            InModuleScope -ModuleName $script:dscModuleName {
                # Both checks return "not installed" — install appeared to fail
                Mock Get-WindowsFeatureWrapper {
                    [PSCustomObject]@{ Name = 'AD-Domain-Services'; Installed = $false; InstallState = 'Available' }
                }
                Mock Install-WindowsFeatureWrapper { [PSCustomObject]@{ RestartNeeded = 'No' } }

                { Install-ADModule -Name 'AD-Domain-Services' } |
                    Should -Throw -ExpectedMessage '*Post-install verification failed*'
            }
        }
    }

    Context 'When the feature is not found on the server' {
        It 'Should throw with an informative error message' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-WindowsFeatureWrapper -ParameterFilter { $Name } { $null }
                Mock Get-WindowsFeatureWrapper { @() }

                { Install-ADModule -Name 'NonExistentFeature' } |
                    Should -Throw -ExpectedMessage "*not found on server*"
            }
        }
    }

    Context 'When installation requires a reboot' {
        It 'Should complete without throwing and log a reboot warning' {
            InModuleScope -ModuleName $script:dscModuleName {
                $script:_featureInstalled = $false
                Mock Get-WindowsFeatureWrapper {
                    if ($script:_featureInstalled) {
                        [PSCustomObject]@{ Name = 'AD-Domain-Services'; Installed = $true; InstallState = 'Installed' }
                    } else {
                        [PSCustomObject]@{ Name = 'AD-Domain-Services'; Installed = $false; InstallState = 'Available' }
                    }
                }
                Mock Install-WindowsFeatureWrapper {
                    $script:_featureInstalled = $true
                    [PSCustomObject]@{ RestartNeeded = 'Yes' }
                }
                Mock Write-ToLog

                { Install-ADModule -Name 'AD-Domain-Services' } | Should -Not -Throw

                Should -Invoke Write-ToLog -ParameterFilter {
                    $Message -match 'reboot' -and $Level -eq 'WARN'
                }
            }
        }
    }

    Context 'When using the default Name parameter' {
        It 'Should default to AD-Domain-Services when no Name is specified' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-WindowsFeatureWrapper {
                    [PSCustomObject]@{ Name = 'AD-Domain-Services'; Installed = $true; InstallState = 'Installed' }
                }

                Install-ADModule

                Should -Invoke Get-WindowsFeatureWrapper -ParameterFilter { $Name -eq 'AD-Domain-Services' }
            }
        }
    }
}
