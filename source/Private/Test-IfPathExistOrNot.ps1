#Requires -Version 7.0

# Validates that all provided paths exist, collecting ALL missing paths before throwing.
# Reports a count of checked/found/missing paths. Wrapper: Test-PathWrapper.
function Test-IfPathExistOrNot {
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Position = 0, Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Paths
    )

    begin {
        Write-ToLog -Message "Starting path validation for $($Paths.Count) path(s)" -Level INFO
    }

    process {
        $missingPaths = @()
        $existingPaths = @()

        # Batch validation: collect all results before throwing
        foreach ($Path in $Paths) {
            try {
                if (Test-PathWrapper -Path $Path) {
                    Write-ToLog -Message "Path verified: $Path" -Level DEBUG
                    $existingPaths += $Path
                } else {
                    Write-ToLog -Message "Path not found: $Path" -Level ERROR
                    $missingPaths += $Path
                }
            } catch {
                Write-ToLog -Message "Error checking path '$Path': $($_.Exception.Message)" -Level ERROR
                $missingPaths += $Path
            }
        }

        # Report metrics
        $totalCount = $Paths.Count
        $existCount = $existingPaths.Count
        $missingCount = $missingPaths.Count
        $successRate = if ($totalCount -gt 0) { [Math]::Round(($existCount / $totalCount) * 100, 2) } else { 0 }

        Write-ToLog -Message "Path validation complete - Total: $totalCount, Exist: $existCount, Missing: $missingCount, Success Rate: $successRate%" -Level INFO

        # If any paths are missing, throw with full context
        if ($missingCount -gt 0) {
            $bullet = if ($PSStyle) { "$($PSStyle.Foreground.Red)✗$($PSStyle.Reset)" } else { "✗" }
            $checkmark = if ($PSStyle) { "$($PSStyle.Foreground.Green)✓$($PSStyle.Reset)" } else { "✓" }
            $tip = if ($PSStyle) { "$($PSStyle.Foreground.Yellow)ℹ$($PSStyle.Reset)" } else { "ℹ" }

            $errorMsg = "Path validation failed: $missingCount of $totalCount path(s) not found."

            # List missing paths
            $missingList = $missingPaths | ForEach-Object {
                "  ${bullet} $_"
            }
            $errorMsg += "`n`nMissing paths:`n$($missingList -join "`n")"

            # Show existing paths for context (if any)
            if ($existCount -gt 0) {
                $existingList = $existingPaths | ForEach-Object {
                    "  ${checkmark} $_"
                }
                $errorMsg += "`n`nExisting paths (for context):`n$($existingList -join "`n")"
            }

            # Add actionable tip
            $errorMsg += "`n`n${tip} Tip: Verify that the missing paths are correct and that the file system is accessible."

            throw $errorMsg
        }

        Write-ToLog -Message "All $totalCount path(s) validated successfully" -Level SUCCESS
    }
}

# Helper function for mockability in tests
function Test-PathWrapper {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Wrapper function for testing purposes only; does not change state. Only queries path existence.')]
    param(
        [Parameter(Mandatory)]
        [string]
        $Path,

        [Parameter()]
        [string]
        $PathType
    )

    if ($PathType) {
        return Test-Path -Path $Path -PathType $PathType
    } else {
        return Test-Path -Path $Path
    }
}