#Requires -Version 7.0

BeforeAll {
    $script:dscModuleName = 'Invoke-ADDS'
    Import-Module -Name $script:dscModuleName
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Remove-RegisteredSecretVault' -Tag 'Unit' {

    BeforeEach {
        InModuleScope -ModuleName $script:dscModuleName {
            Mock Write-ToLog
        }
    }

    Context 'When the vault is not registered' {
        It 'Should return without error and not call Unregister-SecretVaultWrapper' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-SecretVaultWrapper { $null }
                Mock Unregister-SecretVaultWrapper

                { Remove-RegisteredSecretVault -Name 'MyVault' } | Should -Not -Throw

                Should -Invoke Unregister-SecretVaultWrapper -Times 0
            }
        }
    }

    Context 'When the vault is registered and unregistration succeeds' {
        It 'Should call Unregister-SecretVaultWrapper with the correct name' {
            InModuleScope -ModuleName $script:dscModuleName {
                $script:_vaultUnregistered = $false
                Mock Get-SecretVaultWrapper {
                    if ($script:_vaultUnregistered) { $null }
                    else { [PSCustomObject]@{ Name = 'MyVault' } }
                }
                Mock Unregister-SecretVaultWrapper { $script:_vaultUnregistered = $true }

                Remove-RegisteredSecretVault -Name 'MyVault'

                Should -Invoke Unregister-SecretVaultWrapper -Times 1 -ParameterFilter {
                    $Name -eq 'MyVault'
                }
            }
        }

        It 'Should complete without throwing' {
            InModuleScope -ModuleName $script:dscModuleName {
                $script:_vaultUnregistered = $false
                Mock Get-SecretVaultWrapper {
                    if ($script:_vaultUnregistered) { $null }
                    else { [PSCustomObject]@{ Name = 'MyVault' } }
                }
                Mock Unregister-SecretVaultWrapper { $script:_vaultUnregistered = $true }

                { Remove-RegisteredSecretVault -Name 'MyVault' } | Should -Not -Throw
            }
        }
    }

    Context 'When the vault is still present after unregistration' {
        It 'Should throw a verification failure error' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-SecretVaultWrapper { [PSCustomObject]@{ Name = 'MyVault' } }
                Mock Unregister-SecretVaultWrapper

                { Remove-RegisteredSecretVault -Name 'MyVault' } |
                    Should -Throw -ExpectedMessage '*Post-unregister verification failed*'
            }
        }
    }

    Context 'When Name is not provided and Get-Vault returns nothing' {
        It 'Should throw when the vault name cannot be resolved' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-Vault { $null }

                { Remove-RegisteredSecretVault } | Should -Throw
            }
        }
    }

    Context 'When using -WhatIf' {
        It 'Should not call Unregister-SecretVaultWrapper' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-SecretVaultWrapper { [PSCustomObject]@{ Name = 'MyVault' } }
                Mock Unregister-SecretVaultWrapper

                Remove-RegisteredSecretVault -Name 'MyVault' -WhatIf

                Should -Invoke Unregister-SecretVaultWrapper -Times 0
            }
        }
    }
}
