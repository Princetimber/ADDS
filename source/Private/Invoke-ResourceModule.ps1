#Requires -Version 7.0

# Installs a PowerShell module from PSGallery using PSResourceGet.
# Validates PSGallery is registered, then installs if the module is not already present.
# Idempotent — skips if the module is already loaded. Metrics in end block.
function Invoke-ResourceModule {
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Name = @('Microsoft.PowerShell.SecretManagement', 'Az.KeyVault')
    )

    begin {
        Write-ToLog -Message "Starting module installation process for $($Name.Count) module(s)..." -Level INFO

        $modulesChecked = 0
        $modulesInstalled = 0
        $modulesSkipped = 0
        $modulesFailed = 0

        # Repository validation: Ensure PSGallery is registered and accessible
        try {
            $repository = Get-PSResourceRepository -Name PSGallery -ErrorAction Stop

            if (-not $repository) {
                $bullet = if ($PSStyle) { "$($PSStyle.Foreground.Cyan)•$($PSStyle.Reset)" } else { "•" }
                $tip = if ($PSStyle) { "$($PSStyle.Foreground.Yellow)ℹ$($PSStyle.Reset)" } else { "ℹ" }

                $errorMsg = "Repository validation failed: PSGallery not found."
                $errorMsg += "`n`n${tip} Tip: Register PSGallery with: Register-PSResourceRepository -PSGallery"

                # Try to list available repositories
                try {
                    $availableRepos = Get-PSResourceRepository
                    if ($availableRepos) {
                        $repoList = $availableRepos | ForEach-Object {
                            "  ${bullet} $($_.Name) - URI: $($_.Uri)"
                        }
                        $errorMsg += "`n`nAvailable repositories:`n$($repoList -join "`n")"
                    }
                }
                catch {
                    # Silently continue if we can't get repository list - best effort only
                    Write-Verbose "Could not retrieve repository list: $($_.Exception.Message)"
                }

                throw $errorMsg
            }

            Write-ToLog -Message "Repository validated: PSGallery is registered (URI: $($repository.Uri))." -Level DEBUG
        }
        catch {
            Write-ToLog -Message "Repository validation error: $($_.Exception.Message)" -Level ERROR
            throw
        }
    }

    process {
        try {
            foreach ($moduleName in $Name) {
                $modulesChecked++
                Write-ToLog -Message "Processing module: $moduleName" -Level DEBUG

                try {
                    # Check if module is already installed
                    $existingModule = Get-ModuleWrapper -Name $moduleName -ListAvailable

                    if ($existingModule) {
                        Write-ToLog -Message "Module '$moduleName' is already installed (Version: $($existingModule.Version))." -Level DEBUG
                        $modulesSkipped++
                        continue
                    }

                    # Set PSGallery as trusted to avoid prompts
                    Write-ToLog -Message "Setting PSGallery as trusted repository..." -Level DEBUG
                    Set-PSResourceRepositoryWrapper -Name PSGallery -Trusted

                    # Install module
                    Write-ToLog -Message "Installing module '$moduleName' from PSGallery (Scope: AllUsers)..." -Level INFO
                    Install-PSResourceWrapper -Name $moduleName -Repository PSGallery -Scope AllUsers -Confirm:$false

                    # Post-install verification
                    $verifyModule = Get-ModuleWrapper -Name $moduleName -ListAvailable

                    if ($verifyModule) {
                        Write-ToLog -Message "Module '$moduleName' installed successfully (Version: $($verifyModule.Version))." -Level SUCCESS
                        $modulesInstalled++
                    }
                    else {
                        $bullet = if ($PSStyle) { "$($PSStyle.Foreground.Cyan)•$($PSStyle.Reset)" } else { "•" }
                        $tip = if ($PSStyle) { "$($PSStyle.Foreground.Yellow)ℹ$($PSStyle.Reset)" } else { "ℹ" }

                        $errorMsg = "Post-install verification failed: Module '$moduleName' not found after installation."
                        $errorMsg += "`n`n${tip} Tip: Check module name spelling or try installing manually with: Install-PSResource -Name $moduleName"

                        Write-ToLog -Message "Verification failed: Module '$moduleName' not found after installation." -Level ERROR
                        $modulesFailed++
                        throw $errorMsg
                    }
                }
                catch {
                    Write-ToLog -Message "Failed to install module '$moduleName': $($_.Exception.Message)" -Level ERROR
                    $modulesFailed++

                    # Enhanced error message for common issues
                    if ($_.Exception.Message -like "*not found*" -and $_.Exception.Message -notlike "*Post-install verification*") {
                        $bullet = if ($PSStyle) { "$($PSStyle.Foreground.Cyan)•$($PSStyle.Reset)" } else { "•" }
                        $tip = if ($PSStyle) { "$($PSStyle.Foreground.Yellow)ℹ$($PSStyle.Reset)" } else { "ℹ" }

                        $errorMsg = "Module '$moduleName' not found in PSGallery."
                        $errorMsg += "`n`n${tip} Tips:"
                        $errorMsg += "`n  ${bullet} Verify module name at https://www.powershellgallery.com/"
                        $errorMsg += "`n  ${bullet} Check spelling and capitalization"
                        $errorMsg += "`n  ${bullet} Ensure internet connectivity to PSGallery"

                        throw $errorMsg
                    }
                    else {
                        throw
                    }
                }
            }
        }
        catch {
            Write-ToLog -Message "Module installation process encountered errors: $($_.Exception.Message)" -Level ERROR
            throw
        }
    }

    end {
        # Metrics reporting
        $successRate = if ($modulesChecked -gt 0) {
            [Math]::Round((($modulesInstalled + $modulesSkipped) / $modulesChecked) * 100, 2)
        }
        else {
            0
        }

        Write-ToLog -Message "Module installation completed - Total: $modulesChecked, Installed: $modulesInstalled, Skipped: $modulesSkipped, Failed: $modulesFailed, Success Rate: $successRate%" -Level INFO

        if ($modulesFailed -gt 0) {
            Write-ToLog -Message "Module installation completed with $modulesFailed failure(s)." -Level WARN
        }
        else {
            Write-ToLog -Message "All module operations completed successfully." -Level SUCCESS
        }
    }
}

# ============================================================================
# HELPER FUNCTIONS FOR MOCKABILITY
# ============================================================================

# Wraps Get-Module for Pester mocking.
function Get-ModuleWrapper {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]
        $Name,

        [Parameter()]
        [switch]
        $ListAvailable
    )

    if ($Name) {
        return Get-Module -Name $Name -ListAvailable:$ListAvailable
    }
    else {
        return Get-Module -ListAvailable:$ListAvailable
    }
}

# Wraps Set-PSResourceRepository for Pester mocking.
function Set-PSResourceRepositoryWrapper {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param (
        [Parameter(Mandatory)]
        [string]
        $Name,

        [Parameter()]
        [switch]
        $Trusted
    )

    Set-PSResourceRepository -Name $Name -Trusted:$Trusted
}

# Wraps Install-PSResource for Pester mocking.
function Install-PSResourceWrapper {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSupportsShouldProcess', '')]
    param (
        [Parameter(Mandatory)]
        [string]
        $Name,

        [Parameter()]
        [string]
        $Repository,

        [Parameter()]
        [string]
        $Scope,

        [Parameter()]
        [bool]
        $Confirm
    )

    Install-PSResource -Name $Name -Repository $Repository -Scope $Scope -Confirm:$Confirm
}