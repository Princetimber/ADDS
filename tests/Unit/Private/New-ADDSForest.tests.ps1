#Requires -Version 7.0

BeforeAll {
    $script:dscModuleName = 'Invoke-ADDS'
    Import-Module -Name $script:dscModuleName
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'New-ADDSForest' -Tag 'Unit' {

    BeforeEach {
        InModuleScope -ModuleName $script:dscModuleName {
            Mock Write-ToLog
            Mock Test-PreflightCheck { $true }
            Mock Install-ADModule
            Mock Invoke-ResourceModule
            Mock Get-SafeModePassword { ConvertTo-SecureString 'TestPass123!' -AsPlainText -Force }
            Mock Test-PathWrapper { $true }
            Mock New-ItemDirectoryWrapper
            Mock Install-ADDSForestWrapper
        }
    }

    Context 'When using -WhatIf' {
        It 'Should not call Install-ADDSForestWrapper' {
            InModuleScope -ModuleName $script:dscModuleName {
                New-ADDSForest -DomainName 'contoso.com' -WhatIf

                Should -Invoke Install-ADDSForestWrapper -Times 0
            }
        }
    }

    Context 'When a password is supplied directly' {
        It 'Should not connect to Azure or call Get-SecretWrapper' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Connect-ToAzure
                Mock Get-SecretWrapper
                $securePass = ConvertTo-SecureString 'DirectPass123!' -AsPlainText -Force

                New-ADDSForest -DomainName 'contoso.com' -SafeModeAdministratorPassword $securePass -Confirm:$false

                Should -Invoke Connect-ToAzure -Times 0
                Should -Invoke Get-SecretWrapper -Times 0
            }
        }

        It 'Should call Install-ADDSForestWrapper with the correct DomainName' {
            InModuleScope -ModuleName $script:dscModuleName {
                $securePass = ConvertTo-SecureString 'DirectPass123!' -AsPlainText -Force

                New-ADDSForest -DomainName 'contoso.com' -SafeModeAdministratorPassword $securePass -Confirm:$false

                Should -Invoke Install-ADDSForestWrapper -Times 1 -ParameterFilter {
                    $Parameters.DomainName -eq 'contoso.com'
                }
            }
        }
    }

    Context 'When the password comes from Azure Key Vault' {
        It 'Should connect to Azure, get the vault, register it, and retrieve the secret' {
            InModuleScope -ModuleName $script:dscModuleName {
                $mockSecure = ConvertTo-SecureString 'VaultPass!' -AsPlainText -Force
                Mock Connect-ToAzure
                Mock Get-Vault { [PSCustomObject]@{ VaultName = 'MyKV' } }
                Mock Add-RegisteredSecretVault
                Mock Get-SecretWrapper { $mockSecure }
                Mock Remove-RegisteredSecretVault
                Mock Disconnect-FromAzure

                New-ADDSForest -DomainName 'contoso.com' `
                    -ResourceGroupName 'MyRG' -KeyVaultName 'MyKV' -SecretName 'DSRMPass' -Confirm:$false

                Should -Invoke Connect-ToAzure -Times 1
                Should -Invoke Get-Vault -Times 1 -ParameterFilter {
                    $KeyVaultName -eq 'MyKV' -and $ResourceGroupName -eq 'MyRG'
                }
                Should -Invoke Add-RegisteredSecretVault -Times 1 -ParameterFilter { $Name -eq 'MyKV' }
                Should -Invoke Get-SecretWrapper -Times 1 -ParameterFilter {
                    $Name -eq 'DSRMPass' -and $Vault -eq 'MyKV'
                }
            }
        }

        It 'Should disconnect and unregister the vault in the finally block on success' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Connect-ToAzure
                Mock Get-Vault { [PSCustomObject]@{ VaultName = 'MyKV' } }
                Mock Add-RegisteredSecretVault
                Mock Get-SecretWrapper { ConvertTo-SecureString 'p' -AsPlainText -Force }
                Mock Remove-RegisteredSecretVault
                Mock Disconnect-FromAzure

                New-ADDSForest -DomainName 'contoso.com' `
                    -ResourceGroupName 'MyRG' -KeyVaultName 'MyKV' -SecretName 'DSRMPass' -Confirm:$false

                Should -Invoke Remove-RegisteredSecretVault -Times 1
                Should -Invoke Disconnect-FromAzure -Times 1
            }
        }

        It 'Should still disconnect and unregister in the finally block when an error occurs' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Connect-ToAzure
                Mock Get-Vault { [PSCustomObject]@{ VaultName = 'MyKV' } }
                Mock Add-RegisteredSecretVault
                Mock Get-SecretWrapper { ConvertTo-SecureString 'p' -AsPlainText -Force }
                Mock Install-ADDSForestWrapper { throw 'Forest creation failed' }
                Mock Remove-RegisteredSecretVault
                Mock Disconnect-FromAzure

                { New-ADDSForest -DomainName 'contoso.com' `
                    -ResourceGroupName 'MyRG' -KeyVaultName 'MyKV' -SecretName 'DSRMPass' -Confirm:$false } |
                    Should -Throw

                Should -Invoke Remove-RegisteredSecretVault -Times 1
                Should -Invoke Disconnect-FromAzure -Times 1
            }
        }
    }

    Context 'When the password comes from a pre-registered SecretManagement vault' {
        It 'Should retrieve the secret from the vault without connecting to Azure' {
            InModuleScope -ModuleName $script:dscModuleName {
                $mockSecure = ConvertTo-SecureString 'LocalVaultPass!' -AsPlainText -Force
                Mock Get-SecretVaultWrapper {
                    [PSCustomObject]@{ Name = 'LocalVault'; ModuleName = 'Microsoft.PowerShell.SecretStore' }
                }
                Mock Get-SecretWrapper { $mockSecure }
                Mock Connect-ToAzure

                New-ADDSForest -DomainName 'contoso.com' -VaultName 'LocalVault' -SecretName 'DSRMPass' -Confirm:$false

                Should -Invoke Get-SecretWrapper -Times 1 -ParameterFilter { $Vault -eq 'LocalVault' }
                Should -Invoke Connect-ToAzure -Times 0
            }
        }

        It 'Should throw when the specified vault is not registered' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-SecretVaultWrapper { $null }

                { New-ADDSForest -DomainName 'contoso.com' -VaultName 'UnknownVault' -SecretName 'DSRMPass' -Confirm:$false } |
                    Should -Throw -ExpectedMessage "*SecretManagement vault 'UnknownVault' is not registered*"
            }
        }
    }

    Context 'When target directories do not exist' {
        It 'Should create all three AD directories (database, log, sysvol)' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Test-PathWrapper { $false }
                $securePass = ConvertTo-SecureString 'pass' -AsPlainText -Force

                New-ADDSForest -DomainName 'contoso.com' -SafeModeAdministratorPassword $securePass -Confirm:$false

                Should -Invoke New-ItemDirectoryWrapper -Times 3
            }
        }
    }

    Context 'When target directories already exist' {
        It 'Should not call New-ItemDirectoryWrapper' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Test-PathWrapper { $true }
                $securePass = ConvertTo-SecureString 'pass' -AsPlainText -Force

                New-ADDSForest -DomainName 'contoso.com' -SafeModeAdministratorPassword $securePass -Confirm:$false

                Should -Invoke New-ItemDirectoryWrapper -Times 0
            }
        }
    }

    Context 'When -InstallDNS is specified' {
        It 'Should pass InstallDNS = $true to Install-ADDSForestWrapper' {
            InModuleScope -ModuleName $script:dscModuleName {
                $securePass = ConvertTo-SecureString 'pass' -AsPlainText -Force

                New-ADDSForest -DomainName 'contoso.com' -SafeModeAdministratorPassword $securePass -InstallDNS -Confirm:$false

                Should -Invoke Install-ADDSForestWrapper -Times 1 -ParameterFilter {
                    $Parameters.InstallDNS -eq $true
                }
            }
        }
    }

    Context 'When Install-ADDSForestWrapper throws' {
        It 'Should throw an enhanced error message' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Install-ADDSForestWrapper { throw 'Access denied' }
                $securePass = ConvertTo-SecureString 'pass' -AsPlainText -Force

                { New-ADDSForest -DomainName 'contoso.com' -SafeModeAdministratorPassword $securePass -Confirm:$false } |
                    Should -Throw -ExpectedMessage "*AD DS Forest creation failed*"
            }
        }
    }

    Context 'When incomplete Key Vault parameters are provided' {
        It 'Should fall back to interactive prompt when only ResourceGroupName is given' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Connect-ToAzure

                # No SecretName or KeyVaultName — falls back to Get-SafeModePassword prompt
                New-ADDSForest -DomainName 'contoso.com' -ResourceGroupName 'MyRG' -Confirm:$false

                Should -Invoke Connect-ToAzure -Times 0
                Should -Invoke Get-SafeModePassword -Times 1
            }
        }
    }
}
