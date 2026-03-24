#Requires -Version 7.0

BeforeAll {
    $script:dscModuleName = 'Invoke-ADDS'
    Import-Module -Name $script:dscModuleName
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Get-Vault' -Tag 'Unit' {

    Context 'When both KeyVaultName and ResourceGroupName are provided' {
        It 'Should pass both parameters to Get-AzKeyVaultWrapper' {
            InModuleScope -ModuleName $script:dscModuleName {
                $mockVault = [PSCustomObject]@{ VaultName = 'MyVault'; ResourceGroupName = 'MyRG' }
                Mock Get-AzKeyVaultWrapper { $mockVault }

                $result = Get-Vault -KeyVaultName 'MyVault' -ResourceGroupName 'MyRG'

                $result | Should -Be $mockVault
                Should -Invoke Get-AzKeyVaultWrapper -Times 1 -ParameterFilter {
                    $KeyVaultName -eq 'MyVault' -and $ResourceGroupName -eq 'MyRG'
                }
            }
        }
    }

    Context 'When only KeyVaultName is provided' {
        It 'Should call Get-AzKeyVaultWrapper with just KeyVaultName' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-AzKeyVaultWrapper { [PSCustomObject]@{ VaultName = 'MyVault' } }

                Get-Vault -KeyVaultName 'MyVault'

                Should -Invoke Get-AzKeyVaultWrapper -Times 1 -ParameterFilter {
                    $KeyVaultName -eq 'MyVault'
                }
            }
        }
    }

    Context 'When called with no parameters' {
        It 'Should call Get-AzKeyVaultWrapper with no arguments' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-AzKeyVaultWrapper { @() }

                Get-Vault

                Should -Invoke Get-AzKeyVaultWrapper -Times 1
            }
        }
    }

    Context 'When the Key Vault is not found' {
        It 'Should return null when Get-AzKeyVaultWrapper returns null' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-AzKeyVaultWrapper { $null }

                $result = Get-Vault -KeyVaultName 'NonExistent' -ResourceGroupName 'MyRG'

                $result | Should -BeNullOrEmpty
            }
        }
    }
}
