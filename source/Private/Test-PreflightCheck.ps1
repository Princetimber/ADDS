#Requires -Version 7.0

# Validates platform (Windows Server), elevation, Windows features, required paths, and disk space.
# Single source of truth for all environment validation — callers must NOT duplicate these checks.
# Returns $true when all checks pass; throws on first failure.
function Test-PreflightCheck {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter()]
        [ValidateNotNull()]
        [string[]]
        $RequiredFeatures = @('AD-Domain-Services'),

        [Parameter()]
        [ValidateNotNull()]
        [string[]]
        $RequiredPaths = @(),

        [Parameter()]
        [ValidateRange(1, 1000)]
        [int]
        $MinDiskGB = 4
    )

        begin {
        $_earlyExit = $false
        Write-ToLog -Message "Starting preflight checks..." -Level INFO

        $checksPerformed = 0
        $checksPassed = 0
        $checksFailed = 0

        # Platform validation: Windows Server required
        $checksPerformed++
        try {
            if (-not (Test-IsWindowsPlatform)) {
                Write-ToLog -Message "Platform check failed: This module requires Windows operating system." -Level ERROR
                $checksFailed++
                $_earlyExit = $true
                return
            }

            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
            if ($os.ProductType -ne 3) {
                $bullet = if ($PSStyle) { "$($PSStyle.Foreground.Cyan)•$($PSStyle.Reset)" } else { "•" }
                $tip = if ($PSStyle) { "$($PSStyle.Foreground.Yellow)ℹ$($PSStyle.Reset)" } else { "ℹ" }

                $errorMsg = "Platform validation failed: Windows Server required (ProductType 3)."
                $errorMsg += "`n`nCurrent system:`n  ${bullet} OS: $($os.Caption)`n  ${bullet} ProductType: $($os.ProductType) (1=Workstation, 2=Domain Controller, 3=Server)"
                $errorMsg += "`n`n${tip} Tip: This module is designed for Windows Server installations only."

                Write-ToLog -Message "Platform check failed: Windows Server not detected (ProductType: $($os.ProductType))." -Level ERROR
                $checksFailed++
                throw $errorMsg
            }

            Write-ToLog -Message "Platform validated: Windows Server detected ($($os.Caption))." -Level DEBUG
            $checksPassed++
        } catch {
            Write-ToLog -Message "Platform validation error: $($_.Exception.Message)" -Level ERROR
            $checksFailed++
            throw
        }

        # Elevation check: Admin privileges required for Get-WindowsFeature
        $checksPerformed++
        try {
            $currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
            $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

            if (-not $isAdmin) {
                $tip = if ($PSStyle) { "$($PSStyle.Foreground.Yellow)ℹ$($PSStyle.Reset)" } else { "ℹ" }
                $errorMsg = "Elevation check failed: Administrative privileges required."
                $errorMsg += "`n`n${tip} Tip: Run PowerShell as Administrator to perform preflight checks."

                Write-ToLog -Message "Elevation check failed: Administrative privileges required." -Level ERROR
                $checksFailed++
                throw $errorMsg
            }

            Write-ToLog -Message "Elevation validated: Running with administrative privileges." -Level DEBUG
            $checksPassed++
        } catch {
            Write-ToLog -Message "Elevation check error: $($_.Exception.Message)" -Level ERROR
            $checksFailed++
            throw
        }
    }

    process {
        if ($_earlyExit) { return }

        # Feature validation
        if ($RequiredFeatures.Count -gt 0) {
            Write-ToLog -Message "Validating $($RequiredFeatures.Count) required feature(s)..." -Level INFO

            foreach ($featureName in $RequiredFeatures) {
                $checksPerformed++

                try {
                    $feature = Get-WindowsFeatureWrapper -Name $featureName

                    if (-not $feature) {
                        # Enhanced error: show available features
                        $bullet = if ($PSStyle) { "$($PSStyle.Foreground.Cyan)•$($PSStyle.Reset)" } else { "•" }
                        $tip = if ($PSStyle) { "$($PSStyle.Foreground.Yellow)ℹ$($PSStyle.Reset)" } else { "ℹ" }

                        $errorMsg = "Feature '$featureName' not found on server."

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
                        } catch {
                            # Best-effort only — log at WARN but do not prevent the parent error from throwing
                            Write-ToLog -Message "Could not retrieve available feature list: $($_.Exception.Message)" -Level WARN
                        }

                        Write-ToLog -Message "Feature '$featureName' not found on server." -Level ERROR
                        $checksFailed++
                        throw $errorMsg
                    } elseif (-not $feature.Installed) {
                        Write-ToLog -Message "Feature '$featureName' is not installed (but is available)." -Level WARN
                        $checksFailed++
                    } else {
                        Write-ToLog -Message "Feature '$featureName' is installed." -Level DEBUG
                        $checksPassed++
                    }
                } catch {
                    Write-ToLog -Message "Feature validation error for '$featureName': $($_.Exception.Message)" -Level ERROR
                    $checksFailed++
                    throw
                }
            }
        }

        # Path and disk space validation
        if ($RequiredPaths.Count -gt 0) {
            Write-ToLog -Message "Validating $($RequiredPaths.Count) required path(s)..." -Level INFO

            foreach ($path in $RequiredPaths) {
                $checksPerformed++

                try {
                    if (-not (Test-PathWrapper -Path $path)) {
                        $bullet = if ($PSStyle) { "$($PSStyle.Foreground.Cyan)•$($PSStyle.Reset)" } else { "•" }
                        $tip = if ($PSStyle) { "$($PSStyle.Foreground.Yellow)ℹ$($PSStyle.Reset)" } else { "ℹ" }

                        $errorMsg = "Required path '$path' does not exist."
                        $parentPath = Split-Path -Path $path -Parent

                        if ($parentPath -and (Test-PathWrapper -Path $parentPath)) {
                            $errorMsg += "`n`n${tip} Tip: Parent directory exists at '$parentPath'. Create the directory or verify the path is correct."
                        } else {
                            $errorMsg += "`n`n${tip} Tip: Verify the path is correct and accessible."
                        }

                        Write-ToLog -Message "Required path '$path' does not exist." -Level ERROR
                        $checksFailed++
                        throw $errorMsg
                    }

                    Write-ToLog -Message "Required path '$path' exists." -Level DEBUG
                    $checksPassed++

                    # Check disk space for this path
                    $checksPerformed++
                    $driveLetter = [System.IO.Path]::GetPathRoot($path) -replace '\\$', ''
                    $drive = Get-PSDrive | Where-Object { $_.Root -eq "$driveLetter\" }

                    if ($null -ne $drive -and $drive.Free -lt $MinDiskGB * 1GB) {
                        $freeGB = [Math]::Round($drive.Free / 1GB, 2)
                        $totalGB = [Math]::Round(($drive.Used + $drive.Free) / 1GB, 2)

                        $tip = if ($PSStyle) { "$($PSStyle.Foreground.Yellow)ℹ$($PSStyle.Reset)" } else { "ℹ" }

                        $errorMsg = "Insufficient disk space on drive $($drive.Name):."
                        $errorMsg += "`n`n  Required: $MinDiskGB GB"
                        $errorMsg += "`n  Available: $freeGB GB"
                        $errorMsg += "`n  Total: $totalGB GB"
                        $errorMsg += "`n`n${tip} Tip: Free up at least $([Math]::Ceiling($MinDiskGB - $freeGB)) GB to meet requirements."

                        Write-ToLog -Message "Insufficient disk space on $($drive.Name): $freeGB GB free, $MinDiskGB GB required." -Level ERROR
                        $checksFailed++
                        throw $errorMsg
                    }

                    if ($null -ne $drive) {
                        $freeGB = [Math]::Round($drive.Free / 1GB, 2)
                        Write-ToLog -Message "Disk space validated for drive $($drive.Name): $freeGB GB free (required: $MinDiskGB GB)." -Level DEBUG
                        $checksPassed++
                    }
                } catch {
                    Write-ToLog -Message "Path validation error for '$path': $($_.Exception.Message)" -Level ERROR
                    $checksFailed++
                    throw
                }
            }
        }
    }

    end {
        if ($_earlyExit) {
            return $false
        }

        # Metrics reporting
        $successRate = if ($checksPerformed -gt 0) {
            [Math]::Round(($checksPassed / $checksPerformed) * 100, 2)
        } else {
            0
        }

        Write-ToLog -Message "Preflight checks completed - Total: $checksPerformed, Passed: $checksPassed, Failed: $checksFailed, Success Rate: $successRate%" -Level INFO

        if ($checksFailed -eq 0) {
            Write-ToLog -Message "All preflight checks passed successfully." -Level SUCCESS
            return $true
        } else {
            Write-ToLog -Message "Preflight checks failed: $checksFailed of $checksPerformed checks did not pass." -Level ERROR
            return $false
        }
    }
}

# NOTE: Get-WindowsFeatureWrapper is defined in Install-ADModule.ps1
# Both files are dot-sourced into the same module scope, so the shared
# wrapper function is available here without duplication.
