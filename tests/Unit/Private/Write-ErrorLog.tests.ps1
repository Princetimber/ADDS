#Requires -Version 7.0

BeforeAll {
    $script:dscModuleName = 'Invoke-ADDS'

    Import-Module -Name $script:dscModuleName
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'Write-ErrorLog' -Tag 'Unit' {

    BeforeEach {
        InModuleScope -ModuleName $script:dscModuleName {
            $script:LogFile = Join-Path $TestDrive 'module.log'
            $script:LogDirectoryCreated = $true
            $script:LogMutex = $null
        }
    }

    Context 'When no custom message prefix is provided' {
        It 'Should delegate to Write-ToLog using the ErrorRecord parameter set' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Write-ToLog

                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Unhandled error'),
                    'TestError', [System.Management.Automation.ErrorCategory]::NotSpecified, $null
                )

                Write-ErrorLog -ErrorRecord $errorRecord

                Should -Invoke Write-ToLog -Times 1 -ParameterFilter {
                    $null -ne $ErrorRecord
                }
            }
        }
    }

    Context 'When a custom message prefix is provided' {
        It 'Should log the prefix combined with the exception message at ERROR level' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Write-ToLog

                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Connection refused'),
                    'TestError', [System.Management.Automation.ErrorCategory]::NotSpecified, $null
                )

                Write-ErrorLog -ErrorRecord $errorRecord -Message 'Failed to connect:'

                Should -Invoke Write-ToLog -Times 1 -ParameterFilter {
                    $Level -eq 'ERROR' -and
                    $Message -match 'Failed to connect:' -and
                    $Message -match 'Connection refused'
                }
            }
        }

        It 'Should log exception type at DEBUG level' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Write-ToLog

                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Some error'),
                    'TestError', [System.Management.Automation.ErrorCategory]::NotSpecified, $null
                )

                Write-ErrorLog -ErrorRecord $errorRecord -Message 'Context:'

                Should -Invoke Write-ToLog -Times 1 -ParameterFilter {
                    $Level -eq 'DEBUG' -and $Message -match 'Error Type:'
                }
            }
        }

        It 'Should log error category at DEBUG level' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Write-ToLog

                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Some error'),
                    'TestError', [System.Management.Automation.ErrorCategory]::NotSpecified, $null
                )

                Write-ErrorLog -ErrorRecord $errorRecord -Message 'Context:'

                Should -Invoke Write-ToLog -Times 1 -ParameterFilter {
                    $Level -eq 'DEBUG' -and $Message -match 'Error Category:'
                }
            }
        }
    }

    Context 'When IncludeStackTrace is specified' {
        It 'Should log the stack trace at DEBUG level when ScriptStackTrace is available' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Write-ToLog

                # Build an ErrorRecord with a ScriptStackTrace by catching a real error
                try {
                    throw 'Stack trace test'
                } catch {
                    $errorRecord = $_
                }

                Write-ErrorLog -ErrorRecord $errorRecord -IncludeStackTrace

                Should -Invoke Write-ToLog -Times 1 -ParameterFilter {
                    $Level -eq 'DEBUG' -and $Message -match 'Stack Trace'
                }
            }
        }
    }

    Context 'When IncludeStackTrace is not specified' {
        It 'Should not log the stack trace' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Write-ToLog

                try {
                    throw 'No stack trace needed'
                } catch {
                    $errorRecord = $_
                }

                Write-ErrorLog -ErrorRecord $errorRecord

                Should -Invoke Write-ToLog -Times 0 -ParameterFilter {
                    $Level -eq 'DEBUG' -and $Message -match 'Stack Trace'
                }
            }
        }
    }

    Context 'When an ErrorRecord with an InnerException is provided' {
        It 'Should log the inner exception message at DEBUG level' {
            InModuleScope -ModuleName $script:dscModuleName {
                Mock Write-ToLog

                $innerException = [System.Exception]::new('Inner cause')
                $outerException = [System.Exception]::new('Outer error', $innerException)
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $outerException, 'TestError',
                    [System.Management.Automation.ErrorCategory]::NotSpecified, $null
                )

                Write-ErrorLog -ErrorRecord $errorRecord -Message 'Operation failed:'

                Should -Invoke Write-ToLog -Times 1 -ParameterFilter {
                    $Level -eq 'DEBUG' -and $Message -match 'Inner Exception:'
                }
            }
        }
    }
}
