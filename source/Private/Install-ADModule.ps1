#Requires -Version 7.0

# Installs a Windows Server feature with all sub-features and management tools.
# Idempotent — skips if already installed. Warns if a reboot is required. Metrics in end block.
# No platform/elevation checks — owned by Test-PreflightCheck (DRY).
function Install-ADModule {
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name = 'AD-Domain-Services'
    )

    begin {
        Write-ToLog -Message "Starting Windows feature installation process for '$Name'..." -Level INFO

        $featuresChecked = 0
        $featuresInstalled = 0
        $featuresSkipped = 0
        $featuresFailed = 0
        $_processException = $null
    }

    process {
        try {
            $featuresChecked++
            $_alreadyCounted = $false
            Write-ToLog -Message "Processing Windows feature: $Name" -Level DEBUG

            try {
                # Check if feature is already installed
                $existingFeature = Get-WindowsFeatureWrapper -Name $Name

                if (-not $existingFeature) {
                    # Enhanced error: show available features
                    $bullet = if ($PSStyle) { "$($PSStyle.Foreground.Cyan)•$($PSStyle.Reset)" } else { "•" }
                    $tip = if ($PSStyle) { "$($PSStyle.Foreground.Yellow)ℹ$($PSStyle.Reset)" } else { "ℹ" }

                    $errorMsg = "Feature '$Name' not found on server."

                    # Attempt to list similar features
                    try {
                        $availableFeatures = Get-WindowsFeatureWrapper | Where-Object { $_.Name -like "*AD*" -or $_.Name -like "*Domain*" }
                        if ($availableFeatures) {
                            $featureList = $availableFeatures | Select-Object -First 10 | ForEach-Object {
                                "  ${bullet} $($_.Name) - Installed: $($_.Installed)"
                            }
                            $errorMsg += "`n`nAvailable AD-related features:`n$($featureList -join "`n")"
                            $errorMsg += "`n`n${tip} Tip: Verify the feature name. Use Get-WindowsFeature to list all features."
                        }
                    }
                    catch {
                        # Silently continue if we can't get feature list - best effort only
                        Write-Verbose "Could not retrieve feature list: $($_.Exception.Message)"
                    }

                    Write-ToLog -Message "Feature '$Name' not found on server." -Level ERROR
                    $featuresFailed++
                    $_alreadyCounted = $true
                    throw $errorMsg
                }

                if ($existingFeature.Installed) {
                    Write-ToLog -Message "Feature '$Name' is already installed (State: $($existingFeature.InstallState))." -Level DEBUG
                    $featuresSkipped++
                }
                else {
                    # Install feature
                    Write-ToLog -Message "Installing Windows feature '$Name' (IncludeAllSubFeature: Yes, IncludeManagementTools: Yes)..." -Level INFO
                    $installResult = Install-WindowsFeatureWrapper -Name $Name -IncludeAllSubFeature -IncludeManagementTools

                    # Post-install verification
                    $verifyFeature = Get-WindowsFeatureWrapper -Name $Name

                    if ($verifyFeature -and $verifyFeature.Installed) {
                        Write-ToLog -Message "Feature '$Name' installed successfully (State: $($verifyFeature.InstallState))." -Level SUCCESS

                        # Check if reboot is required
                        if ($installResult.RestartNeeded -eq 'Yes') {
                            Write-ToLog -Message "Feature '$Name' installation requires a system reboot to complete." -Level WARN
                        }

                        $featuresInstalled++
                    }
                    else {
                        $bullet = if ($PSStyle) { "$($PSStyle.Foreground.Cyan)•$($PSStyle.Reset)" } else { "•" }
                        $tip = if ($PSStyle) { "$($PSStyle.Foreground.Yellow)ℹ$($PSStyle.Reset)" } else { "ℹ" }

                        $errorMsg = "Post-install verification failed: Feature '$Name' not installed after Install-WindowsFeature."
                        $errorMsg += "`n`n${tip} Tips:"
                        $errorMsg += "`n  ${bullet} Check Windows Event Logs for installation errors"
                        $errorMsg += "`n  ${bullet} Ensure all prerequisites are met"
                        $errorMsg += "`n  ${bullet} Try installing manually with: Install-WindowsFeature -Name $Name -IncludeAllSubFeature -IncludeManagementTools"

                        Write-ToLog -Message "Verification failed: Feature '$Name' not installed after installation attempt." -Level ERROR
                        $featuresFailed++
                        $_alreadyCounted = $true
                        throw $errorMsg
                    }
                }
            }
            catch {
                if (-not $_alreadyCounted) {
                    Write-ToLog -Message "Failed to install feature '$Name': $($_.Exception.Message)" -Level ERROR
                    $featuresFailed++
                }
                throw
            }
        }
        catch {
            Write-ToLog -Message "Windows feature installation process encountered errors: $($_.Exception.Message)" -Level ERROR
            $_processException = $_
        }
    }

    end {
        # Metrics reporting
        $successRate = if ($featuresChecked -gt 0) {
            [Math]::Round((($featuresInstalled + $featuresSkipped) / $featuresChecked) * 100, 2)
        }
        else {
            0
        }

        Write-ToLog -Message "Windows feature installation completed - Total: $featuresChecked, Installed: $featuresInstalled, Skipped: $featuresSkipped, Failed: $featuresFailed, Success Rate: $successRate%" -Level INFO

        if ($featuresFailed -gt 0) {
            Write-ToLog -Message "Windows feature installation completed with $featuresFailed failure(s)." -Level WARN
        }
        else {
            Write-ToLog -Message "All feature operations completed successfully." -Level SUCCESS
        }

        if ($_processException) {
            throw $_processException.Exception.Message
        }
    }
}

# ============================================================================
# HELPER FUNCTIONS FOR MOCKABILITY
# ============================================================================

# Wraps Get-WindowsFeature for Pester mocking.
function Get-WindowsFeatureWrapper {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]
        $Name
    )

    if ($Name) {
        return Get-WindowsFeature -Name $Name
    }
    else {
        return Get-WindowsFeature
    }
}

# Wraps Install-WindowsFeature for Pester mocking.
function Install-WindowsFeatureWrapper {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param (
        [Parameter(Mandatory)]
        [string]
        $Name,

        [Parameter()]
        [switch]
        $IncludeAllSubFeature,

        [Parameter()]
        [switch]
        $IncludeManagementTools
    )

    return Install-WindowsFeature -Name $Name -IncludeAllSubFeature:$IncludeAllSubFeature -IncludeManagementTools:$IncludeManagementTools
}