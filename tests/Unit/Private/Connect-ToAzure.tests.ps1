#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0.0' }

BeforeAll {
    $script:dscModuleName = 'Invoke-ADDS'
    Import-Module -Name $script:dscModuleName
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Connect-ToAzure' -Tag 'Unit' {

    BeforeEach {
        InModuleScope -ModuleName $script:dscModuleName {
            Mock Write-ToLog
        }
    }

    Context 'When an active Azure context already exists' {
        It 'Should skip authentication and not call Connect-AzAccountWrapper' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-AzContextWrapper { [PSCustomObject]@{ Account = 'user@contoso.com' } }
                Mock Connect-AzAccountWrapper

                Connect-ToAzure

                Should -Invoke Connect-AzAccountWrapper -Times 0
            }
        }
    }

    Context 'When no context exists and authentication succeeds' {
        It 'Should call Connect-AzAccountWrapper then poll until context is confirmed' {
            InModuleScope -ModuleName $script:dscModuleName {
                # $script: scope is shared between mock scriptblocks in InModuleScope
                $script:_azConnected = $false
                Mock Get-AzContextWrapper {
                    if ($script:_azConnected) { [PSCustomObject]@{ Account = 'user@contoso.com' } }
                    else { $null }
                }
                Mock Connect-AzAccountWrapper { $script:_azConnected = $true }
                Mock Test-TimeoutElapsedWrapper { $false }
                Mock Start-Sleep

                Connect-ToAzure

                Should -Invoke Connect-AzAccountWrapper -Times 1
            }
        }
    }

    Context 'When authentication times out' {
        It 'Should throw a timeout error after the timeout period elapses' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-AzContextWrapper { $null }
                Mock Connect-AzAccountWrapper
                Mock Test-TimeoutElapsedWrapper { $true }
                Mock Start-Sleep

                { Connect-ToAzure -TimeoutMinutes 1 } | Should -Throw -ExpectedMessage '*timed out*'
            }
        }
    }

    Context 'When Connect-AzAccountWrapper throws an exception' {
        It 'Should surface the error' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-AzContextWrapper { $null }
                Mock Connect-AzAccountWrapper { throw 'Auth failure' }

                { Connect-ToAzure } | Should -Throw
            }
        }
    }

    Context 'When using -WhatIf' {
        It 'Should not call Connect-AzAccountWrapper' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-AzContextWrapper { $null }
                Mock Connect-AzAccountWrapper

                Connect-ToAzure -WhatIf

                Should -Invoke Connect-AzAccountWrapper -Times 0
            }
        }
    }

    Context 'When using -UseManagedIdentity' {
        It 'Should call Connect-AzAccountManagedIdentityWrapper and not the device-code wrapper' {
            InModuleScope -ModuleName $script:dscModuleName {
                $script:_azConnected = $false
                Mock Get-AzContextWrapper {
                    if ($script:_azConnected) { [PSCustomObject]@{ Account = 'identity@contoso.com' } }
                    else { $null }
                }
                Mock Connect-AzAccountManagedIdentityWrapper { $script:_azConnected = $true }
                Mock Connect-AzAccountWrapper

                Connect-ToAzure -UseManagedIdentity

                Should -Invoke Connect-AzAccountManagedIdentityWrapper -Times 1
                Should -Invoke Connect-AzAccountWrapper -Times 0
            }
        }

        It 'Should pass -AccountId through for a user-assigned identity' {
            InModuleScope -ModuleName $script:dscModuleName {
                $script:_azConnected = $false
                Mock Get-AzContextWrapper {
                    if ($script:_azConnected) { [PSCustomObject]@{ Account = 'identity@contoso.com' } }
                    else { $null }
                }
                Mock Connect-AzAccountManagedIdentityWrapper { $script:_azConnected = $true }

                Connect-ToAzure -UseManagedIdentity -ManagedIdentityClientId '11111111-1111-1111-1111-111111111111'

                Should -Invoke Connect-AzAccountManagedIdentityWrapper -Times 1 -ParameterFilter {
                    $AccountId -eq '11111111-1111-1111-1111-111111111111'
                }
            }
        }
    }

    Context 'When using -FederatedToken (workload identity federation)' {
        It 'Should call Connect-AzAccountWorkloadIdentityWrapper with the supplied token, application and tenant' {
            InModuleScope -ModuleName $script:dscModuleName {
                $script:_azConnected = $false
                Mock Get-AzContextWrapper {
                    if ($script:_azConnected) { [PSCustomObject]@{ Account = 'workload@contoso.com' } }
                    else { $null }
                }
                Mock Connect-AzAccountWorkloadIdentityWrapper { $script:_azConnected = $true }

                Connect-ToAzure -FederatedToken 'fake-token' -ApplicationId 'app-id' -TenantId 'tenant-id'

                Should -Invoke Connect-AzAccountWorkloadIdentityWrapper -Times 1 -ParameterFilter {
                    $FederatedToken -eq 'fake-token' -and $ApplicationId -eq 'app-id' -and $TenantId -eq 'tenant-id'
                }
            }
        }
    }

    Context 'When using -CertificateThumbprint (app-only certificate)' {
        It 'Should call Connect-AzAccountCertificateWrapper with the supplied certificate and application' {
            InModuleScope -ModuleName $script:dscModuleName {
                $script:_azConnected = $false
                Mock Get-AzContextWrapper {
                    if ($script:_azConnected) { [PSCustomObject]@{ Account = 'cert-app@contoso.com' } }
                    else { $null }
                }
                Mock Connect-AzAccountCertificateWrapper { $script:_azConnected = $true }

                Connect-ToAzure -CertificateThumbprint 'ABC123' -CertificateApplicationId 'app-id' -TenantId 'tenant-id'

                Should -Invoke Connect-AzAccountCertificateWrapper -Times 1 -ParameterFilter {
                    $CertificateThumbprint -eq 'ABC123' -and $ApplicationId -eq 'app-id' -and $TenantId -eq 'tenant-id'
                }
            }
        }
    }

    Context 'When using -ServicePrincipalCredential (client secret, last-resort app-only)' {
        It 'Should call Connect-AzAccountClientSecretWrapper with the supplied credential and tenant' {
            InModuleScope -ModuleName $script:dscModuleName {
                $script:_azConnected = $false
                Mock Get-AzContextWrapper {
                    if ($script:_azConnected) { [PSCustomObject]@{ Account = 'secret-app@contoso.com' } }
                    else { $null }
                }
                Mock Connect-AzAccountClientSecretWrapper { $script:_azConnected = $true }
                $cred = [pscredential]::new('app-id', (ConvertTo-SecureString 'not-a-real-secret' -AsPlainText -Force))

                Connect-ToAzure -ServicePrincipalCredential $cred -TenantId 'tenant-id'

                Should -Invoke Connect-AzAccountClientSecretWrapper -Times 1 -ParameterFilter {
                    $TenantId -eq 'tenant-id'
                }
            }
        }
    }

    Context 'When using -UseInteractiveBrowser' {
        It 'Should call Connect-AzAccountInteractiveWrapper and not the device-code wrapper' {
            InModuleScope -ModuleName $script:dscModuleName {
                $script:_azConnected = $false
                Mock Get-AzContextWrapper {
                    if ($script:_azConnected) { [PSCustomObject]@{ Account = 'interactive@contoso.com' } }
                    else { $null }
                }
                Mock Connect-AzAccountInteractiveWrapper { $script:_azConnected = $true }
                Mock Connect-AzAccountWrapper

                Connect-ToAzure -UseInteractiveBrowser

                Should -Invoke Connect-AzAccountInteractiveWrapper -Times 1
                Should -Invoke Connect-AzAccountWrapper -Times 0
            }
        }
    }

    Context 'When using -UseExistingContext and a context already exists' {
        It 'Should succeed and call no Connect wrapper' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-AzContextWrapper { [PSCustomObject]@{ Account = 'existing@contoso.com' } }
                Mock Connect-AzAccountWrapper
                Mock Connect-AzAccountManagedIdentityWrapper
                Mock Connect-AzAccountWorkloadIdentityWrapper
                Mock Connect-AzAccountCertificateWrapper
                Mock Connect-AzAccountClientSecretWrapper
                Mock Connect-AzAccountInteractiveWrapper

                { Connect-ToAzure -UseExistingContext } | Should -Not -Throw

                Should -Invoke Connect-AzAccountWrapper -Times 0
                Should -Invoke Connect-AzAccountManagedIdentityWrapper -Times 0
                Should -Invoke Connect-AzAccountWorkloadIdentityWrapper -Times 0
                Should -Invoke Connect-AzAccountCertificateWrapper -Times 0
                Should -Invoke Connect-AzAccountClientSecretWrapper -Times 0
                Should -Invoke Connect-AzAccountInteractiveWrapper -Times 0
            }
        }
    }

    Context 'When using -UseExistingContext and no context exists' {
        It 'Should throw an actionable error and call no Connect wrapper' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-AzContextWrapper { $null }
                Mock Connect-AzAccountWrapper

                { Connect-ToAzure -UseExistingContext } | Should -Throw -ExpectedMessage '*UseExistingContext*already exist*'

                Should -Invoke Connect-AzAccountWrapper -Times 0
            }
        }
    }

    Context 'When device-code sign-in is blocked by Conditional Access' {
        It 'Should reword the error to point at the unattended parameter sets' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-AzContextWrapper { $null }
                Mock Connect-AzAccountWrapper { throw 'AADSTS50079: Due to a configuration change made by your administrator, or because you moved to a new location, you must enroll in multifactor authentication (conditional access).' }

                { Connect-ToAzure } | Should -Throw -ExpectedMessage '*Conditional Access*UseManagedIdentity*'
            }
        }
    }

    Context 'When validating TimeoutMinutes parameter' {
        It 'Should throw a validation error when TimeoutMinutes is 0' {
            InModuleScope -ModuleName $script:dscModuleName {
                { Connect-ToAzure -TimeoutMinutes 0 } | Should -Throw
            }
        }

        It 'Should throw a validation error when TimeoutMinutes exceeds 120' {
            InModuleScope -ModuleName $script:dscModuleName {
                { Connect-ToAzure -TimeoutMinutes 121 } | Should -Throw
            }
        }

        It 'Should accept TimeoutMinutes = 1 (minimum valid value)' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Get-AzContextWrapper { [PSCustomObject]@{ Account = 'user@contoso.com' } }

                { Connect-ToAzure -TimeoutMinutes 1 } | Should -Not -Throw
            }
        }
    }
}
