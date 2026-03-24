#Requires -Version 7.0

BeforeAll {
    $script:dscModuleName = 'Invoke-ADDS'
    Import-Module -Name $script:dscModuleName
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Add-RegisteredSecretVault' -Tag 'Unit' {

    BeforeEach {
        InModuleScope -ModuleName $script:dscModuleName {
            Mock Write-ToLog
        }
    }

    Context 'When the vault is already registered' {
        It 'Should skip registration and not call Register-SecretVaultWrapper' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-SecretVaultWrapper { [PSCustomObject]@{ Name = 'MyVault'; ModuleName = 'Az.KeyVault' } }
                Mock Register-SecretVaultWrapper
                Mock Get-AzContextWrapper { [PSCustomObject]@{ Subscription = @{ Id = 'sub-123' }; Account = 'user@contoso.com' } }

                Add-RegisteredSecretVault -Name 'MyVault' -SubscriptionId 'sub-123'

                Should -Invoke Register-SecretVaultWrapper -Times 0
            }
        }
    }

    Context 'When the vault is not registered and all parameters are provided' {
        It 'Should call Register-SecretVaultWrapper with Az.KeyVault as the module name' {
            InModuleScope -ModuleName $script:dscModuleName {
                # Use $script: scope so the flag is shared between mock scriptblocks in module scope
                $script:_vaultRegistered = $false
                Mock Get-SecretVaultWrapper {
                    if ($script:_vaultRegistered) { [PSCustomObject]@{ Name = 'MyVault'; ModuleName = 'Az.KeyVault' } }
                    else { $null }
                }
                Mock Register-SecretVaultWrapper { $script:_vaultRegistered = $true }
                Mock Get-AzContextWrapper { [PSCustomObject]@{ Subscription = @{ Id = 'sub-123' } } }

                Add-RegisteredSecretVault -Name 'MyVault' -SubscriptionId 'sub-123'

                Should -Invoke Register-SecretVaultWrapper -Times 1 -ParameterFilter {
                    $Name -eq 'MyVault' -and $ModuleName -eq 'Az.KeyVault'
                }
            }
        }

        It 'Should throw when post-registration verification fails' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-SecretVaultWrapper { $null }
                Mock Register-SecretVaultWrapper
                Mock Get-AzContextWrapper { [PSCustomObject]@{ Subscription = @{ Id = 'sub-123' } } }

                { Add-RegisteredSecretVault -Name 'MyVault' -SubscriptionId 'sub-123' } |
                    Should -Throw -ExpectedMessage '*Post-register verification failed*'
            }
        }
    }

    Context 'When SubscriptionId is not provided' {
        It 'Should resolve SubscriptionId from the active Azure context' {
            InModuleScope -ModuleName $script:dscModuleName {
                $script:_vaultRegistered = $false
                Mock Get-SecretVaultWrapper {
                    if ($script:_vaultRegistered) { [PSCustomObject]@{ Name = 'MyVault' } }
                    else { $null }
                }
                Mock Register-SecretVaultWrapper { $script:_vaultRegistered = $true }
                Mock Get-AzContextWrapper { [PSCustomObject]@{ Subscription = @{ Id = 'ctx-sub-456' } } }

                Add-RegisteredSecretVault -Name 'MyVault'

                Should -Invoke Register-SecretVaultWrapper -Times 1 -ParameterFilter {
                    $VaultParameters.SubscriptionId -eq 'ctx-sub-456'
                }
            }
        }

        It 'Should throw when no SubscriptionId is supplied and no Azure context exists' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-SecretVaultWrapper { $null }
                Mock Get-AzContextWrapper { $null }

                { Add-RegisteredSecretVault -Name 'MyVault' } | Should -Throw
            }
        }
    }

    Context 'When Name is not provided and Get-Vault returns nothing' {
        It 'Should throw when the vault name cannot be resolved' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-Vault { $null }

                { Add-RegisteredSecretVault -SubscriptionId 'sub-123' } | Should -Throw
            }
        }
    }

    Context 'When using -WhatIf' {
        It 'Should not call Register-SecretVaultWrapper' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-SecretVaultWrapper { $null }
                Mock Register-SecretVaultWrapper
                Mock Get-AzContextWrapper { [PSCustomObject]@{ Subscription = @{ Id = 'sub-123' } } }

                Add-RegisteredSecretVault -Name 'MyVault' -SubscriptionId 'sub-123' -WhatIf

                Should -Invoke Register-SecretVaultWrapper -Times 0
            }
        }
    }
}
