#Requires -Version 7.0

# Authenticates to Azure using the strongest method the caller supplies.
# Idempotent — skips if an active Az context already exists, for every parameter set.
# -UseExistingContext makes that behavior an explicit, checkable request: it requires
# a context to already be active and throws an actionable error if one is not, instead
# of silently falling through to an authentication attempt.
# Methods otherwise, strongest first: Managed Identity, Workload Identity Federation,
# Certificate (app-only), Client Secret (app-only), Interactive Browser, Device Code
# (last resort). Device code is never the only path here — it is the default only
# because no unattended credential was supplied, and a Conditional Access block is
# detected and reworded to point at the other parameter sets. No platform/elevation
# checks (DRY).
function Connect-ToAzure {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'DeviceCode')]
    [OutputType([void])]
    param (
        [Parameter(ParameterSetName = 'ExistingContext', Mandatory)]
        [switch]
        $UseExistingContext,

        [Parameter(ParameterSetName = 'ManagedIdentity', Mandatory)]
        [switch]
        $UseManagedIdentity,

        [Parameter(ParameterSetName = 'ManagedIdentity')]
        [ValidateNotNullOrEmpty()]
        [string]
        $ManagedIdentityClientId,

        [Parameter(ParameterSetName = 'WorkloadIdentityFederation', Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $FederatedToken,

        [Parameter(ParameterSetName = 'WorkloadIdentityFederation', Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $ApplicationId,

        [Parameter(ParameterSetName = 'Certificate', Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $CertificateThumbprint,

        [Parameter(ParameterSetName = 'Certificate', Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $CertificateApplicationId,

        [Parameter(ParameterSetName = 'WorkloadIdentityFederation', Mandatory)]
        [Parameter(ParameterSetName = 'Certificate', Mandatory)]
        [Parameter(ParameterSetName = 'ClientSecret', Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $TenantId,

        [Parameter(ParameterSetName = 'ClientSecret', Mandatory)]
        [ValidateNotNullOrEmpty()]
        [pscredential]
        $ServicePrincipalCredential,

        [Parameter(ParameterSetName = 'Interactive', Mandatory)]
        [switch]
        $UseInteractiveBrowser,

        [Parameter(ParameterSetName = 'DeviceCode')]
        [switch]
        $UseDeviceCode,

        [Parameter()]
        [ValidateRange(1, 120)]
        [int]$TimeoutMinutes = 90
    )

    begin {
        Write-ToLog -Message "Starting Azure authentication process (method: $($PSCmdlet.ParameterSetName))..." -Level INFO

        $connectionsAttempted = 0
        $connectionsSucceeded = 0
        $connectionsFailed    = 0
        $lastError            = $null
    }

    process {
        try {
            # Check for an existing active session — return early if already connected,
            # for every parameter set (idempotency).
            $existingContext = Get-AzContextWrapper
            if ($existingContext) {
                Write-ToLog -Message "Active Azure context found for account '$($existingContext.Account)'. Skipping authentication." -Level DEBUG
                $connectionsSucceeded++
                return
            }

            if ($PSCmdlet.ParameterSetName -eq 'ExistingContext') {
                # Caller explicitly asked to reuse whatever session is already active.
                # None exists — that is this parameter set's error condition, not a
                # reason to fall through to an authentication attempt.
                $errorMsg  = 'No active Azure context found, and -UseExistingContext requires one to already exist.'
                $errorMsg += ' Connect first with -UseManagedIdentity, -FederatedToken/-ApplicationId/-TenantId,'
                $errorMsg += ' -CertificateThumbprint/-CertificateApplicationId/-TenantId, -ServicePrincipalCredential/-TenantId,'
                $errorMsg += ' -UseInteractiveBrowser, or device code (no parameters).'
                Write-ToLog -Message $errorMsg -Level ERROR
                throw $errorMsg
            }

            $connectionsAttempted++

            if ($PSCmdlet.ParameterSetName -eq 'DeviceCode') {
                # Last resort — Microsoft recommends blocking this flow tenant-wide, and it
                # is the easiest to phish (an attacker starts the flow and asks the target
                # to enter the code). Only reached when no unattended credential was supplied.
                Write-ToLog -Message 'No unattended credential supplied. Falling back to device-code sign-in (last resort). If this tenant blocks device code via Conditional Access, use -UseManagedIdentity, -FederatedToken/-ApplicationId/-TenantId, -CertificateThumbprint/-CertificateApplicationId/-TenantId, or -ServicePrincipalCredential/-TenantId instead.' -Level WARN
                Write-Information 'ACTION REQUIRED: complete device-code sign-in at https://microsoft.com/devicelogin' -InformationAction Continue
            }
            else {
                Write-ToLog -Message "No active Azure context found. Authenticating via '$($PSCmdlet.ParameterSetName)'..." -Level INFO
            }

            if ($PSCmdlet.ShouldProcess('Azure', "Connect-AzAccount ($($PSCmdlet.ParameterSetName))")) {
                try {
                    switch ($PSCmdlet.ParameterSetName) {
                        'ManagedIdentity' {
                            if ($PSBoundParameters.ContainsKey('ManagedIdentityClientId')) {
                                Connect-AzAccountManagedIdentityWrapper -AccountId $ManagedIdentityClientId
                            }
                            else {
                                Connect-AzAccountManagedIdentityWrapper
                            }
                        }
                        'WorkloadIdentityFederation' {
                            Connect-AzAccountWorkloadIdentityWrapper -ApplicationId $ApplicationId -TenantId $TenantId -FederatedToken $FederatedToken
                        }
                        'Certificate' {
                            Connect-AzAccountCertificateWrapper -ApplicationId $CertificateApplicationId -TenantId $TenantId -CertificateThumbprint $CertificateThumbprint
                        }
                        'ClientSecret' {
                            Connect-AzAccountClientSecretWrapper -Credential $ServicePrincipalCredential -TenantId $TenantId
                        }
                        'Interactive' {
                            Connect-AzAccountInteractiveWrapper
                        }
                        default {
                            # DeviceCode
                            Connect-AzAccountWrapper
                        }
                    }
                }
                catch {
                    # Detect a Conditional Access block on the device-code flow and reword it
                    # actionably rather than letting a raw MSAL/Az error reach the operator.
                    if ($PSCmdlet.ParameterSetName -eq 'DeviceCode' -and
                        $_.Exception.Message -match '50079|50076|53003|70016|500131|730016|(?i)conditional access') {
                        $blockedMsg  = 'Device-code sign-in was blocked, most likely by a Conditional Access policy in this tenant.'
                        $blockedMsg += ' Retry with an unattended method instead: -UseManagedIdentity, -FederatedToken/-ApplicationId/-TenantId,'
                        $blockedMsg += ' -CertificateThumbprint/-CertificateApplicationId/-TenantId, or -ServicePrincipalCredential/-TenantId.'
                        Write-ToLog -Message $blockedMsg -Level ERROR
                        throw $blockedMsg
                    }
                    throw
                }

                # Poll until context is confirmed or timeout is reached. Synchronous methods
                # (managed identity, certificate, client secret, workload identity) normally
                # resolve on the first check; interactive/device-code sign-in may take longer.
                $timeout   = [System.TimeSpan]::FromMinutes($TimeoutMinutes)
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

                while (-not (Test-TimeoutElapsedWrapper -Stopwatch $stopwatch -Timeout $timeout)) {
                    $confirmedContext = Get-AzContextWrapper
                    if ($confirmedContext) {
                        Write-ToLog -Message "Successfully connected to Azure as '$($confirmedContext.Account)'." -Level SUCCESS
                        $connectionsSucceeded++
                        return
                    }

                    Start-Sleep -Seconds 5

                    $elapsedMin = [Math]::Round($stopwatch.Elapsed.TotalMinutes, 1)
                    Write-ToLog -Message "Waiting for Azure authentication... ($elapsedMin / $TimeoutMinutes minutes elapsed)" -Level DEBUG
                }

                # Timeout reached — build actionable error message with PSStyle hints
                $bullet = if ($PSStyle) { "$($PSStyle.Foreground.Red)•$($PSStyle.Reset)" } else { "`e[31m•`e[0m" }
                $tip    = if ($PSStyle) { "$($PSStyle.Foreground.Yellow)ℹ$($PSStyle.Reset)" } else { "`e[33mℹ`e[0m" }

                $errorMsg  = "Azure authentication timed out after $TimeoutMinutes minute(s)."
                $errorMsg += "`n`n${tip} Tips:"
                if ($PSCmdlet.ParameterSetName -eq 'DeviceCode') {
                    $errorMsg += "`n  ${bullet} Complete the device-code sign-in at https://microsoft.com/devicelogin"
                }
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

# Wraps Connect-AzAccount (device code) for Pester mocking. Last-resort delegated flow.
function Connect-AzAccountWrapper {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Wrapper function; ShouldProcess handled by calling function Connect-ToAzure.')]
    [OutputType([void])]
    param()

    Connect-AzAccount -UseDeviceAuthentication
}

# Wraps Connect-AzAccount -Identity for Pester mocking. System- or user-assigned managed identity.
function Connect-AzAccountManagedIdentityWrapper {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Wrapper function; ShouldProcess handled by calling function Connect-ToAzure.')]
    [OutputType([void])]
    param (
        [Parameter()]
        [string]
        $AccountId
    )

    $connectParams = @{ Identity = $true }
    if ($PSBoundParameters.ContainsKey('AccountId')) {
        $connectParams['AccountId'] = $AccountId
    }

    Connect-AzAccount @connectParams
}

# Wraps Connect-AzAccount with a federated (workload identity) token for Pester mocking.
function Connect-AzAccountWorkloadIdentityWrapper {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Wrapper function; ShouldProcess handled by calling function Connect-ToAzure.')]
    [OutputType([void])]
    param (
        [Parameter(Mandatory)]
        [string]
        $ApplicationId,

        [Parameter(Mandatory)]
        [string]
        $TenantId,

        [Parameter(Mandatory)]
        [string]
        $FederatedToken
    )

    Connect-AzAccount -ApplicationId $ApplicationId -Tenant $TenantId -FederatedToken $FederatedToken
}

# Wraps Connect-AzAccount -ServicePrincipal with a certificate for Pester mocking. App-only.
function Connect-AzAccountCertificateWrapper {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Wrapper function; ShouldProcess handled by calling function Connect-ToAzure.')]
    [OutputType([void])]
    param (
        [Parameter(Mandatory)]
        [string]
        $ApplicationId,

        [Parameter(Mandatory)]
        [string]
        $TenantId,

        [Parameter(Mandatory)]
        [string]
        $CertificateThumbprint
    )

    Connect-AzAccount -ServicePrincipal -ApplicationId $ApplicationId -Tenant $TenantId -CertificateThumbprint $CertificateThumbprint
}

# Wraps Connect-AzAccount -ServicePrincipal with a client secret for Pester mocking. Last-resort app-only.
function Connect-AzAccountClientSecretWrapper {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Wrapper function; ShouldProcess handled by calling function Connect-ToAzure.')]
    [OutputType([void])]
    param (
        [Parameter(Mandatory)]
        [pscredential]
        $Credential,

        [Parameter(Mandatory)]
        [string]
        $TenantId
    )

    Connect-AzAccount -ServicePrincipal -Credential $Credential -Tenant $TenantId
}

# Wraps interactive-browser Connect-AzAccount for Pester mocking. A human at a workstation.
function Connect-AzAccountInteractiveWrapper {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Wrapper function; ShouldProcess handled by calling function Connect-ToAzure.')]
    [OutputType([void])]
    param()

    Connect-AzAccount
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
