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

Describe 'New-ADDomainController' -Tag 'Unit' {

    BeforeEach {
        InModuleScope -ModuleName $script:dscModuleName {
            $script:mockCred = [PSCredential]::new(
                'CONTOSO\Admin',
                (ConvertTo-SecureString 'AdminPass!' -AsPlainText -Force)
            )
            Mock Write-ToLog
            Mock Test-PreflightCheck { $true }
            Mock Install-ADModule
            Mock Invoke-ResourceModule
            Mock Get-SafeModePassword { ConvertTo-SecureString 'TestPass123!' -AsPlainText -Force }
            Mock Get-Credential { $script:mockCred }
            Mock Test-PathWrapper { $true }
            Mock New-ItemDirectoryWrapper
            Mock Install-ADDomainControllerWrapper
        }
    }

    Context 'When using -WhatIf' {
        It 'Should not call Install-ADDomainControllerWrapper' {
            InModuleScope -ModuleName $script:dscModuleName {
                New-ADDomainController -DomainName 'contoso.com' -WhatIf

                Should -Invoke Install-ADDomainControllerWrapper -Times 0
            }
        }
    }

    Context 'When a password is supplied directly' {
        It 'Should not connect to Azure' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Connect-ToAzure
                $securePass = ConvertTo-SecureString 'DirectPass123!' -AsPlainText -Force

                New-ADDomainController -DomainName 'contoso.com' `
                    -SafeModeAdministratorPassword $securePass -DomainAdminCredential $script:mockCred -Confirm:$false

                Should -Invoke Connect-ToAzure -Times 0
            }
        }

        It 'Should call Install-ADDomainControllerWrapper with DomainName and SiteName' {
            InModuleScope -ModuleName $script:dscModuleName {
                $securePass = ConvertTo-SecureString 'DirectPass123!' -AsPlainText -Force

                New-ADDomainController -DomainName 'contoso.com' -SiteName 'London-Site' `
                    -SafeModeAdministratorPassword $securePass -DomainAdminCredential $script:mockCred -Confirm:$false

                Should -Invoke Install-ADDomainControllerWrapper -Times 1 -ParameterFilter {
                    $Parameters.DomainName -eq 'contoso.com' -and $Parameters.SiteName -eq 'London-Site'
                }
            }
        }

        It 'Should use Default-First-Site-Name when SiteName is not specified' {
            InModuleScope -ModuleName $script:dscModuleName {
                $securePass = ConvertTo-SecureString 'DirectPass123!' -AsPlainText -Force

                New-ADDomainController -DomainName 'contoso.com' `
                    -SafeModeAdministratorPassword $securePass -DomainAdminCredential $script:mockCred -Confirm:$false

                Should -Invoke Install-ADDomainControllerWrapper -Times 1 -ParameterFilter {
                    $Parameters.SiteName -eq 'Default-First-Site-Name'
                }
            }
        }
    }

    Context 'When the password comes from Azure Key Vault' {
        It 'Should connect to Azure and retrieve the secret' {
            InModuleScope -ModuleName $script:dscModuleName {
                $mockSecure = ConvertTo-SecureString 'VaultPass!' -AsPlainText -Force
                Mock Connect-ToAzure
                Mock Get-Vault { [PSCustomObject]@{ VaultName = 'MyKV' } }
                Mock Add-RegisteredSecretVault
                Mock Get-SecretWrapper { $mockSecure }
                Mock Remove-RegisteredSecretVault
                Mock Disconnect-FromAzure

                New-ADDomainController -DomainName 'contoso.com' -DomainAdminCredential $script:mockCred `
                    -ResourceGroupName 'MyRG' -KeyVaultName 'MyKV' -SecretName 'DSRMPass' -Confirm:$false

                Should -Invoke Connect-ToAzure -Times 1
                Should -Invoke Get-SecretWrapper -Times 1 -ParameterFilter {
                    $Name -eq 'DSRMPass' -and $Vault -eq 'MyKV'
                }
            }
        }

        It 'Should disconnect and unregister vault in the finally block even when an error occurs' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Connect-ToAzure
                Mock Get-Vault { [PSCustomObject]@{ VaultName = 'MyKV' } }
                Mock Add-RegisteredSecretVault
                Mock Get-SecretWrapper { ConvertTo-SecureString 'pass' -AsPlainText -Force }
                Mock Install-ADDomainControllerWrapper { throw 'Promotion failed' }
                Mock Remove-RegisteredSecretVault
                Mock Disconnect-FromAzure

                { New-ADDomainController -DomainName 'contoso.com' -DomainAdminCredential $script:mockCred `
                    -ResourceGroupName 'MyRG' -KeyVaultName 'MyKV' -SecretName 'DSRMPass' -Confirm:$false } |
                    Should -Throw

                Should -Invoke Remove-RegisteredSecretVault -Times 1
                Should -Invoke Disconnect-FromAzure -Times 1
            }
        }
    }

    Context 'When the password comes from a pre-registered SecretManagement vault' {
        It 'Should retrieve the secret without connecting to Azure' {
            InModuleScope -ModuleName $script:dscModuleName {
                $mockSecure = ConvertTo-SecureString 'LocalVaultPass!' -AsPlainText -Force
                Mock Get-SecretVaultWrapper {
                    [PSCustomObject]@{ Name = 'LocalVault'; ModuleName = 'Microsoft.PowerShell.SecretStore' }
                }
                Mock Get-SecretWrapper { $mockSecure }
                Mock Connect-ToAzure

                New-ADDomainController -DomainName 'contoso.com' -DomainAdminCredential $script:mockCred `
                    -VaultName 'LocalVault' -SecretName 'DSRMPass' -Confirm:$false

                Should -Invoke Get-SecretWrapper -Times 1 -ParameterFilter { $Vault -eq 'LocalVault' }
                Should -Invoke Connect-ToAzure -Times 0
            }
        }

        It 'Should throw when the specified vault is not registered' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-SecretVaultWrapper { $null }

                { New-ADDomainController -DomainName 'contoso.com' -DomainAdminCredential $script:mockCred `
                    -VaultName 'UnknownVault' -SecretName 'DSRMPass' -Confirm:$false } |
                    Should -Throw -ExpectedMessage "*SecretManagement vault 'UnknownVault' is not registered*"
            }
        }
    }

    Context 'When DomainAdminCredential is not supplied' {
        It 'Should prompt for credentials via Get-Credential' {
            InModuleScope -ModuleName $script:dscModuleName {
                $securePass = ConvertTo-SecureString 'DirectPass123!' -AsPlainText -Force

                New-ADDomainController -DomainName 'contoso.com' `
                    -SafeModeAdministratorPassword $securePass -Confirm:$false

                Should -Invoke Get-Credential -Times 1
            }
        }
    }

    Context 'When target directories do not exist' {
        It 'Should create all three AD directories' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Test-PathWrapper { $false }
                $securePass = ConvertTo-SecureString 'pass' -AsPlainText -Force

                New-ADDomainController -DomainName 'contoso.com' `
                    -SafeModeAdministratorPassword $securePass -DomainAdminCredential $script:mockCred -Confirm:$false

                Should -Invoke New-ItemDirectoryWrapper -Times 3
            }
        }
    }

    Context 'When target directories already exist' {
        It 'Should not call New-ItemDirectoryWrapper' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Test-PathWrapper { $true }
                $securePass = ConvertTo-SecureString 'pass' -AsPlainText -Force

                New-ADDomainController -DomainName 'contoso.com' `
                    -SafeModeAdministratorPassword $securePass -DomainAdminCredential $script:mockCred -Confirm:$false

                Should -Invoke New-ItemDirectoryWrapper -Times 0
            }
        }
    }

    Context 'When Install-ADDomainControllerWrapper throws' {
        It 'Should throw an enhanced error message' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Install-ADDomainControllerWrapper { throw 'Promotion failed' }
                $securePass = ConvertTo-SecureString 'pass' -AsPlainText -Force

                { New-ADDomainController -DomainName 'contoso.com' `
                    -SafeModeAdministratorPassword $securePass -DomainAdminCredential $script:mockCred -Confirm:$false } |
                    Should -Throw -ExpectedMessage "*Domain controller promotion failed*"
            }
        }
    }

    Context 'When -InstallDNS is specified' {
        It 'Should pass InstallDNS = $true to Install-ADDomainControllerWrapper' {
            InModuleScope -ModuleName $script:dscModuleName {
                $securePass = ConvertTo-SecureString 'pass' -AsPlainText -Force

                New-ADDomainController -DomainName 'contoso.com' `
                    -SafeModeAdministratorPassword $securePass -DomainAdminCredential $script:mockCred `
                    -InstallDNS -Confirm:$false

                Should -Invoke Install-ADDomainControllerWrapper -Times 1 -ParameterFilter {
                    $Parameters.InstallDNS -eq $true
                }
            }
        }
    }
}
