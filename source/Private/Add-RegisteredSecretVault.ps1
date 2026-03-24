#Requires -Version 7.0

# Registers an Azure Key Vault as a SecretManagement vault and verifies registration.
# Idempotent — skips if the vault name is already registered. Metrics in end block.
# No platform/elevation checks — owned by Test-PreflightCheck (DRY).
function Add-RegisteredSecretVault {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ModuleName = 'Az.KeyVault',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$SubscriptionId
    )

    begin {
        Write-ToLog -Message 'Starting secret vault registration process...' -Level INFO

        $vaultsAttempted  = 0
        $vaultsRegistered = 0
        $vaultsSkipped    = 0
        $vaultsFailed     = 0
        $lastError        = $null
    }

    process {
        try {
            # Resolve Name from current vault if not supplied
            if (-not $PSBoundParameters.ContainsKey('Name')) {
                $vaultInfo = Get-Vault
                if (-not $vaultInfo) {
                    $errorMsg = 'No -Name supplied and Get-Vault returned no Key Vaults in the current context.'
                    Write-ToLog -Message $errorMsg -Level ERROR
                    $vaultsFailed++
                    $lastError = [System.Management.Automation.ErrorRecord]::new(
                        [System.InvalidOperationException]::new($errorMsg),
                        'NoKeyVaultFound',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                        $null
                    )
                    return
                }
                $Name = $vaultInfo.VaultName
            }

            Write-ToLog -Message "Processing secret vault registration for '$Name'..." -Level DEBUG
            $vaultsAttempted++

            # Resolve SubscriptionId from current context if not supplied
            if (-not $PSBoundParameters.ContainsKey('SubscriptionId')) {
                $azContext = Get-AzContextWrapper
                if (-not $azContext) {
                    $errorMsg = 'No -SubscriptionId supplied and no active Azure context found.'
                    Write-ToLog -Message $errorMsg -Level ERROR
                    $vaultsFailed++
                    $lastError = [System.Management.Automation.ErrorRecord]::new(
                        [System.InvalidOperationException]::new($errorMsg),
                        'NoAzureContext',
                        [System.Management.Automation.ErrorCategory]::AuthenticationError,
                        $null
                    )
                    return
                }
                $SubscriptionId = $azContext.Subscription.Id
            }

            # Check if already registered — idempotent
            $existingVault = Get-SecretVaultWrapper -Name $Name
            if ($existingVault) {
                Write-ToLog -Message "Secret vault '$Name' is already registered. Skipping." -Level DEBUG
                $vaultsSkipped++
                return
            }

            # Register the vault
            $vaultParameters = @{
                AZKVaultName   = $Name
                SubscriptionId = $SubscriptionId
            }

            Write-ToLog -Message "Registering secret vault '$Name' (Module: $ModuleName, Subscription: $SubscriptionId)..." -Level INFO

            if ($PSCmdlet.ShouldProcess($Name, 'Register-SecretVault')) {
                Register-SecretVaultWrapper -Name $Name -ModuleName $ModuleName -VaultParameters $vaultParameters

                # Post-register verification
                $verifiedVault = Get-SecretVaultWrapper -Name $Name
                if ($verifiedVault) {
                    Write-ToLog -Message "Secret vault '$Name' registered successfully." -Level SUCCESS
                    $vaultsRegistered++
                }
                else {
                    $bullet = if ($PSStyle) { "$($PSStyle.Foreground.Red)•$($PSStyle.Reset)" } else { "`e[31m•`e[0m" }
                    $tip    = if ($PSStyle) { "$($PSStyle.Foreground.Yellow)ℹ$($PSStyle.Reset)" } else { "`e[33mℹ`e[0m" }

                    $errorMsg  = "Post-register verification failed: vault '$Name' not found after Register-SecretVault."
                    $errorMsg += "`n`n${tip} Tips:"
                    $errorMsg += "`n  ${bullet} Confirm the Az.KeyVault module is installed"
                    $errorMsg += "`n  ${bullet} Verify the Key Vault name and subscription are correct"
                    $errorMsg += "`n  ${bullet} Run Get-SecretVault to inspect registered vaults"

                    Write-ToLog -Message "Post-register verification failed for '$Name'." -Level ERROR
                    $vaultsFailed++
                    $lastError = [System.Management.Automation.ErrorRecord]::new(
                        [System.InvalidOperationException]::new($errorMsg),
                        'SecretVaultVerificationFailed',
                        [System.Management.Automation.ErrorCategory]::InvalidResult,
                        $null
                    )
                }
            }
        }
        catch {
            Write-ToLog -Message "Failed to register secret vault '$Name': $($_.Exception.Message)" -Level ERROR
            $vaultsFailed++
            $lastError = $_
        }
    }

    end {
        $successRate = if ($vaultsAttempted -gt 0) {
            [Math]::Round((($vaultsRegistered + $vaultsSkipped) / $vaultsAttempted) * 100, 2)
        }
        else { 0 }

        Write-ToLog -Message "Secret vault registration completed - Total: $vaultsAttempted, Registered: $vaultsRegistered, Skipped: $vaultsSkipped, Failed: $vaultsFailed, Success Rate: $successRate%" -Level INFO

        if ($vaultsFailed -gt 0) {
            Write-ToLog -Message "Secret vault registration completed with $vaultsFailed failure(s)." -Level WARN
        }
        elseif ($vaultsRegistered -gt 0) {
            Write-ToLog -Message 'Secret vault registration completed successfully.' -Level SUCCESS
        }

        if ($lastError) {
            $PSCmdlet.ThrowTerminatingError($lastError)
        }
    }
}

# ============================================================================
# WRAPPER FUNCTIONS FOR MOCKABILITY
# ============================================================================

# Wraps Get-SecretVault for Pester mocking.
function Get-SecretVaultWrapper {
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter()]
        [string]$Name
    )

    if ($Name) {
        return Get-SecretVault -Name $Name -ErrorAction SilentlyContinue
    }
    else {
        return Get-SecretVault -ErrorAction SilentlyContinue
    }
}

# Wraps Register-SecretVault for Pester mocking.
function Register-SecretVaultWrapper {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Wrapper function; ShouldProcess handled by calling function Add-RegisteredSecretVault.')]
    [OutputType([void])]
    param (
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$ModuleName,

        [Parameter(Mandatory)]
        [hashtable]$VaultParameters
    )

    Register-SecretVault -Name $Name -ModuleName $ModuleName -VaultParameters $VaultParameters -Confirm:$false
}

# Wraps Get-AzContext for Pester mocking.
function Get-AzContextWrapper {
    [CmdletBinding()]
    [OutputType([object])]
    param()

    Get-AzContext -ErrorAction SilentlyContinue
}
