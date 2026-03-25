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

Describe 'Test-PreflightCheck' -Tag 'Unit' {

    Context 'When all checks pass' {
        It 'Should return $true when platform, feature, and path checks all pass' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock -ModuleName $script:dscModuleName -CommandName Test-IsWindowsPlatform -MockWith { return $true }
                Mock Get-CimInstance { [PSCustomObject]@{ ProductType = 3; Caption = 'Windows Server 2025' } }
                Mock Get-WindowsFeatureWrapper { [PSCustomObject]@{ Name = 'AD-Domain-Services'; Installed = $true; InstallState = 'Installed' } }

                $result = Test-PreflightCheck -RequiredFeatures @('AD-Domain-Services')

                $result | Should -BeTrue
            }
        }
    }

    Context 'When the platform is not Windows Server (ProductType != 3)' {
        It 'Should throw when ProductType is 1 (Workstation)' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock -ModuleName $script:dscModuleName -CommandName Test-IsWindowsPlatform -MockWith { return $true }
                Mock Get-CimInstance { [PSCustomObject]@{ ProductType = 1; Caption = 'Windows 11 Pro' } }

                { Test-PreflightCheck } | Should -Throw -ExpectedMessage '*Windows Server required*'
            }
        }

        It 'Should throw when ProductType is 2 (backup domain controller)' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock -ModuleName $script:dscModuleName -CommandName Test-IsWindowsPlatform -MockWith { return $true }
                Mock Get-CimInstance { [PSCustomObject]@{ ProductType = 2; Caption = 'Windows Server 2025' } }

                { Test-PreflightCheck } | Should -Throw
            }
        }
    }

    Context 'When a required feature is not installed but is available' {
        It 'Should return $false when the feature exists but is not installed' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock -ModuleName $script:dscModuleName -CommandName Test-IsWindowsPlatform -MockWith { return $true }
                Mock Get-CimInstance { [PSCustomObject]@{ ProductType = 3; Caption = 'Windows Server 2025' } }
                Mock Get-WindowsFeatureWrapper { [PSCustomObject]@{ Name = 'AD-Domain-Services'; Installed = $false; InstallState = 'Available' } }

                $result = Test-PreflightCheck -RequiredFeatures @('AD-Domain-Services')

                $result | Should -BeFalse
            }
        }
    }

    Context 'When a required feature is not found on the server' {
        It 'Should throw when the feature cannot be found' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock -ModuleName $script:dscModuleName -CommandName Test-IsWindowsPlatform -MockWith { return $true }
                Mock Get-CimInstance { [PSCustomObject]@{ ProductType = 3; Caption = 'Windows Server 2025' } }
                Mock Get-WindowsFeatureWrapper -ParameterFilter { $Name } { $null }
                Mock Get-WindowsFeatureWrapper { @() }

                { Test-PreflightCheck -RequiredFeatures @('NonExistentFeature') } | Should -Throw
            }
        }
    }

    Context 'When no required features are specified' {
        It 'Should skip feature validation and return $true' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock -ModuleName $script:dscModuleName -CommandName Test-IsWindowsPlatform -MockWith { return $true }
                Mock Get-CimInstance { [PSCustomObject]@{ ProductType = 3; Caption = 'Windows Server 2025' } }

                $result = Test-PreflightCheck -RequiredFeatures @()

                $result | Should -BeTrue
            }
        }
    }

    Context 'When a required path does not exist' {
        It 'Should throw when a required path is missing' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock -ModuleName $script:dscModuleName -CommandName Test-IsWindowsPlatform -MockWith { return $true }
                Mock Get-CimInstance { [PSCustomObject]@{ ProductType = 3; Caption = 'Windows Server 2025' } }
                Mock Get-WindowsFeatureWrapper { [PSCustomObject]@{ Name = 'AD-Domain-Services'; Installed = $true; InstallState = 'Installed' } }
                Mock Test-PathWrapper { $false }

                { Test-PreflightCheck -RequiredFeatures @('AD-Domain-Services') -RequiredPaths @('C:\NonExistent') } |
                    Should -Throw -ExpectedMessage "*Required path*does not exist*"
            }
        }
    }

    Context 'When disk space is insufficient' {
        It 'Should throw when free space is below MinDiskGB' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock -ModuleName $script:dscModuleName -CommandName Test-IsWindowsPlatform -MockWith { return $true }
                Mock Get-CimInstance { [PSCustomObject]@{ ProductType = 3; Caption = 'Windows Server 2025' } }
                Mock Get-WindowsFeatureWrapper { [PSCustomObject]@{ Name = 'AD-Domain-Services'; Installed = $true; InstallState = 'Installed' } }
                Mock Test-PathWrapper { $true }
                Mock Get-PSDrive { [PSCustomObject]@{ Name = 'C'; Root = 'C:\'; Free = 1GB; Used = 200GB } }

                { Test-PreflightCheck -RequiredFeatures @('AD-Domain-Services') -RequiredPaths @('C:\Windows') -MinDiskGB 4 } |
                    Should -Throw -ExpectedMessage '*Insufficient disk space*'
            }
        }
    }

    Context 'When disk space is sufficient' {
        It 'Should return $true when free space meets MinDiskGB' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock -ModuleName $script:dscModuleName -CommandName Test-IsWindowsPlatform -MockWith { return $true }
                Mock Get-CimInstance { [PSCustomObject]@{ ProductType = 3; Caption = 'Windows Server 2025' } }
                Mock Get-WindowsFeatureWrapper { [PSCustomObject]@{ Name = 'AD-Domain-Services'; Installed = $true; InstallState = 'Installed' } }
                Mock Test-PathWrapper { $true }
                Mock Get-PSDrive { [PSCustomObject]@{ Name = 'C'; Root = 'C:\'; Free = 20GB; Used = 200GB } }

                $result = Test-PreflightCheck -RequiredFeatures @('AD-Domain-Services') -RequiredPaths @('C:\Windows') -MinDiskGB 4

                $result | Should -BeTrue
            }
        }
    }

    Context 'When validating MinDiskGB parameter boundaries' {
        It 'Should throw a validation error when MinDiskGB is 0' {
            InModuleScope -ModuleName $script:dscModuleName {
                { Test-PreflightCheck -MinDiskGB 0 } | Should -Throw
            }
        }

        It 'Should throw a validation error when MinDiskGB exceeds 1000' {
            InModuleScope -ModuleName $script:dscModuleName {
                { Test-PreflightCheck -MinDiskGB 1001 } | Should -Throw
            }
        }

        It 'Should accept MinDiskGB = 1 (minimum valid value)' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock -ModuleName $script:dscModuleName -CommandName Test-IsWindowsPlatform -MockWith { return $true }
                Mock Get-CimInstance { [PSCustomObject]@{ ProductType = 3; Caption = 'Windows Server 2025' } }

                { Test-PreflightCheck -RequiredFeatures @() -MinDiskGB 1 } | Should -Not -Throw
            }
        }
    }
}
