#Requires -Version 7.0

# Disconnects the active Azure session. Idempotent — skips if no context is active.
# Verifies disconnection post-operation. Metrics in end block.
# No platform/elevation checks — owned by Test-PreflightCheck (DRY).
function Disconnect-FromAzure {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param ()

    begin {
        Write-ToLog -Message 'Starting Azure disconnection process...' -Level INFO

        $disconnectionsAttempted = 0
        $disconnectionsSucceeded = 0
        $disconnectionsSkipped = 0
        $lastError = $null
    }

    process {
        try {
            # Check for an active session before attempting to disconnect
            $existingContext = Get-AzContextWrapper
            if (-not $existingContext) {
                Write-ToLog -Message 'No active Azure context found. Skipping disconnection.' -Level DEBUG
                $disconnectionsSkipped++
                return
            }

            $disconnectionsAttempted++
            $accountName = $existingContext.Account
            Write-ToLog -Message "Active Azure context found for account '$accountName'. Initiating disconnection..." -Level INFO

            if ($PSCmdlet.ShouldProcess("Azure account '$accountName'", 'Disconnect-AzAccount')) {
                Disconnect-AzAccountWrapper

                # Verify the session was cleared
                $remainingContext = Get-AzContextWrapper
                if (-not $remainingContext) {
                    Write-ToLog -Message "Successfully disconnected from Azure account '$accountName'." -Level SUCCESS
                    $disconnectionsSucceeded++
                } else {
                    $bullet = if ($PSStyle) { "$($PSStyle.Foreground.Red)•$($PSStyle.Reset)" } else { "`e[31m•`e[0m" }
                    $tip = if ($PSStyle) { "$($PSStyle.Foreground.Yellow)ℹ$($PSStyle.Reset)" } else { "`e[33mℹ`e[0m" }

                    $errorMsg = "Disconnection verification failed: Azure context still present after Disconnect-AzAccount."
                    $errorMsg += "`n`n${tip} Tips:"
                    $errorMsg += "`n  ${bullet} Retry Disconnect-FromAzure"
                    $errorMsg += "`n  ${bullet} Run Disconnect-AzAccount -Username '$accountName' manually"

                    Write-ToLog -Message 'Disconnection verification failed: Azure context still present.' -Level ERROR
                    $lastError = [System.Management.Automation.ErrorRecord]::new(
                        [System.InvalidOperationException]::new($errorMsg),
                        'AzureDisconnectVerificationFailed',
                        [System.Management.Automation.ErrorCategory]::InvalidResult,
                        $null
                    )
                }
            }
        } catch {
            Write-ToLog -Message "Azure disconnection failed: $($_.Exception.Message)" -Level ERROR
            $lastError = $_
        }
    }

    end {
        Write-ToLog -Message "Azure disconnection completed - Attempted: $disconnectionsAttempted, Succeeded: $disconnectionsSucceeded, Skipped: $disconnectionsSkipped" -Level INFO

        if ($lastError) {
            Write-ToLog -Message 'Azure disconnection completed with errors.' -Level WARN
        } elseif ($disconnectionsSucceeded -gt 0) {
            Write-ToLog -Message 'Azure disconnection completed successfully.' -Level SUCCESS
        }

        if ($lastError) {
            $PSCmdlet.ThrowTerminatingError($lastError)
        }
    }
}

# ============================================================================
# WRAPPER FUNCTIONS FOR MOCKABILITY
# ============================================================================

# Wraps Get-AzContext for Pester mocking.
function Get-AzContextWrapper {
    [CmdletBinding()]
    [OutputType([object])]
    param()

    Get-AzContext -ErrorAction SilentlyContinue
}

# Wraps Disconnect-AzAccount for Pester mocking.
function Disconnect-AzAccountWrapper {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Wrapper function; ShouldProcess handled by calling function Disconnect-FromAzure.')]
    [OutputType([void])]
    param()

    Disconnect-AzAccount -Confirm:$false
}
