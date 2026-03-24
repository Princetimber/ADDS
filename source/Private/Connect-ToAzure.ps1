#Requires -Version 7.0

# Authenticates to Azure via interactive device-code login.
# Idempotent — skips if an active Az context already exists.
# Polls every 5 s up to -TimeoutMinutes. No platform/elevation checks (DRY).
function Connect-ToAzure {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param (
        [Parameter()]
        [ValidateRange(1, 120)]
        [int]$TimeoutMinutes = 90
    )

    begin {
        Write-ToLog -Message 'Starting Azure authentication process...' -Level INFO

        $connectionsAttempted = 0
        $connectionsSucceeded = 0
        $connectionsFailed    = 0
        $lastError            = $null
    }

    process {
        try {
            # Check for an existing active session — return early if already connected
            $existingContext = Get-AzContextWrapper
            if ($existingContext) {
                Write-ToLog -Message "Active Azure context found for account '$($existingContext.Account)'. Skipping authentication." -Level DEBUG
                $connectionsSucceeded++
                return
            }

            # Initiate device-code authentication
            $connectionsAttempted++
            Write-ToLog -Message 'No active Azure context found. Initiating device-code authentication...' -Level INFO

            if ($PSCmdlet.ShouldProcess('Azure', 'Connect-AzAccount')) {
                Connect-AzAccountWrapper

                # Poll until context is confirmed or timeout is reached
                $timeout   = [System.TimeSpan]::FromMinutes($TimeoutMinutes)
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

                while (-not (Test-TimeoutElapsedWrapper -Stopwatch $stopwatch -Timeout $timeout)) {
                    Start-Sleep -Seconds 5

                    $confirmedContext = Get-AzContextWrapper
                    if ($confirmedContext) {
                        Write-ToLog -Message "Successfully connected to Azure as '$($confirmedContext.Account)'." -Level SUCCESS
                        $connectionsSucceeded++
                        return
                    }

                    $elapsedMin = [Math]::Round($stopwatch.Elapsed.TotalMinutes, 1)
                    Write-ToLog -Message "Waiting for Azure authentication... ($elapsedMin / $TimeoutMinutes minutes elapsed)" -Level DEBUG
                }

                # Timeout reached — build actionable error message with PSStyle hints
                $bullet = if ($PSStyle) { "$($PSStyle.Foreground.Red)•$($PSStyle.Reset)" } else { "`e[31m•`e[0m" }
                $tip    = if ($PSStyle) { "$($PSStyle.Foreground.Yellow)ℹ$($PSStyle.Reset)" } else { "`e[33mℹ`e[0m" }

                $errorMsg  = "Azure authentication timed out after $TimeoutMinutes minute(s)."
                $errorMsg += "`n`n${tip} Tips:"
                $errorMsg += "`n  ${bullet} Complete the device-code sign-in at https://microsoft.com/devicelogin"
                $errorMsg += "`n  ${bullet} Increase -TimeoutMinutes if more time is needed (max 120)"
                $errorMsg += "`n  ${bullet} Verify network connectivity to Azure endpoints"

                Write-ToLog -Message "Azure authentication timed out after $TimeoutMinutes minute(s)." -Level ERROR
                $connectionsFailed++

                # Store error for re-throw in end block (allows metrics to be reported first)
                $exception = [System.TimeoutException]::new($errorMsg)
                $lastError = [System.Management.Automation.ErrorRecord]::new(
                    $exception, 'AzureAuthenticationTimeout',
                    [System.Management.Automation.ErrorCategory]::OperationTimeout,
                    $null
                )
            }
        }
        catch {
            Write-ToLog -Message "Azure authentication failed: $($_.Exception.Message)" -Level ERROR
            $connectionsFailed++
            # Store error for re-throw in end block (allows metrics to be reported first)
            $lastError = $_
        }
    }

    end {
        # Metrics are always reported, even on failure
        Write-ToLog -Message "Azure authentication completed - Attempted: $connectionsAttempted, Succeeded: $connectionsSucceeded, Failed: $connectionsFailed" -Level INFO

        if ($connectionsFailed -gt 0) {
            Write-ToLog -Message "Azure authentication completed with $connectionsFailed failure(s)." -Level WARN
        }
        elseif ($connectionsSucceeded -gt 0) {
            Write-ToLog -Message 'Azure authentication completed successfully.' -Level SUCCESS
        }

        # Re-throw any stored error after metrics have been reported
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

# Wraps Connect-AzAccount for Pester mocking.
function Connect-AzAccountWrapper {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Wrapper function; ShouldProcess handled by calling function Connect-ToAzure.')]
    [OutputType([void])]
    param()

    Connect-AzAccount -UseDeviceAuthentication
}

# Wraps the timeout-elapsed check for Pester mocking.
function Test-TimeoutElapsedWrapper {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [System.Diagnostics.Stopwatch]$Stopwatch,

        [Parameter(Mandatory)]
        [System.TimeSpan]$Timeout
    )

    return $Stopwatch.Elapsed -ge $Timeout
}
